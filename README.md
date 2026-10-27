# FiberNavi

Личный навигатор для iPhone в стилистике карт из open-world игр. Реальные карты OSM, реальные маршруты, оформление и голос из своих копий игр. Ставится сайдлоадом, в App Store не публикуется.

План и принятые решения: [docs/PLAN.md](docs/PLAN.md).

## Сборка

Нужны Xcode 16+ и [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open FiberNavi.xcodeproj
```

Каждый пуш собирает и прогоняет тесты в симуляторе GitHub Actions (`.github/workflows/ios.yml`).

До этапа 2 карта берёт стиль OpenFreeMap (данные © OpenStreetMap contributors). Стиль задаётся ключом `FNMapStyleURL` в `project.yml`.

## Ассеты из игр

Ассеты кладутся в `Assets/UserPacks/<тема>/`, подробности в [Assets/UserPacks/README.md](Assets/UserPacks/README.md). Файлы из игр в git не попадают. Без них приложение работает на заглушках.
