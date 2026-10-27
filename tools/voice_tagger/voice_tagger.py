#!/usr/bin/env python3
"""Разметка реплик персонажа для навигатора.

  1) suggest — Whisper расшифровывает все WAV и ПРЕДЛАГАЕТ событие каждой реплике:
       voice_tagger.py suggest --voice Assets/UserPacks/sanAndreas/voice/cj
     → tags.json (только предложения; финальную разметку правишь сам, руками или в review).

  2) review — локальная страница: слушаешь реплику, меняешь событие, бракуешь дубли слов,
     слушаешь склейку инструкции:
       voice_tagger.py review --voice .../voice/cj        (http://localhost:8765)

  3) build — из проверенного tags.json собирает voice_manifest.json и нарезает слова
     (left, right, turn, now, here…) из оригинальных записей:
       voice_tagger.py build --voice .../voice/cj --character cj

Нужны: Python 3.10+, openai-whisper (pip install openai-whisper) и ffmpeg — только для suggest.
Вход: WAV 16 бит моно (так их кладёт pack_tool).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import wave
from array import array
from dataclasses import dataclass
from pathlib import Path

# ------------------------------------------------------------------ правила событий

EVENTS = ["turn", "arrival", "reroute", "speeding", "confirm", "chatter", "none"]

ARRIVAL = [r"\bwe'?re here\b", r"\bhere we are\b", r"\bmade it\b", r"\barrived\b", r"\bthis is (it|the place)\b",
           r"\bwe here\b"]
REROUTE = [r"\bwrong way\b", r"\bturn (it )?around\b", r"\bwhere (are )?you going\b", r"\bmissed\b",
           r"\bwrong turn\b"]
SPEEDING = [r"\bslow (it )?down\b", r"\btoo fast\b", r"\bease up\b", r"\bwatch (your|the) speed\b"]
CONFIRM = [r"\bok(ay)?\b", r"\balright\b", r"\baight\b", r"\byeah\b", r"\blet'?s go\b", r"\bcome on\b",
           r"\bgot it\b", r"\bsure\b", r"\bcool\b", r"\bthis way\b", r"\bover there\b"]
TRAFFIC = [r"\btraffic\b", r"\bstuck\b", r"\bmove it\b", r"\bnot moving\b"]
NIGHT = [r"\bnight\b", r"\bdark\b"]

STRONG = {"fuck", "fucking", "fucker", "motherfucker", "motherfuckin", "cunt", "nigga", "nigger", "faggot"}
MILD = {"shit", "damn", "hell", "ass", "bitch", "bastard", "dick", "piss", "crap", "goddamn"}

# Слова для склейки инструкций (слой 2). up_ahead — пара «up ahead».
VOCAB = {"left", "right", "turn", "go", "keep", "stay", "straight", "now", "here", "back", "around",
         "slow", "down", "merge", "we're", "up_ahead"}


def normalize_word(w: str) -> str:
    w = w.strip().lower().replace("’", "'")
    return re.sub(r"[^a-z']", "", w)


def explicit_level(text: str) -> int:
    words = {normalize_word(w) for w in text.split()}
    if words & STRONG or any(w.startswith("fuck") or w.startswith("motherf") for w in words):
        return 2
    return 1 if words & MILD else 0


def suggest_event(text: str) -> tuple[str, float, list[str]]:
    """(событие, уверенность правила 0..1, ключи событий приложения)."""
    t = " " + text.lower().replace("’", "'") + " "
    words = [w for w in (normalize_word(x) for x in t.split()) if w]
    has = lambda pats: any(re.search(p, t) for p in pats)  # noqa: E731

    if not words:
        return "none", 0.9, []
    if has(ARRIVAL):
        return "arrival", 0.85, ["arrived"]
    if has(REROUTE):
        return "reroute", 0.8, ["reroute"]
    if has(SPEEDING):
        return "speeding", 0.8, ["speeding"]
    left, right = "left" in words, "right" in words
    if (left or right) and len(words) <= 8 and not (left and right):
        side = "left" if left else "right"
        keep = "keep" in words or "stay" in words
        return "turn", 0.75, [f"{'keep' if keep else 'turn'}_{side}"]
    if "straight" in words and len(words) <= 6:
        return "turn", 0.6, ["straight"]
    if has(CONFIRM) and len(words) <= 5:
        return "confirm", 0.65, ["confirm", "route_start"]
    if has(TRAFFIC):
        return "chatter", 0.6, ["traffic_jam"]
    if has(NIGHT):
        return "chatter", 0.5, ["night_driving"]
    if len(words) >= 3:
        return "chatter", 0.5, ["long_straight", "long_stop"]
    return "none", 0.4, []


# ------------------------------------------------------------------ аудио

@dataclass
class Audio:
    rate: int
    samples: array  # int16, моно

    @staticmethod
    def read(path: Path) -> "Audio":
        with wave.open(str(path), "rb") as w:
            if w.getsampwidth() != 2:
                raise ValueError(f"{path.name}: нужен 16-битный WAV (прогони через pack_tool)")
            data = array("h", w.readframes(w.getnframes()))
            ch = w.getnchannels()
            if ch > 1:
                data = array("h", data[::ch])
            return Audio(w.getframerate(), data)

    def cut(self, start: float, end: float, pad: float = 0.03) -> "Audio":
        a = max(0, int((start - pad) * self.rate))
        b = min(len(self.samples), int((end + pad) * self.rate))
        return Audio(self.rate, self.samples[a:b])

    def write(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with wave.open(str(path), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(self.rate)
            w.writeframes(self.samples.tobytes())

    def rms(self, a: int = 0, b: int | None = None) -> float:
        seg = self.samples[a:b]
        if not seg:
            return 0.0
        return (sum(s * s for s in seg) / len(seg)) ** 0.5 / 32768

    @property
    def duration(self) -> float:
        return len(self.samples) / self.rate


def take_score(clip: Audio, probability: float) -> float:
    """Чистота дубля: уверенность Whisper × тишина по краям × громкость × разумная длина."""
    n = len(clip.samples)
    if n == 0:
        return 0.0
    edge = max(1, int(0.02 * clip.rate))
    body = clip.rms()
    if body < 0.01:
        return 0.0
    edges = max(clip.rms(0, edge), clip.rms(n - edge, n))
    edge_q = max(0.0, 1 - edges / body)          # слово не обрезано и нет фона на стыке
    loud_q = min(1.0, body / 0.08)
    d = clip.duration
    dur_q = 1.0 if 0.12 <= d <= 0.9 else 0.5
    return round(max(0.0, min(1.0, probability)) * (0.4 + 0.6 * edge_q) * (0.5 + 0.5 * loud_q) * dur_q, 3)


# ------------------------------------------------------------------ команды

def transcribe(files: list[Path], model_name: str, language: str) -> dict[str, dict]:
    try:
        import whisper  # type: ignore
    except ImportError:
        sys.exit("Нужен openai-whisper: pip install openai-whisper (и ffmpeg в PATH)")
    model = whisper.load_model(model_name)
    out = {}
    for i, f in enumerate(files, 1):
        r = model.transcribe(str(f), language=language, word_timestamps=True, fp16=False)
        words = [{"w": w["word"].strip(), "start": round(w["start"], 3), "end": round(w["end"], 3),
                  "p": round(w.get("probability", 0.0), 3)}
                 for seg in r.get("segments", []) for w in seg.get("words", [])]
        out[f.name] = {"text": r.get("text", "").strip(), "words": words}
        print(f"[{i}/{len(files)}] {f.name}: {out[f.name]['text']}")
    return out


def cmd_suggest(voice: Path, model: str, language: str, transcripts: Path | None) -> int:
    files = sorted(p for p in voice.glob("*.wav"))
    if not files:
        print(f"Нет WAV в {voice}", file=sys.stderr)
        return 1
    data = json.loads(transcripts.read_text()) if transcripts else transcribe(files, model, language)
    old = {e["file"]: e for e in load_tags(voice)}
    tags = []
    for f in files:
        tr = data.get(f.name, {"text": "", "words": []})
        event, rule_conf, app_events = suggest_event(tr["text"])
        probs = [w["p"] for w in tr["words"]] or [0.0]
        conf = round(rule_conf * (sum(probs) / len(probs)), 3)
        entry = {"file": f.name, "text": tr["text"], "event": event, "confidence": conf,
                 "app_events": app_events, "explicit": explicit_level(tr["text"]), "words": tr["words"],
                 "reviewed": False}
        prev = old.get(f.name)
        if prev and prev.get("reviewed"):
            # Ручную разметку не затираем.
            entry.update({k: prev[k] for k in ("event", "app_events", "explicit", "reviewed") if k in prev})
        tags.append(entry)
    save_tags(voice, tags)
    counts = {e: sum(1 for t in tags if t["event"] == e) for e in EVENTS}
    print("tags.json:", ", ".join(f"{k}={v}" for k, v in counts.items() if v))
    return 0


def load_tags(voice: Path) -> list[dict]:
    p = voice / "tags.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else []


def save_tags(voice: Path, tags: list[dict]) -> None:
    (voice / "tags.json").write_text(json.dumps(tags, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def word_tokens(words: list[dict]) -> list[tuple[str, float, float, float]]:
    """Слова Whisper → (токен, start, end, p), с объединением «up ahead»."""
    out = []
    norm = [(normalize_word(w["w"]), w["start"], w["end"], w.get("p", 0.0)) for w in words]
    i = 0
    while i < len(norm):
        tok, s, e, p = norm[i]
        if tok == "up" and i + 1 < len(norm) and norm[i + 1][0] == "ahead":
            out.append(("up_ahead", s, norm[i + 1][2], min(p, norm[i + 1][3])))
            i += 2
            continue
        if tok in ("were", "we're") and i > 0 and norm[i - 1][0] == "we":
            tok = "we're"
        out.append((tok, s, e, p))
        i += 1
    return out


def cmd_build(voice: Path, character: str, max_takes: int = 6) -> int:
    tags = load_tags(voice)
    if not tags:
        print("Нет tags.json — сначала suggest", file=sys.stderr)
        return 1
    existing = voice / "voice_manifest.json"
    rejected: set[str] = set()
    if existing.exists():
        old = json.loads(existing.read_text(encoding="utf-8"))
        rejected = {t["file"] for takes in (old.get("words") or {}).values() for t in takes if t.get("rejected")}

    lines = []
    candidates: dict[str, list[dict]] = {}
    for t in tags:
        if t.get("event") in (None, "none") or not t.get("app_events"):
            pass
        else:
            lines.append({"id": Path(t["file"]).stem, "file": t["file"], "text": t.get("text", ""),
                          "events": t["app_events"], "explicit": t.get("explicit", 0), "weight": 1.0})
        # Слова режем из всех реплик, где Whisper уверен.
        try:
            audio = Audio.read(voice / t["file"])
        except (FileNotFoundError, ValueError, wave.Error) as e:
            print(f"пропуск {t['file']}: {e}", file=sys.stderr)
            continue
        for tok, s, e, p in word_tokens(t.get("words", [])):
            if tok not in VOCAB or p < 0.5:
                continue
            clip = audio.cut(s, e)
            candidates.setdefault(tok, []).append({"clip": clip, "score": take_score(clip, p), "src": t["file"]})

    words_dir = voice / "words"
    if words_dir.exists():
        for old_file in words_dir.glob("*.wav"):
            old_file.unlink()
    words: dict[str, list[dict]] = {}
    for tok, takes in sorted(candidates.items()):
        takes.sort(key=lambda x: -x["score"])
        for n, take in enumerate(takes[:max_takes], 1):
            rel = f"words/{tok.replace(chr(39), '')}_{n:02d}.wav"
            take["clip"].write(voice / rel)
            entry = {"file": rel, "score": take["score"], "from": take["src"]}
            if rel in rejected:
                entry["rejected"] = True
            words.setdefault(tok, []).append(entry)

    manifest = {"character": character, "version": 1, "lines": lines, "words": words}
    existing.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    by_event: dict[str, int] = {}
    for line in lines:
        for e in line["events"]:
            by_event[e] = by_event.get(e, 0) + 1
    print(f"voice_manifest.json: {len(lines)} реплик, слова: " +
          ", ".join(f"{w}×{len(t)}" for w, t in words.items()))
    print("по событиям: " + ", ".join(f"{k}={v}" for k, v in sorted(by_event.items())))
    missing = sorted({"left", "right", "turn", "now", "here"} - set(words))
    if missing:
        print("Нет слов для склейки (сработает фолбэк без слов): " + ", ".join(missing))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("suggest", help="расшифровать и предложить события")
    s.add_argument("--voice", type=Path, required=True)
    s.add_argument("--model", default="small", help="tiny/base/small/medium/large-v3")
    s.add_argument("--language", default="en")
    s.add_argument("--transcripts", type=Path, help="готовые расшифровки JSON вместо Whisper")
    b = sub.add_parser("build", help="собрать voice_manifest.json и нарезку слов")
    b.add_argument("--voice", type=Path, required=True)
    b.add_argument("--character", required=True)
    b.add_argument("--max-takes", type=int, default=6)
    r = sub.add_parser("review", help="страница проверки в браузере")
    r.add_argument("--voice", type=Path, required=True)
    r.add_argument("--port", type=int, default=8765)
    args = parser.parse_args(argv)

    if args.cmd == "suggest":
        return cmd_suggest(args.voice, args.model, args.language, args.transcripts)
    if args.cmd == "build":
        return cmd_build(args.voice, args.character, args.max_takes)
    from review_server import serve  # noqa: PLC0415
    return serve(args.voice, args.port)


if __name__ == "__main__":
    sys.exit(main())
