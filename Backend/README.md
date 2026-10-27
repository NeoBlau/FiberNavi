# Backend

Три сервиса в Docker Compose:

| Сервис | Порт | Что делает |
|---|---|---|
| `valhalla` | 8002 | Маршруты, манёвры, альтернативы (`/route`) |
| `photon` | 2322 | Поиск адресов и мест (`/api?q=`, `/reverse`) |
| `tiles` | 8080 | Раздача `moscow.pmtiles` (`/moscow/{z}/{x}/{y}.mvt`, TileJSON `/moscow.json`) |

## Запуск

```sh
cd Backend
cp .env.example .env        # впиши PHOTON_DUMP_URL
./scripts/prepare_region.sh # скачивание и обрезка данных, ~2–6 ГБ
docker compose up -d        # первый старт Valhalla строит граф: 10–30 минут
./scripts/smoke_test.sh     # проверка сервисов и времени маршрута
```

Ресурсы: 4+ ГБ RAM (Photon берёт 2 ГБ кучи), ~15 ГБ диска. Для обрезки по области полезен `osmium` (`brew install osmium-tool`), без него граф строится по всему ЦФО.

## Обновление данных

`FORCE=1 ./scripts/prepare_region.sh && docker compose restart`

## Атрибуция

Данные © OpenStreetMap contributors (ODbL). Тайлы: Planetiler, схема OpenMapTiles. Приложение показывает атрибуцию на карте.

Valhalla на телефоне (полный офлайн) — отдельный этап 7a, см. `docs/PLAN.md`. Этот бэкенд остаётся источником данных и запасным вариантом.
