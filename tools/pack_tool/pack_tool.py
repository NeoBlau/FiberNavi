#!/usr/bin/env python3
"""Собирает пак ассетов темы из выгрузки своей копии игры.

    pack_tool.py build --in raw/gta_sa --out Assets/UserPacks/sanAndreas --map tools/pack_tool/maps/gta_sa.yml

Что делает:
  1. читает карту соответствий maps/<game>.yml (имя в игре -> ключ);
  2. конвертирует DDS/TGA/BMP/SVG -> PNG с альфой, аудио -> WAV 16 бит, моно, 44.1 кГц
     (OGG iOS не играет; AWC/OSX сначала выгрузи в WAV через OpenIV / SAAT);
  3. раскладывает файлы по ключам: hud/, ui/blip/, map/tiles/, sfx/, voice/<char>/, font/;
  4. пишет manifest.json: секции, которые читает приложение (blips/hud/map/sounds/fonts/voice),
     и список assets с происхождением каждого файла;
  5. печатает отчёт: каких ключей нет, дубликаты, картинки без альфы, неподдерживаемые форматы.

Нужны: Python 3.10+, Pillow, PyYAML, ffmpeg в PATH. Для SVG — cairosvg.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("Нужен PyYAML: pip install pyyaml")

from PIL import Image

IMAGE_EXT = {".png", ".dds", ".tga", ".bmp", ".jpg", ".jpeg", ".webp", ".svg"}
AUDIO_EXT = {".wav", ".ogg", ".mp3", ".flac", ".m4a", ".aac", ".aif", ".aiff"}
RAW_AUDIO_EXT = {".awc", ".osx", ".raw", ".bnk"}
FONT_EXT = {".ttf", ".otf"}

# Ключ брифа -> ключ приложения. Порядок = приоритет: берётся первый найденный.
APP_KEYS: dict[str, list[str]] = {
    "blip.food": ["ui.blip.food.burger", "ui.blip.food.chicken", "ui.blip.food.restaurant",
                  "ui.blip.food.pizza", "ui.blip.saloon", "ui.blip.food.grub"],
    "blip.atm": ["ui.blip.bank"],
    "blip.car_service": ["ui.blip.repair", "ui.blip.garage"],
    "blip.hospital": ["ui.blip.hospital", "ui.blip.doctor"],
    "blip.pharmacy": ["ui.blip.pharmacy"],
    "blip.police": ["ui.blip.police", "ui.blip.sheriff"],
    "blip.shop": ["ui.blip.shop", "ui.blip.shop.store", "ui.blip.shop.market", "ui.blip.clothes"],
    "blip.parking": ["ui.blip.parking", "ui.blip.stable"],
    "blip.metro": ["ui.blip.transit.metro"],
    "blip.rail": ["ui.blip.transit.train"],
    "blip.gas_station": ["ui.blip.fuel"],
    "blip.waypoint": ["ui.waypoint"],
    "hud.minimap_frame": ["hud.minimap_frame"],
    "hud.player_arrow": ["hud.player_arrow"],
    "hud.compass": ["hud.compass_rose", "hud.north"],
    "map.tex.water": ["map.tile.water"],
    "map.tex.grass": ["map.tile.park"],
    "map.tex.road": ["map.tile.road"],
    "map.tex.paper": ["map.tile.paper", "map.tile.urban"],
    "map.tex.hatch": ["map.tile.hatch"],
    "ui.mission_start": ["sfx.ui.confirm", "sfx.mission_complete"],
    "ui.waypoint": ["sfx.waypoint.set"],
    "ui.arrived": ["sfx.arrival", "sfx.mission_complete"],
    "ui.reroute": ["sfx.route.recalc"],
    "ui.map_open": ["sfx.map.open"],
    "ui.map_close": ["sfx.ui.select"],
    "font.title": ["font.heading"],
    "font.digits": ["font.digits", "font.heading"],
    "font.body": ["font.body"],
}

SECTION_BY_PREFIX = {"blip.": "blips", "hud.": "hud", "map.": "map", "ui.": "sounds", "font.": "fonts"}

THEME_BY_GAME = {"gta_sa": "sanAndreas", "gta_v": "gta5", "rdr2": "rdr2", "gta_vi": "gta6concept"}


@dataclass
class Report:
    missing: list[str] = field(default_factory=list)
    absent: list[str] = field(default_factory=list)
    duplicates: dict[str, list[str]] = field(default_factory=dict)
    no_alpha: list[str] = field(default_factory=list)
    unsupported: list[str] = field(default_factory=list)
    written: int = 0

    def print(self, out=None) -> None:
        out = out or sys.stdout
        print(f"\nЗаписано файлов: {self.written}", file=out)
        if self.missing:
            print(f"Нет в выгрузке ({len(self.missing)}): " + ", ".join(self.missing), file=out)
        if self.absent:
            print("Нет в самой игре (будет заглушка): " + ", ".join(self.absent), file=out)
        for key, files in self.duplicates.items():
            print(f"Несколько файлов на {key}, взят первый: " + ", ".join(files), file=out)
        if self.no_alpha:
            print("Картинки без прозрачности: " + ", ".join(self.no_alpha), file=out)
        if self.unsupported:
            print("Сначала выгрузи в WAV (OpenIV / SAAT): " + ", ".join(self.unsupported), file=out)


# ------------------------------------------------------------------ конвертация

def convert_image(src: Path, dst: Path, max_size: int | None = None) -> tuple[tuple[int, int], bool]:
    """В PNG RGBA. Возвращает (размер, есть ли настоящая прозрачность)."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.suffix.lower() == ".svg":
        try:
            import cairosvg  # type: ignore
        except ImportError as exc:
            raise RuntimeError("для SVG нужен cairosvg: pip install cairosvg") from exc
        cairosvg.svg2png(url=str(src), write_to=str(dst), output_width=max_size or 256)
        img = Image.open(dst).convert("RGBA")
    else:
        img = Image.open(src)
        img.load()
        img = img.convert("RGBA")
    if max_size and max(img.size) > max_size:
        img.thumbnail((max_size, max_size), Image.LANCZOS)
    img.save(dst, "PNG", optimize=True)
    alpha_min, _ = img.getchannel("A").getextrema()
    return img.size, alpha_min < 255


def make_seamless(path: Path, blend: float = 0.25) -> None:
    """Делает текстуру тайлящейся: сдвиг на половину и мягкое смешивание швов."""
    img = Image.open(path).convert("RGBA")
    w, h = img.size
    shifted = Image.new("RGBA", (w, h))
    shifted.paste(img.crop((w // 2, h // 2, w, h)), (0, 0))
    shifted.paste(img.crop((0, h // 2, w // 2, h)), (w - w // 2, 0))
    shifted.paste(img.crop((w // 2, 0, w, h // 2)), (0, h - h // 2))
    shifted.paste(img.crop((0, 0, w // 2, h // 2)), (w - w // 2, h - h // 2))
    # У сдвинутой копии края непрерывны (это середина оригинала), шов — в центре.
    # Маска: у краёв берём сдвинутую, в центре — оригинал, между ними плавный переход.
    mask = Image.new("L", (w, h))
    px = mask.load()
    bw, bh = max(1, int(w * blend)), max(1, int(h * blend))
    for y in range(h):
        for x in range(w):
            dx = min(x, w - 1 - x) / bw
            dy = min(y, h - 1 - y) / bh
            px[x, y] = int(255 * (1 - max(0.0, min(1.0, min(dx, dy)))))
    Image.composite(shifted, img, mask).save(path, "PNG")


def convert_audio(src: Path, dst: Path) -> None:
    """WAV 16 бит PCM, моно, 44.1 кГц — iOS играет без вопросов."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-ac", "1", "-ar", "44100",
           "-c:a", "pcm_s16le", str(dst)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg: {result.stderr.strip()}")


# ------------------------------------------------------------------ поиск файлов

def find_matches(raw: Path, pattern: str | list[str]) -> list[Path]:
    patterns = [pattern] if isinstance(pattern, str) else pattern
    files = [p for p in raw.rglob("*") if p.is_file()]
    out: list[Path] = []
    for pat in patterns:
        pat_l = pat.lower()
        for f in sorted(files):
            if f in out:
                continue
            rel = f.relative_to(raw).as_posix().lower()
            if fnmatch.fnmatch(f.stem.lower(), pat_l) or fnmatch.fnmatch(f.name.lower(), pat_l) \
                    or fnmatch.fnmatch(rel, pat_l):
                out.append(f)
    return out


def target_path(key: str, ext: str, index: int | None = None) -> str:
    """ui.blip.food.burger -> ui/blip/food_burger.png; map.tile.water + 3 -> map/tiles/water_03.png."""
    parts = key.split(".")
    if parts[0] == "ui" and len(parts) > 1 and parts[1] == "blip":
        return f"ui/blip/{'_'.join(parts[2:])}{ext}"
    if key == "ui.waypoint":
        return f"ui/waypoint{ext}"
    if parts[:2] == ["map", "tile"]:
        return f"map/tiles/{parts[2]}_{(index or 1):02d}{ext}"
    if parts[0] == "hud":
        return f"hud/{parts[1]}{ext}"
    if parts[0] == "sfx":
        return f"sfx/{'_'.join(parts[1:])}{ext}"
    if parts[0] == "font":
        return f"font/{parts[1]}{ext}"
    suffix = f"_{index:02d}" if index else ""
    return f"{'/'.join(parts)}{suffix}{ext}"


# ------------------------------------------------------------------ сборка

def build(raw: Path, out: Path, mapping: dict, report: Report, seamless: bool = True) -> dict:
    game = mapping.get("game", out.name)
    assets_out: list[dict] = []
    by_key: dict[str, str] = {}
    voice_chars: dict[str, str] = {}

    for key, spec in (mapping.get("assets") or {}).items():
        spec = spec or {}
        if spec.get("absent"):
            report.absent.append(key)
            continue
        source = spec.get("source", "own")
        origin = spec.get("origin", "")
        if key.startswith("voice."):
            char = key.split(".", 1)[1]
            files = [f for f in find_matches(raw, spec.get("match", f"voice/{char}/*"))
                     if f.suffix.lower() in AUDIO_EXT | RAW_AUDIO_EXT]
            if not files:
                report.missing.append(key)
                continue
            n = 0
            for f in files:
                if f.suffix.lower() in RAW_AUDIO_EXT:
                    report.unsupported.append(f.name)
                    continue
                n += 1
                rel = f"voice/{char}/{char}_{n:04d}.wav"
                convert_audio(f, out / rel)
                report.written += 1
                assets_out.append({"key": f"voice.{char}.{n:04d}", "file": rel, "source": source,
                                   "origin": f"{origin}:{f.name}" if origin else f.name, "format": "wav"})
            voice_chars[char] = f"voice/{char}/voice_manifest.json"
            continue

        files = find_matches(raw, spec.get("match", key.split(".")[-1]))
        if not files:
            report.missing.append(key)
            continue
        multi = key.startswith("map.tile.") or spec.get("multi", False)
        if not multi and len(files) > 1:
            report.duplicates[key] = [f.name for f in files]
            files = files[:1]
        for i, f in enumerate(files, start=1):
            ext = f.suffix.lower()
            entry: dict = {"key": f"{key}.{i:02d}" if multi else key, "source": source,
                           "origin": f"{origin}:{f.stem}" if origin else f.name}
            if ext in IMAGE_EXT:
                rel = target_path(key, ".png", i if multi else None)
                size, has_alpha = convert_image(f, out / rel, spec.get("max_size"))
                if key.startswith("map.tile.") and seamless:
                    make_seamless(out / rel)
                if not has_alpha and not key.startswith("map."):
                    report.no_alpha.append(f.name)
                entry.update(file=rel, format="png", size=list(size))
            elif ext in AUDIO_EXT:
                rel = target_path(key, ".wav")
                convert_audio(f, out / rel)
                entry.update(file=rel, format="wav")
            elif ext in RAW_AUDIO_EXT:
                report.unsupported.append(f.name)
                continue
            elif ext in FONT_EXT:
                rel = target_path(key, ext)
                (out / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(f, out / rel)
                entry.update(file=rel, format=ext[1:])
            else:
                report.unsupported.append(f.name)
                continue
            report.written += 1
            assets_out.append(entry)
            by_key.setdefault(key, entry["file"])

    manifest: dict = {
        "pack": game,
        "game": mapping.get("title", game),
        "version": str(mapping.get("version", "1.0")),
        "theme": mapping.get("theme", THEME_BY_GAME.get(game, game)),
        "assets": assets_out,
    }
    # Секции, которые читает приложение (UserPack.swift).
    for app_key, candidates in APP_KEYS.items():
        file = next((by_key[c] for c in candidates if c in by_key), None)
        if not file:
            continue
        section = next(s for prefix, s in SECTION_BY_PREFIX.items() if app_key.startswith(prefix))
        manifest.setdefault(section, {})[app_key] = file
    if voice_chars:
        manifest["voice"] = {"characters": voice_chars}
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="собрать пак")
    b.add_argument("--in", dest="raw", required=True, type=Path, help="папка с выгрузкой из игры")
    b.add_argument("--out", required=True, type=Path, help="папка пака, напр. Assets/UserPacks/gta5")
    b.add_argument("--map", required=True, type=Path, help="tools/pack_tool/maps/<game>.yml")
    b.add_argument("--game", help="переопределить game из карты")
    b.add_argument("--no-seamless", action="store_true", help="не делать тайлы карты бесшовными")
    b.add_argument("--clean", action="store_true", help="очистить --out перед сборкой")
    args = parser.parse_args(argv)

    mapping = yaml.safe_load(args.map.read_text(encoding="utf-8")) or {}
    if args.game:
        mapping["game"] = args.game
    if not args.raw.is_dir():
        print(f"Нет папки {args.raw}", file=sys.stderr)
        return 1
    if args.clean and args.out.exists():
        # Сохраняем разметку голоса, сделанную вручную.
        keep = {p: p.read_bytes() for p in args.out.rglob("voice_manifest.json")}
        shutil.rmtree(args.out)
        for p, data in keep.items():
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)
    args.out.mkdir(parents=True, exist_ok=True)

    report = Report()
    manifest = build(args.raw, args.out, mapping, report, seamless=not args.no_seamless)
    (args.out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"manifest.json -> {args.out / 'manifest.json'}")
    report.print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
