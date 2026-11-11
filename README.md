# RealRoute RPG — восстановленный исходник

**Не декомпиляция.** Flutter в debug-сборке кладёт в `kernel_blob.bin` не только
байткод, но и **текст исходников** каждого файла приложения (он нужен
отладчику). Поэтому код ниже — это твой код буквально, а не реконструкция по
смелл-коду. Ничего не «дописано заново».

- Источник: `C:\Users\hackerman\Downloads\realroute-rpg-debug.apk` (189 МБ)
- Kernel: `assets/flutter_assets/kernel_blob.bin`, 78 МБ
- Исходный путь на твоей машине: `/home/hackerman/realroute/lib/...`
- Восстановлено: **13 файлов, 3963 строки**; потерь внутри кода нет

## Что это было

GPS-игра про бег по реальному городу. Выбираешь темп (шаг/бег/спринт) и длину,
приложение тянет улицы из OpenStreetMap через Overpass API, строит петлю нужной
длины и ведёт тебя по ней. Бежишь по настоящему миру, а на экране — карта,
прогресс, темп, средняя/макс. скорость.

- **офлайн-карта** — предзагрузка тайлов вокруг себя с лимитом ~250 тайлов;
- **три роутера** — Valhalla, OSRM (`routed-foot`) и собственный пешеходный
  граф из Overpass, с фолбэком;
- **шагомер** — через `pedometer`;
- **5 языков** — en, ru, fr, de, es, прямо в `app_strings.dart`.

## Что уже изменено после восстановления

1. **Убран античит.** Забег больше нельзя проиграть: `_updateCheat`,
   `RunPhase.failed`, лимиты скорости, счётчик «нет шагов» и диалог «КВЕСТ
   ПРОВАЛЕН» удалены. GPS врёт — наказывать за это бегуна плохая сделка.
2. **Плавное движение** (см. `FIXES.md`): камера больше не телепортируется
   каждые 500 мс, точка сглаживается, публикации от шагомера троттлятся.
3. **Появилась память.** `services/run_history.dart` + `screens/history_screen.dart`:
   каждый финиш пишется в `runs.json` (рядом с графом улиц и кэшем тайлов),
   на главной — сумма километров, в истории — список забегов, лучший темп,
   очистка с подтверждением.
4. **Появились тесты** — `test/`: метрики (haversine, смещение по азимуту,
   форматирование), `decodePolyline` (эталонный пример Google), сериализация
   `RunRecord`, геометрия клеток территории. Прогнано: **27/27 зелёные**,
   `flutter analyze` — **No issues found**.
5. **Завоёванные улицы** — карта делится на клетки z16 (~350 м), каждая
   пробежка «красит» пройденные, они копятся в `territory.json` и рисуются
   бирюзовыми квадратами на экране генерации маршрута. В диалоге финиша —
   «Новых клеток: +N», в истории и на экране маршрута — «Захвачено клеток: N».
6. **Офлайн-тайлы больше не висят** — `NetworkTileProvider` получил клиент с
   `connectionTimeout` 5 с и общим бюджетом 8 с, плюс `silenceExceptions`:
   вместо минутного ожидания на каждый тайл — прозрачная плитка.

### Проверено на этом проекте

| | |
|---|---|
| Flutter / Dart | 3.47.9 / 3.13.7 |
| `flutter_map` | 8.3.2 |
| `geolocator` | 14.1.2 |
| `flutter analyze` | No issues found (6.2 s) |
| `flutter test` | 19 passed |

Версии подобрались первым `pub get` и зафиксированы в `pubspec.yaml` — это те,
на которых код действительно компилируется.

## Файлы

| Файл | Строк | Что внутри |
|---|---:|---|
| `lib/main.dart` | ~65 | точка входа, `SharedPreferences`, роуты `/settings`, `/history` |
| `lib/theme.dart` | 99 | `AppColors`, тёмная тема |
| `lib/core/metrics.dart` | 51 | haversine, смещение по азимуту, форматирование |
| `lib/core/tiles.dart` | ~110 | клетки территории: lat/lon → z/x/y, углы, трек → клетки |
| `lib/l10n/app_strings.dart` | ~450 | все строки на 5 языках |
| `lib/screens/home_screen.dart` | ~235 | выбор темпа и длины, итоги, вход в историю |
| `lib/screens/route_map_screen.dart` | 607 | генерация маршрута, карта, старт |
| `lib/screens/run_map_screen.dart` | ~580 | сам забег, HUD, пауза, финиш, сохранение |
| `lib/screens/history_screen.dart` | ~220 | история забегов, итоги, очистка |
| `lib/screens/settings_screen.dart` | 494 | язык, офлайн-карта, сервер тайлов |
| `lib/services/run_tracker.dart` | ~410 | GPS-трек, сглаживание, скорость, шаги |
| `lib/services/run_history.dart` | ~180 | `RunRecord`, `runs.json`, агрегаты |
| `lib/services/territory.dart` | ~140 | `territory.json`, «завоёванные» клетки, `near()` для карты |
| `lib/services/pedestrian_router.dart` | 485 | граф улиц из Overpass + поиск пути |
| `lib/services/osrm_router.dart` | 93 | OSRM foot-роутинг |
| `lib/services/valhalla_router.dart` | 135 | Valhalla + `decodePolyline` |
| `lib/services/tile_prefetch.dart` | 359 | кэш тайлов, очередь загрузки |
| `test/*.dart` | ~330 | метрики, полилиния, история, клетки территории |

Внешние пакеты: `flutter_map`, `geolocator`, `latlong2`, `http`,
`path_provider`, `pedometer`, `shared_preferences`.

## Как поднять проект

```bash
# 1. сгенерировать отсутствующие платформенные папки (android/, ios/)
#    lib/ и pubspec.yaml не перезаписываются
flutter create --platforms=android,ios --project-name realroute .

# 2. зависимости
flutter pub get

# 3. проверка, тесты, запуск
flutter analyze
flutter test
flutter run
```

## Сборка APK (проверено, собралось)

```powershell
$sdk = '<workspace>\.android-sdk'
$env:ANDROID_HOME = $sdk; $env:ANDROID_SDK_ROOT = $sdk
$env:JAVA_HOME   = 'C:\Program Files\Java\jdk-17'
$env:PUB_CACHE   = '<workspace>\.pubcache'   # иначе .cxx плагинов пишется в read-only кэш
flutter build apk --debug
```

Результат: `build/app/outputs/flutter-apk/app-debug.apk` (156.6 МБ, ABI:
arm64-v8a, armeabi-v7a, x86_64) — `com.realroute.app`, `1.0.0`, minSdk 24,
targetSdk 36, все разрешения на месте.

Что понадобилось: JDK 17, Android SDK (`platforms;android-36`,
`build-tools;36.0.0`, `platform-tools`), **NDK 28.2.13676358** и **CMake 3.22.1**.
NDK нужен не нашему коду (нативного здесь нет), а плагинам
`path_provider_android` / `shared_preferences_android` — они тянут `jni`
с CMake-сборкой.

### Разрешения (Android)

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>

<uses-feature android:name="android.hardware.sensor.stepcounter" android:required="false"/>
```

Оригинал: `minSdkVersion 24`, `targetSdkVersion 36`, `compileSdk 36`.

## Что НЕ восстановлено

- **`pubspec.yaml`** — в APK его нет (это не `.dart`), поэтому файл написан
  заново: `sdk: ">=3.6.0 <4.0.0"` (в исходнике используются digit separators
  вроде `2_000_000_000`), зависимости — по импортам, версии подобраны и
  проверены сборкой. `pubspec.lock` тоже сгенерирован заново.
- **`android/`, `ios/`** — генерируются заново (шаг 1).
- **Иконки, keystore, CI** — их в APK и не было.
- Ключи `SharedPreferences`: `lang`, `tileServer`. Файл истории: `runs.json`.

## Что осталось из идей

- профиль территории: сколько клеток за неделю, «стрик» дней, топ-район;
- восстановление прерванного забега (звонок/падение процесса);
- рисовать территорию и на самом экране забега (сейчас — только на экране
  генерации маршрута, чтобы не тащить сотни полигонов в перерисовку).

## Инструменты

`../tools/recover_sources.py` — экстрактор исходников из kernel,
`../tools/dump_kernel.py` — строки/пакеты из kernel,
`../tools/axml.py` — парсер `AndroidManifest.xml`,
`../tools/inspect_apk.py` — разбор структуры APK,
`../tools/check_syntax.py` — проверка скобок (на случай, когда Flutter нет под рукой),
`../tools/check_imports.py` — проверка относительных импортов.
`../tools/kernel_blob.bin` оставлен как источник восстановления — из него всё
можно вытащить заново, даже если APK потеряется.
