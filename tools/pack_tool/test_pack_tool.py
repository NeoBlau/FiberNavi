"""python3 -m unittest tools/pack_tool/test_pack_tool.py"""
import io
import json
import math
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import wave
from contextlib import redirect_stdout
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import pack_tool  # noqa: E402

MAPS = Path(__file__).parent / "maps"


def tone(path: Path, seconds=0.3, rate=22050):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        frames = b"".join(struct.pack("<hh", int(8000 * math.sin(i / 10)), 0) for i in range(int(seconds * rate)))
        w.writeframes(frames)


def icon(path: Path, alpha=True, fmt=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0) if alpha else (20, 20, 20, 255))
    for x in range(8, 24):
        for y in range(8, 24):
            img.putpixel((x, y), (255, 200, 0, 255))
    img.save(path, fmt) if fmt else img.save(path)


class PackToolTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.raw = self.tmp / "raw"
        self.out = self.tmp / "out"

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_build(self, map_name):
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = pack_tool.main(["build", "--in", str(self.raw), "--out", str(self.out),
                                   "--map", str(MAPS / map_name)])
        self.assertEqual(code, 0)
        return json.loads((self.out / "manifest.json").read_text()), buf.getvalue()

    def test_gta_sa_pack(self):
        icon(self.raw / "hud" / "radar_burgerShot.dds", fmt="DDS")
        icon(self.raw / "hud" / "radar_hostpital.png")
        icon(self.raw / "hud" / "radar_police.png", alpha=False)
        icon(self.raw / "hud" / "arrow.png")
        Image.new("RGB", (64, 64), (60, 90, 140)).save(self.raw / "hud" / "radar_north.png")
        (self.raw / "tiles").mkdir(parents=True)
        for i in (1, 2):
            Image.new("RGB", (128, 128), (60, 90, 140 + i)).save(self.raw / "tiles" / f"water_{i}.png")
        tone(self.raw / "sfx" / "blip_detected.wav")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(self.raw / "sfx" / "blip_detected.wav"),
                        str(self.raw / "sfx" / "confirm.ogg")], check=True)
        (self.raw / "sfx" / "mission_passed.osx").write_bytes(b"\0" * 64)
        tone(self.raw / "voice" / "cj" / "SPC_PA_0001.wav")
        tone(self.raw / "voice" / "cj" / "SPC_PA_0002.wav")
        (self.raw / "font").mkdir()
        (self.raw / "font" / "pricedown bl.ttf").write_bytes(b"fake-ttf")

        manifest, log = self.run_build("gta_sa.yml")

        # Секции приложения
        self.assertEqual(manifest["theme"], "sanAndreas")
        self.assertEqual(manifest["blips"]["blip.food"], "ui/blip/food_burger.png")
        self.assertEqual(manifest["blips"]["blip.hospital"], "ui/blip/hospital.png")
        self.assertEqual(manifest["hud"]["hud.player_arrow"], "hud/player_arrow.png")
        self.assertEqual(manifest["hud"]["hud.compass"], "hud/north.png")
        self.assertEqual(manifest["map"]["map.tex.water"], "map/tiles/water_01.png")
        self.assertEqual(manifest["sounds"]["ui.waypoint"], "sfx/waypoint_set.wav")
        self.assertEqual(manifest["sounds"]["ui.mission_start"], "sfx/ui_confirm.wav")
        self.assertEqual(manifest["fonts"]["font.title"], "font/heading.ttf")
        self.assertEqual(manifest["voice"]["characters"]["cj"], "voice/cj/voice_manifest.json")

        # Файлы и форматы
        with wave.open(str(self.out / "sfx/ui_confirm.wav")) as w:
            self.assertEqual((w.getnchannels(), w.getframerate(), w.getsampwidth()), (1, 44100, 2))
        self.assertTrue((self.out / "map/tiles/water_02.png").exists())
        self.assertTrue((self.out / "voice/cj/cj_0002.wav").exists())
        burger = Image.open(self.out / "ui/blip/food_burger.png")
        self.assertEqual(burger.mode, "RGBA")

        # Происхождение
        by_key = {a["key"]: a for a in manifest["assets"]}
        self.assertEqual(by_key["ui.blip.hospital"]["source"], "own")
        self.assertIn("radar_hostpital", by_key["ui.blip.hospital"]["origin"])
        self.assertEqual(by_key["font.heading"]["source"], "licensed")
        self.assertEqual(by_key["ui.blip.food.burger"]["size"], [32, 32])

        # Отчёт
        self.assertIn("radar_police.png", log)       # без альфы
        self.assertIn("mission_passed.osx", log)     # надо выгрузить в WAV
        self.assertIn("ui.blip.fuel", log)           # нет в игре
        self.assertIn("ui.blip.bank", log)           # нет в выгрузке

    def test_seamless_keeps_size_and_edges_match(self):
        path = self.tmp / "t.png"
        img = Image.new("RGB", (64, 64))
        for x in range(64):
            for y in range(64):
                img.putpixel((x, y), (x * 4, y * 4, 0))
        img.save(path)
        pack_tool.make_seamless(path)
        out = Image.open(path).convert("RGB")
        self.assertEqual(out.size, (64, 64))
        # Левый и правый край почти совпадают — тайл стыкуется.
        diff = sum(abs(out.getpixel((0, y))[0] - out.getpixel((63, y))[0]) for y in range(64)) / 64
        self.assertLess(diff, 12)

    def test_duplicates_reported(self):
        icon(self.raw / "a" / "radar_hospital.png")
        icon(self.raw / "b" / "radar_hospital.png")
        manifest, log = self.run_build("gta_v.yml")
        self.assertIn("Несколько файлов на ui.blip.hospital", log)
        self.assertEqual(manifest["blips"]["blip.hospital"], "ui/blip/hospital.png")
        self.assertEqual(manifest["blips"]["blip.pharmacy"], "ui/blip/pharmacy.png")


if __name__ == "__main__":
    unittest.main()
