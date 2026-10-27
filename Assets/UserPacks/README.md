# UserPacks

Сюда кладутся ассеты, извлечённые из своих копий игр. Содержимое папки в `.gitignore`.

```
UserPacks/
  sanAndreas/ gta5/ rdr2/ gta6concept/
    manifest.json      # по образцу manifest.example.json
    map/  hud/  blip/  fonts/  sfx/  voice/
    ref/               # только gta6concept: кадры карты и HUD из трейлеров
```

Форматы: метки PNG/SVG, шрифты TTF/OTF, звуки WAV/OGG/MP3.
Приложение работает и без паков: недостающие файлы заменяются заглушками, а в debug-лог пишется предупреждение.
