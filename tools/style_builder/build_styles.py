#!/usr/bin/env python3
"""Собирает MapLibre-стили тем из палитр.

Вход:  tools/style_builder/palettes/<theme>.json
Выход: App/Themes/<theme>/<theme>.day.json и <theme>.night.json
(имя с темой: файлы копируются в корень бандла и не должны совпадать)

Схема тайлов OpenMapTiles (OpenFreeMap или свой Planetiler-PMTiles из Backend/).
Иконки POI (`blip.*`) и паттерны (`pattern.*`) регистрирует приложение в рантайме:
из пользовательского пака, а если файла нет, то сгенерированную заглушку.

Запуск: python3 tools/style_builder/build_styles.py [--check]
"""
from __future__ import annotations

import argparse
import colorsys
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PALETTES = Path(__file__).resolve().parent / "palettes"
THEMES_DIR = ROOT / "App" / "Themes"

TILES_URL = "https://tiles.openfreemap.org/planet"
GLYPHS_URL = "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf"
FONT_REGULAR = ["Noto Sans Regular"]
FONT_BOLD = ["Noto Sans Bold"]
FONT_ITALIC = ["Noto Sans Italic"]

# Категории POI -> ключ метки в паке. Порядок важен только для читаемости.
BLIP_CLASSES: dict[str, list[str]] = {
    "blip.gas_station": ["fuel"],
    "blip.food": ["fast_food", "restaurant", "cafe", "bar", "beer", "ice_cream"],
    "blip.atm": ["bank"],
    "blip.parking": ["parking"],
    "blip.hospital": ["hospital"],
    "blip.pharmacy": ["pharmacy"],
    "blip.shop": ["shop", "grocery", "clothing_store"],
    "blip.police": ["police"],
    "blip.car_service": ["car"],
}

NAME = ["coalesce", ["get", "name:ru"], ["get", "name"]]


# ---------------------------------------------------------------- цвета

def _hex_to_rgb(value: str) -> tuple[float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) / 255 for i in (0, 2, 4))  # type: ignore[return-value]


def _rgb_to_hex(rgb: tuple[float, float, float]) -> str:
    return "#" + "".join(f"{round(max(0.0, min(1.0, c)) * 255):02x}" for c in rgb)


def night_color(value: str, lightness: float, saturation: float, tint: str | None) -> str:
    """Ночная версия цвета: темнее, слабее насыщенность, лёгкий подмес оттенка."""
    h, l, s = colorsys.rgb_to_hls(*_hex_to_rgb(value))
    r, g, b = colorsys.hls_to_rgb(h, l * lightness, s * saturation)
    if tint:
        tr, tg, tb = _hex_to_rgb(tint)
        r, g, b = r * 0.85 + tr * 0.15, g * 0.85 + tg * 0.15, b * 0.85 + tb * 0.15
    return _rgb_to_hex((r, g, b))


def make_night(palette: dict) -> dict:
    rules = palette.get("night", {})
    k_l = rules.get("lightness", 0.45)
    k_s = rules.get("saturation", 0.8)
    tint = rules.get("tint")
    out = {}
    for key, value in palette["colors"].items():
        out[key] = night_color(value, k_l, k_s, tint) if isinstance(value, str) and value.startswith("#") else value
    out.update(rules.get("overrides", {}))
    return out


# ---------------------------------------------------------------- помощники выражений

def zoom_width(*stops: tuple[float, float], base: float = 1.5) -> list:
    expr: list = ["interpolate", ["exponential", base], ["zoom"]]
    for z, w in stops:
        expr += [z, w]
    return expr


def scaled(width_expr: list, k: float) -> list:
    out = width_expr[:3]
    rest = width_expr[3:]
    for i in range(0, len(rest), 2):
        out += [rest[i], round(rest[i + 1] * k, 2)]
    return out


def road_filter(classes: list[str], brunnel: str | None = None, ramp: bool | None = None) -> list:
    f: list = ["all", ["match", ["get", "class"], classes, True, False]]
    if brunnel == "none":
        f.append(["match", ["get", "brunnel"], ["bridge", "tunnel"], False, True])
    elif brunnel:
        f.append(["==", ["get", "brunnel"], brunnel])
    if ramp is True:
        f.append(["==", ["get", "ramp"], 1])
    elif ramp is False:
        f.append(["!=", ["get", "ramp"], 1])
    return f


# Ширины дорог. Москва: МКАД/ЦКАД — motorway, ТТК и вылетные — trunk, Садовое — primary/trunk.
W_MOTORWAY = zoom_width((5, 0.6), (9, 1.6), (12, 3.2), (15, 10), (18, 34))
W_TRUNK = zoom_width((5, 0.4), (9, 1.2), (12, 2.6), (15, 8), (18, 28))
W_PRIMARY = zoom_width((7, 0.3), (10, 1.0), (12, 2.0), (15, 6.5), (18, 24))
W_SECONDARY = zoom_width((9, 0.3), (12, 1.4), (15, 5), (18, 20))
W_MINOR = zoom_width((12, 0.4), (14, 1.4), (16, 4), (18, 14))
W_SERVICE = zoom_width((14, 0.3), (16, 1.5), (18, 6))
W_PATH = zoom_width((14, 0.4), (17, 1.4), (19, 3))

ROAD_TIERS = [
    # id, классы, ширина, ключ цвета, мин. зум
    ("service", ["service", "track"], W_SERVICE, "road_service", 14),
    ("minor", ["minor"], W_MINOR, "road_minor", 12),
    ("secondary", ["secondary", "tertiary"], W_SECONDARY, "road_secondary", 9),
    ("primary", ["primary"], W_PRIMARY, "road_primary", 7),
    ("trunk", ["trunk"], W_TRUNK, "road_trunk", 5),
    ("motorway", ["motorway"], W_MOTORWAY, "road_motorway", 5),
]


# ---------------------------------------------------------------- слои

def build_layers(c: dict, p: dict) -> list[dict]:
    opts = p.get("options", {})
    L: list[dict] = []

    def add(layer: dict) -> None:
        L.append(layer)

    add({"id": "background", "type": "background", "paint": {"background-color": c["land"]}})
    if opts.get("land_pattern"):
        add({"id": "background-texture", "type": "background",
             "paint": {"background-pattern": opts["land_pattern"], "background-opacity": opts.get("land_pattern_opacity", 0.5)}})

    # --- землепользование
    landuse = [
        ("residential", ["residential", "suburb", "neighbourhood", "quarter"], "residential", 0.9),
        ("commercial", ["commercial", "retail"], "commercial", 0.8),
        ("industrial", ["industrial", "railway", "garages"], "industrial", 0.8),
        ("cemetery", ["cemetery"], "park", 0.6),
        ("hospital", ["hospital"], "hospital_area", 0.8),
        ("school", ["school", "university", "college", "kindergarten"], "school_area", 0.7),
        ("pitch", ["pitch", "stadium", "playground"], "park", 0.8),
    ]
    for lid, classes, color, opacity in landuse:
        add({"id": f"landuse-{lid}", "type": "fill", "source": "openmaptiles", "source-layer": "landuse",
             "filter": ["match", ["get", "class"], classes, True, False],
             "paint": {"fill-color": c[color], "fill-opacity": opacity}})

    add({"id": "landcover-wood", "type": "fill", "source": "openmaptiles", "source-layer": "landcover",
         "filter": ["==", ["get", "class"], "wood"],
         "paint": {"fill-color": c["wood"], "fill-opacity": ["interpolate", ["linear"], ["zoom"], 6, 0.6, 12, 0.9]}})
    add({"id": "landcover-grass", "type": "fill", "source": "openmaptiles", "source-layer": "landcover",
         "filter": ["match", ["get", "class"], ["grass", "farmland"], True, False],
         "paint": {"fill-color": c["grass"], "fill-opacity": 0.75}})
    add({"id": "landcover-wetland", "type": "fill", "source": "openmaptiles", "source-layer": "landcover",
         "filter": ["==", ["get", "class"], "wetland"],
         "paint": {"fill-color": c["grass"], "fill-opacity": 0.5}})
    add({"id": "landcover-sand", "type": "fill", "source": "openmaptiles", "source-layer": "landcover",
         "filter": ["==", ["get", "class"], "sand"],
         "paint": {"fill-color": c["sand"], "fill-opacity": 0.8}})
    # Парки Москвы (Лосиный остров, Битца, Сокольники и т.д.) — отдельный слой park.
    add({"id": "park", "type": "fill", "source": "openmaptiles", "source-layer": "park",
         "filter": ["match", ["geometry-type"], ["MultiPolygon", "Polygon"], True, False],
         "paint": {"fill-color": c["park"], "fill-opacity": 0.85}})
    if opts.get("park_pattern"):
        add({"id": "park-texture", "type": "fill", "source": "openmaptiles", "source-layer": "park",
             "filter": ["match", ["geometry-type"], ["MultiPolygon", "Polygon"], True, False],
             "paint": {"fill-pattern": opts["park_pattern"], "fill-opacity": 0.35}})

    # --- вода: Москва-река, Яуза, водохранилища
    add({"id": "water", "type": "fill", "source": "openmaptiles", "source-layer": "water",
         "filter": ["!=", ["get", "brunnel"], "tunnel"],
         "paint": {"fill-color": c["water"]}})
    if opts.get("water_pattern"):
        add({"id": "water-texture", "type": "fill", "source": "openmaptiles", "source-layer": "water",
             "filter": ["!=", ["get", "brunnel"], "tunnel"],
             "paint": {"fill-pattern": opts["water_pattern"], "fill-opacity": opts.get("water_pattern_opacity", 0.4)}})
    if opts.get("water_outline"):
        add({"id": "water-outline", "type": "line", "source": "openmaptiles", "source-layer": "water",
             "filter": ["!=", ["get", "brunnel"], "tunnel"],
             "paint": {"line-color": c["water_outline"], "line-width": zoom_width((8, 0.4), (14, 1.2), (18, 2.5))}})
    add({"id": "waterway-river", "type": "line", "source": "openmaptiles", "source-layer": "waterway",
         "filter": ["all", ["==", ["get", "class"], "river"], ["!=", ["get", "brunnel"], "tunnel"]],
         "layout": {"line-cap": "round"},
         "paint": {"line-color": c["water"], "line-width": zoom_width((8, 0.8), (12, 2), (16, 6))}})
    add({"id": "waterway-other", "type": "line", "source": "openmaptiles", "source-layer": "waterway",
         "minzoom": 12,
         "filter": ["all", ["!=", ["get", "class"], "river"], ["!=", ["get", "brunnel"], "tunnel"]],
         "paint": {"line-color": c["water"], "line-width": zoom_width((12, 0.5), (16, 2))}})

    # --- аэропорты: Шереметьево, Домодедово, Внуково, Жуковский
    add({"id": "aeroway-area", "type": "fill", "source": "openmaptiles", "source-layer": "aeroway", "minzoom": 10,
         "filter": ["match", ["geometry-type"], ["MultiPolygon", "Polygon"], True, False],
         "paint": {"fill-color": c["industrial"], "fill-opacity": 0.7}})
    add({"id": "aeroway-runway", "type": "line", "source": "openmaptiles", "source-layer": "aeroway", "minzoom": 10,
         "filter": ["all", ["match", ["geometry-type"], ["LineString", "MultiLineString"], True, False],
                    ["==", ["get", "class"], "runway"]],
         "paint": {"line-color": c["road_minor"], "line-width": zoom_width((10, 1), (14, 12), (17, 50))}})

    # --- здания
    if opts.get("buildings_3d"):
        add({"id": "building-3d", "type": "fill-extrusion", "source": "openmaptiles", "source-layer": "building",
             "minzoom": 14, "filter": ["!", ["has", "hide_3d"]],
             "paint": {
                 "fill-extrusion-color": ["interpolate", ["linear"], ["coalesce", ["get", "render_height"], 0],
                                          0, c["building"], 60, c["building_top"], 200, c["building_glow"]],
                 "fill-extrusion-height": ["interpolate", ["linear"], ["zoom"], 14, 0, 15, ["coalesce", ["get", "render_height"], 10]],
                 "fill-extrusion-base": ["coalesce", ["get", "render_min_height"], 0],
                 "fill-extrusion-opacity": 0.92,
                 "fill-extrusion-vertical-gradient": True,
             }})
    else:
        add({"id": "building", "type": "fill", "source": "openmaptiles", "source-layer": "building", "minzoom": 13,
             "paint": {"fill-color": c["building"],
                       "fill-outline-color": c["building_outline"],
                       "fill-opacity": ["interpolate", ["linear"], ["zoom"], 13, 0, 14.5, 1]}})

    # --- граница Москвы и области (admin_level 4)
    add({"id": "boundary-region", "type": "line", "source": "openmaptiles", "source-layer": "boundary",
         "filter": ["all", ["==", ["get", "admin_level"], 4], ["!=", ["get", "maritime"], 1]],
         "paint": {"line-color": c["boundary"], "line-dasharray": [3, 2],
                   "line-width": zoom_width((5, 0.8), (10, 1.6), (14, 2.5))}})

    # --- дороги: туннели, обычные, мосты. Сначала все обводки, потом заливки.
    dash_tunnel = [0.5, 0.25]
    for phase, brunnel in (("tunnel", "tunnel"), ("road", "none"), ("bridge", "bridge")):
        for tid, classes, width, color, minz in ROAD_TIERS:
            if tid in ("service",) and phase == "tunnel":
                continue
            casing = {"id": f"{phase}-{tid}-casing", "type": "line", "source": "openmaptiles",
                      "source-layer": "transportation", "minzoom": max(minz, 10) if tid not in ("motorway", "trunk") else 9,
                      "filter": road_filter(classes, brunnel),
                      "layout": {"line-join": "round", "line-cap": "butt" if phase == "tunnel" else "round"},
                      "paint": {"line-color": c["road_casing"] if tid not in ("motorway", "trunk") else c["road_major_casing"],
                                "line-width": scaled(width, 1.0 + opts.get("casing_ratio", 0.35)),
                                "line-gap-width": 0}}
            if phase == "tunnel":
                casing["paint"]["line-dasharray"] = dash_tunnel
            if opts.get("no_casing") and phase != "bridge":
                pass
            else:
                add(casing)
        for tid, classes, width, color, minz in ROAD_TIERS:
            if tid in ("service",) and phase == "tunnel":
                continue
            fill = {"id": f"{phase}-{tid}", "type": "line", "source": "openmaptiles",
                    "source-layer": "transportation", "minzoom": minz,
                    "filter": road_filter(classes, brunnel),
                    "layout": {"line-join": "round", "line-cap": "round"},
                    "paint": {"line-color": c[color], "line-width": width}}
            if phase == "tunnel":
                fill["paint"]["line-opacity"] = 0.55
            add(fill)
        if phase == "road":
            add({"id": "road-path", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
                 "minzoom": 14, "filter": road_filter(["path", "pedestrian"], "none"),
                 "paint": {"line-color": c["path"], "line-width": W_PATH, "line-dasharray": [2, 1.5]}})
            # Железные дороги, МЦК, МЦД
            add({"id": "rail", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
                 "minzoom": 8, "filter": ["all", ["==", ["get", "class"], "rail"], ["!=", ["get", "brunnel"], "tunnel"]],
                 "paint": {"line-color": c["rail"], "line-width": zoom_width((8, 0.5), (13, 1.2), (17, 3))}})
            add({"id": "rail-hatch", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
                 "minzoom": 13, "filter": ["all", ["==", ["get", "class"], "rail"], ["!=", ["get", "brunnel"], "tunnel"]],
                 "paint": {"line-color": c["rail"], "line-dasharray": [0.2, 6],
                           "line-width": zoom_width((13, 3), (17, 8))}})
            # Метро над землёй и в туннеле (на крупных зумах, чтобы не мешать)
            add({"id": "subway", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
                 "minzoom": 12, "filter": ["all", ["==", ["get", "class"], "transit"],
                                           ["==", ["get", "subclass"], "subway"]],
                 "paint": {"line-color": c["subway"], "line-opacity": 0.45, "line-dasharray": [1, 1],
                           "line-width": zoom_width((12, 0.8), (16, 2.5))}})

    # --- подписи
    halo = {"text-halo-color": c["label_halo"], "text-halo-width": opts.get("halo_width", 1.6), "text-halo-blur": 0.5}

    add({"id": "water-name-line", "type": "symbol", "source": "openmaptiles", "source-layer": "waterway",
         "minzoom": 12, "filter": ["match", ["geometry-type"], ["LineString", "MultiLineString"], True, False],
         "layout": {"text-field": NAME, "text-font": FONT_ITALIC, "symbol-placement": "line",
                    "text-size": 12, "text-letter-spacing": 0.1},
         "paint": {"text-color": c["water_label"], **halo}})
    add({"id": "water-name-point", "type": "symbol", "source": "openmaptiles", "source-layer": "water_name",
         "filter": ["match", ["geometry-type"], ["MultiPoint", "Point"], True, False],
         "layout": {"text-field": NAME, "text-font": FONT_ITALIC, "text-size": 12, "text-max-width": 6},
         "paint": {"text-color": c["water_label"], **halo}})

    add({"id": "road-name-minor", "type": "symbol", "source": "openmaptiles", "source-layer": "transportation_name",
         "minzoom": 15, "filter": ["match", ["get", "class"], ["minor", "service"], True, False],
         "layout": {"text-field": NAME, "text-font": FONT_REGULAR, "symbol-placement": "line",
                    "text-size": ["interpolate", ["linear"], ["zoom"], 15, 10, 18, 13]},
         "paint": {"text-color": c["road_label"], **halo}})
    add({"id": "road-name-major", "type": "symbol", "source": "openmaptiles", "source-layer": "transportation_name",
         "minzoom": 12, "filter": ["match", ["get", "class"], ["primary", "secondary", "tertiary", "trunk", "motorway"], True, False],
         "layout": {"text-field": NAME, "text-font": FONT_REGULAR, "symbol-placement": "line",
                    "text-size": ["interpolate", ["linear"], ["zoom"], 12, 10, 16, 13, 18, 15]},
         "paint": {"text-color": c["road_label"], **halo}})
    # Номера трасс: М-11, М-4, А-107 (ЦКАД М-12)…
    add({"id": "road-shield", "type": "symbol", "source": "openmaptiles", "source-layer": "transportation_name",
         "minzoom": 8, "filter": ["all", ["has", "ref"], ["<=", ["get", "ref_length"], 6],
                                  ["match", ["get", "class"], ["motorway", "trunk", "primary"], True, False]],
         "layout": {"text-field": ["get", "ref"], "text-font": FONT_BOLD, "text-size": 10,
                    "symbol-placement": "line", "symbol-spacing": 400, "text-rotation-alignment": "viewport"},
         "paint": {"text-color": c["shield_text"], "text-halo-color": c["shield_bg"], "text-halo-width": 3}})

    add({"id": "airport-label", "type": "symbol", "source": "openmaptiles", "source-layer": "aerodrome_label",
         "minzoom": 9, "filter": ["has", "iata"],
         "layout": {"text-field": ["concat", "✈ ", NAME], "text-font": FONT_BOLD, "text-size": 12},
         "paint": {"text-color": c["label"], **halo}})

    # Метки POI. Иконки регистрирует приложение (пак или заглушка).
    icon_match: list = ["match", ["get", "class"]]
    classes_all: list[str] = []
    for blip, classes in BLIP_CLASSES.items():
        icon_match += [classes, blip]
        classes_all += classes
    icon_match.append("blip.generic")
    add({"id": "poi-blip", "type": "symbol", "source": "openmaptiles", "source-layer": "poi",
         "minzoom": 14, "filter": ["all", ["match", ["get", "class"], classes_all, True, False],
                                   ["<=", ["get", "rank"], ["step", ["zoom"], 5, 15, 15, 16, 30, 17, 100]]],
         "layout": {"icon-image": icon_match, "icon-size": opts.get("blip_size", 0.5), "icon-allow-overlap": False,
                    "text-field": ["step", ["zoom"], "", 17, NAME], "text-font": FONT_REGULAR, "text-size": 10,
                    "text-offset": [0, 1.4], "text-anchor": "top", "text-optional": True},
         "paint": {"text-color": c["label_minor"], **halo}})
    # Станции метро, МЦК и МЦД
    add({"id": "poi-metro", "type": "symbol", "source": "openmaptiles", "source-layer": "poi",
         "minzoom": 12, "filter": ["all", ["==", ["get", "class"], "railway"],
                                   ["match", ["get", "subclass"], ["subway", "station", "halt"], True, False]],
         "layout": {"icon-image": ["match", ["get", "subclass"], "subway", "blip.metro", "blip.rail"],
                    "icon-size": opts.get("blip_size", 0.5),
                    "text-field": ["step", ["zoom"], "", 14, NAME], "text-font": FONT_REGULAR, "text-size": 11,
                    "text-offset": [0, 1.3], "text-anchor": "top", "text-optional": True},
         "paint": {"text-color": c["label_minor"], **halo}})

    # Населённые пункты: районы Москвы, города и деревни области
    add({"id": "place-neighbourhood", "type": "symbol", "source": "openmaptiles", "source-layer": "place",
         "minzoom": 13, "filter": ["match", ["get", "class"], ["neighbourhood", "quarter"], True, False],
         "layout": {"text-field": NAME, "text-font": FONT_REGULAR, "text-size": 11,
                    "text-transform": "uppercase", "text-letter-spacing": 0.1, "text-max-width": 7},
         "paint": {"text-color": c["label_minor"], **halo}})
    add({"id": "place-suburb", "type": "symbol", "source": "openmaptiles", "source-layer": "place",
         "minzoom": 10, "maxzoom": 16, "filter": ["==", ["get", "class"], "suburb"],
         "layout": {"text-field": NAME, "text-font": FONT_BOLD, "text-size": ["interpolate", ["linear"], ["zoom"], 10, 10, 14, 13],
                    "text-transform": "uppercase", "text-letter-spacing": 0.15, "text-max-width": 8},
         "paint": {"text-color": c["label_minor"], **halo}})
    add({"id": "place-village", "type": "symbol", "source": "openmaptiles", "source-layer": "place",
         "minzoom": 10, "filter": ["match", ["get", "class"], ["village", "hamlet"], True, False],
         "layout": {"text-field": NAME, "text-font": FONT_REGULAR, "text-size": ["interpolate", ["linear"], ["zoom"], 10, 10, 14, 13]},
         "paint": {"text-color": c["label"], **halo}})
    add({"id": "place-town", "type": "symbol", "source": "openmaptiles", "source-layer": "place",
         "minzoom": 7, "filter": ["==", ["get", "class"], "town"],
         "layout": {"text-field": NAME, "text-font": FONT_BOLD, "text-size": ["interpolate", ["linear"], ["zoom"], 7, 11, 12, 15]},
         "paint": {"text-color": c["label"], **halo}})
    add({"id": "place-city", "type": "symbol", "source": "openmaptiles", "source-layer": "place",
         "maxzoom": 14, "filter": ["==", ["get", "class"], "city"],
         "layout": {"text-field": NAME, "text-font": FONT_BOLD,
                    "text-size": ["interpolate", ["linear"], ["zoom"], 5, 13, 10, 20],
                    "text-transform": opts.get("city_transform", "none"), "text-letter-spacing": 0.05},
         "paint": {"text-color": c["label_major"], **halo}})
    return L


def build_style(theme: str, palette: dict, variant: str) -> dict:
    colors = palette["colors"] if variant == "day" else make_night(palette)
    return {
        "version": 8,
        "name": f"FiberNavi {theme} ({variant})",
        "metadata": {"fibernavi:theme": theme, "fibernavi:variant": variant,
                     "fibernavi:generated": "tools/style_builder/build_styles.py — не править руками"},
        "sources": {"openmaptiles": {"type": "vector", "url": TILES_URL,
                                     "attribution": "© OpenMapTiles © OpenStreetMap contributors"}},
        "glyphs": GLYPHS_URL,
        "layers": build_layers(colors, palette),
    }


REQUIRED_COLORS = [
    "land", "residential", "commercial", "industrial", "park", "wood", "grass", "sand", "hospital_area",
    "school_area", "water", "water_outline", "building", "building_outline", "building_top", "building_glow",
    "boundary", "road_motorway", "road_trunk", "road_primary", "road_secondary", "road_minor", "road_service",
    "road_casing", "road_major_casing", "path", "rail", "subway", "label", "label_major", "label_minor",
    "label_halo", "road_label", "water_label", "shield_text", "shield_bg",
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="не писать файлы, только сверить с текущими")
    args = parser.parse_args()

    stale = []
    for path in sorted(PALETTES.glob("*.json")):
        theme = path.stem
        palette = json.loads(path.read_text())
        missing = [k for k in REQUIRED_COLORS if k not in palette["colors"]]
        if missing:
            print(f"{theme}: нет цветов {missing}", file=sys.stderr)
            return 1
        out_dir = THEMES_DIR / theme
        out_dir.mkdir(parents=True, exist_ok=True)
        for variant in ("day", "night"):
            text = json.dumps(build_style(theme, palette, variant), ensure_ascii=False, indent=1) + "\n"
            target = out_dir / f"{theme}.{variant}.json"
            if args.check:
                if not target.exists() or target.read_text() != text:
                    stale.append(str(target.relative_to(ROOT)))
            else:
                target.write_text(text)
                print(f"wrote {target.relative_to(ROOT)}")
    if stale:
        print("Устарели (запусти build_styles.py):", *stale, sep="\n  ", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
