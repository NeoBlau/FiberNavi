"""python3 -m unittest tools/voice_tagger/test_voice_tagger.py"""
import io
import json
import math
import shutil
import sys
import tempfile
import unittest
import wave
from array import array
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import voice_tagger as vt  # noqa: E402

RATE = 44100


def speech_like(path: Path, words: list[tuple[float, float]], total: float):
    """Тишина с «словами» — тональными вспышками на заданных интервалах."""
    samples = array("h", [0] * int(total * RATE))
    for s, e in words:
        for i in range(int(s * RATE), int(e * RATE)):
            env = math.sin(math.pi * (i - s * RATE) / ((e - s) * RATE))
            samples[i] = int(12000 * env * math.sin(i * 2 * math.pi * 220 / RATE))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(samples.tobytes())


class RulesTests(unittest.TestCase):
    def test_suggestions(self):
        cases = {
            "Turn left up here, homie!": ("turn", ["turn_left"]),
            "Keep right, keep right.": ("turn", ["keep_right"]),
            "Alright, we're here.": ("arrival", ["arrived"]),
            "Yo, where you going? Wrong way!": ("reroute", ["reroute"]),
            "Slow down, man, you gonna kill us!": ("speeding", ["speeding"]),
            "Aight, let's go.": ("confirm", ["confirm", "route_start"]),
            "Man, this traffic is killing me.": ("chatter", ["traffic_jam"]),
            "Grove Street. Home. At least it was before I messed everything up.": ("chatter", ["long_straight", "long_stop"]),
            "": ("none", []),
        }
        for text, (event, app) in cases.items():
            got = vt.suggest_event(text)
            self.assertEqual((got[0], got[2]), (event, app), text)

    def test_explicit(self):
        self.assertEqual(vt.explicit_level("Hello there"), 0)
        self.assertEqual(vt.explicit_level("Damn, this is crazy"), 1)
        self.assertEqual(vt.explicit_level("What the fuck!"), 2)

    def test_word_tokens_merge_up_ahead_and_were(self):
        words = [{"w": " Up", "start": 0.1, "end": 0.2, "p": 0.9}, {"w": "ahead,", "start": 0.2, "end": 0.5, "p": 0.8},
                 {"w": "we", "start": 0.6, "end": 0.7, "p": 0.9}, {"w": "were", "start": 0.7, "end": 0.9, "p": 0.9}]
        toks = vt.word_tokens(words)
        self.assertEqual([t[0] for t in toks], ["up_ahead", "we", "we're"])
        self.assertEqual(toks[0][1:3], (0.1, 0.5))


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.voice = Path(tempfile.mkdtemp())
        speech_like(self.voice / "cj_0001.wav", [(0.2, 0.5), (0.6, 0.95)], 1.2)       # "turn left"
        speech_like(self.voice / "cj_0002.wav", [(0.1, 0.4), (0.45, 0.8)], 1.0)       # "we're here"
        speech_like(self.voice / "cj_0003.wav", [(0.1, 0.9)], 1.0)
        self.transcripts = self.voice / "tr.json"
        self.transcripts.write_text(json.dumps({
            "cj_0001.wav": {"text": "Turn left!", "words": [
                {"w": "Turn", "start": 0.2, "end": 0.5, "p": 0.95}, {"w": "left!", "start": 0.6, "end": 0.95, "p": 0.9}]},
            "cj_0002.wav": {"text": "We're here.", "words": [
                {"w": "We're", "start": 0.1, "end": 0.4, "p": 0.9}, {"w": "here.", "start": 0.45, "end": 0.8, "p": 0.92}]},
            "cj_0003.wav": {"text": "Grove Street, home of the gang.", "words": [
                {"w": "Grove", "start": 0.1, "end": 0.9, "p": 0.8}]},
        }))

    def tearDown(self):
        shutil.rmtree(self.voice)

    def run_cmd(self, *args):
        with redirect_stdout(io.StringIO()) as buf:
            code = vt.main(list(args))
        self.assertEqual(code, 0)
        return buf.getvalue()

    def test_suggest_then_build(self):
        self.run_cmd("suggest", "--voice", str(self.voice), "--transcripts", str(self.transcripts))
        tags = json.loads((self.voice / "tags.json").read_text())
        self.assertEqual([t["event"] for t in tags], ["turn", "arrival", "chatter"])
        self.assertTrue(all(0 < t["confidence"] <= 1 for t in tags))

        # Ручная правка не затирается повторным suggest.
        tags[2]["event"], tags[2]["app_events"], tags[2]["reviewed"] = "confirm", ["confirm"], True
        (self.voice / "tags.json").write_text(json.dumps(tags))
        self.run_cmd("suggest", "--voice", str(self.voice), "--transcripts", str(self.transcripts))
        self.assertEqual(json.loads((self.voice / "tags.json").read_text())[2]["event"], "confirm")

        log = self.run_cmd("build", "--voice", str(self.voice), "--character", "cj")
        m = json.loads((self.voice / "voice_manifest.json").read_text())
        self.assertEqual(m["character"], "cj")
        self.assertEqual({l["id"]: l["events"] for l in m["lines"]},
                         {"cj_0001": ["turn_left"], "cj_0002": ["arrived"], "cj_0003": ["confirm"]})
        self.assertEqual(set(m["words"]), {"turn", "left", "we're", "here"})
        take = m["words"]["left"][0]
        self.assertTrue((self.voice / take["file"]).exists())
        self.assertGreater(take["score"], 0.5)
        with wave.open(str(self.voice / take["file"])) as w:
            self.assertAlmostEqual(w.getnframes() / RATE, 0.35 + 0.06, delta=0.01)
        self.assertIn("now", log)  # нет слова «now» — предупреждение

    def test_rejected_takes_survive_rebuild(self):
        self.run_cmd("suggest", "--voice", str(self.voice), "--transcripts", str(self.transcripts))
        self.run_cmd("build", "--voice", str(self.voice), "--character", "cj")
        path = self.voice / "voice_manifest.json"
        m = json.loads(path.read_text())
        m["words"]["left"][0]["rejected"] = True
        path.write_text(json.dumps(m))
        self.run_cmd("build", "--voice", str(self.voice), "--character", "cj")
        self.assertTrue(json.loads(path.read_text())["words"]["left"][0].get("rejected"))

    def test_score_penalizes_cut_word(self):
        audio = vt.Audio.read(self.voice / "cj_0003.wav")
        clean = vt.take_score(audio.cut(0.1, 0.9), 0.9)
        clipped = vt.take_score(audio.cut(0.4, 0.6, pad=0), 0.9)
        self.assertGreater(clean, clipped)


if __name__ == "__main__":
    unittest.main()
