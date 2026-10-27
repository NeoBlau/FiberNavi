# Инструменты

| Инструмент | Что делает |
|---|---|
| `style_builder/` | Палитры тем → MapLibre-стили Москвы и области (день/ночь) в `App/Themes/<тема>/` |
| `pack_tool/` | Выгрузка из своей копии игры → пак `Assets/UserPacks/<тема>/` с `manifest.json` |
| `voice_tagger/` | Whisper-разметка реплик, нарезка слов, страница проверки, `voice_manifest.json` |

Зависимости: Python 3.10+, `pip install pillow pyyaml openai-whisper`, ffmpeg.

## Как собрать пак (на примере GTA San Andreas)

1. **Выгрузи файлы из своей установленной игры** в `raw/gta_sa/`. Что и откуда брать, написано в шапке
   `pack_tool/maps/gta_sa.yml` (для остальных игр — `gta_v.yml`, `rdr2.yml`, `gta_vi.yml`):
   - `hud/` — все текстуры из `hud.txd` (Magic.TXD → PNG/DDS), имена не меняй;
   - `tiles/` — 5–10 тайлов радара, переименованных в `water_1.png`, `park_1.png`, `road_1.png`, `urban_1.png`;
   - `sfx/` — звуки меню в WAV (SAAT), имена с префиксами `select`, `confirm`, `blip`, `mission`;
   - `voice/cj/` — реплики в WAV, сколько угодно;
   - `font/` — Pricedown (бесплатно для личного использования).

2. **Собери пак:**
   ```sh
   python3 tools/pack_tool/pack_tool.py build --in raw/gta_sa --out Assets/UserPacks/sanAndreas \
       --map tools/pack_tool/maps/gta_sa.yml
   ```
   Отчёт покажет, чего не хватает, где дубликаты и какие картинки без прозрачности.
   Ключи с `absent: true` (например, заправки в SA нет) заменяются заглушкой.

3. **Разметь голос:**
   ```sh
   V=Assets/UserPacks/sanAndreas/voice/cj
   python3 tools/voice_tagger/voice_tagger.py suggest --voice $V      # Whisper, ~1–2 с на реплику
   python3 tools/voice_tagger/voice_tagger.py review  --voice $V      # http://localhost:8765, правишь события
   python3 tools/voice_tagger/voice_tagger.py build   --voice $V --character cj
   ```
   Повторный `suggest` не затирает строки, отмеченные как проверенные. Забракованные дубли
   слов переживают повторный `build`.

4. **Собери приложение** (`xcodegen generate`, Xcode). Паки из `Assets/UserPacks` попадают в бандл.
   Можно и без пересборки: закинуть папку темы на телефон через «Файлы» → FiberNavi → `UserPacks/`.

## Происхождение файлов

В `manifest.json` у каждого файла есть `source` и `origin`: `own` — выгружено из своей копии
(с путём внутри игры), `licensed` — свободный шрифт с лицензией. Папка `Assets/UserPacks/` в `.gitignore`,
в репозиторий ничего из игр не попадает.

## Тесты

```sh
python3 tools/style_builder/build_styles.py --check
python3 -m unittest tools/pack_tool/test_pack_tool.py tools/voice_tagger/test_voice_tagger.py
```
