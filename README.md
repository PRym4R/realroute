# RealRoute RPG

Run through the real world. Pick a pace and a distance, the app pulls the
streets around you from OpenStreetMap, builds a loop of roughly that length and
guides you along it while you actually run it outdoors.

## Where this source came from

**This is not a decompilation.** Flutter debug builds embed the *source text* of
every app library in `assets/flutter_assets/kernel_blob.bin` (the VM debugger
needs it), so the code here is the original code, recovered byte for byte from a
debug APK. Nothing was retyped or reconstructed from bytecode.

- Recovered: 13 files, 3963 lines from `kernel_blob.bin` (78 MB)
- `pubspec.yaml` is the one thing that cannot be recovered (it is not a `.dart`
  file), so it was rewritten: dependencies come from the imports, versions were
  resolved by building, and the SDK floor (`>=3.6.0`) comes from digit
  separators used in the original code.

## What the game does

- **Route generation**: Overpass API gives the street graph around you, and a
  pedestrian router builds a loop of the requested length.
- **Two more routers with fallback**: Valhalla and OSRM (`routed-foot`).
- **Offline map**: tiles around you can be prefetched, with a ~250-tile cap that
  respects the OSM tile policy.
- **Step counter** via `pedometer`.
- **Five languages**: English, Russian, French, German, Spanish — the app starts
  in your phone's language and remembers a manual choice.

## What was added on top of the recovery

1. **Anti-cheat removed.** A run can no longer be failed: the wheel/speed check,
   the "no steps" timer, `RunPhase.failed` and the failure dialog are gone. GPS
   lies; punishing the runner for it is a bad trade.
2. **Smooth movement.** The camera used to teleport to the raw GPS fix every
   500 ms; it now eases towards a smoothed position at up to 20 Hz, keeps the
   user's zoom, and stops following when you pan the map. See `FIXES.md`.
3. **The game remembers.** Every finish is written to `runs.json`: totals,
   per-run pace, best pace, a history screen, and a "saved" line on the result
   dialog.
4. **Territory.** The map is a grid of z16 cells (~350 m). Every run claims the
   cells it passes through, stored in `territory.json` and drawn as teal squares
   on the route screen. The finish dialog reports how many were new.
5. **Tiles no longer hang offline.** `NetworkTileProvider` now gets a client with
   a 5 s connect timeout and an 8 s total budget, plus `silenceExceptions`.

## Verified with

| | |
|---|---|
| Flutter / Dart | 3.47.9 / 3.13.7 |
| `flutter_map` | 8.3.2 |
| `geolocator` | 14.1.2 |
| `flutter analyze` | No issues found |
| `flutter test` | 27 passed |

## Layout

| File | Lines | Contents |
|---|---:|---|
| `lib/main.dart` | ~75 | entry point, language pick, state files, routes |
| `lib/theme.dart` | 99 | `AppColors`, dark theme |
| `lib/core/metrics.dart` | 51 | haversine, bearing offset, formatting |
| `lib/core/tiles.dart` | ~115 | territory cells: lat/lon → z/x/y, corners, track → cells |
| `lib/l10n/app_strings.dart` | ~480 | every string in five languages |
| `lib/screens/home_screen.dart` | ~235 | pace and distance pickers, totals, history entry |
| `lib/screens/route_map_screen.dart` | ~645 | route generation, map, territory overlay, start |
| `lib/screens/run_map_screen.dart` | ~600 | the run itself: HUD, pause, finish, saving |
| `lib/screens/history_screen.dart` | ~235 | run list, totals, best pace, clear |
| `lib/screens/settings_screen.dart` | 494 | language, offline map, tile server |
| `lib/services/run_tracker.dart` | ~410 | GPS stream, smoothing, speed, steps, progress |
| `lib/services/run_history.dart` | ~185 | `RunRecord`, `runs.json`, aggregates |
| `lib/services/territory.dart` | ~150 | `territory.json`, claimed cells, `near()` |
| `lib/services/pedestrian_router.dart` | 485 | street graph from Overpass + path search |
| `lib/services/osrm_router.dart` | 93 | OSRM foot routing |
| `lib/services/valhalla_router.dart` | 135 | Valhalla + `decodePolyline` |
| `lib/services/tile_prefetch.dart` | ~375 | tile cache, download queue, timeout client |
| `test/*.dart` | ~330 | metrics, polyline, history, territory grid |

External packages: `flutter_map`, `geolocator`, `latlong2`, `http`,
`path_provider`, `pedometer`, `shared_preferences`.

## Build and run

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

### Building an APK (verified)

```powershell
$sdk = '<workspace>\.android-sdk'
$env:ANDROID_HOME = $sdk; $env:ANDROID_SDK_ROOT = $sdk
$env:JAVA_HOME   = 'C:\Program Files\Java\jdk-17'
$env:PUB_CACHE   = '<workspace>\.pubcache'   # plugin .cxx dirs, otherwise read-only
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk` — `com.realroute.app`,
`1.0.0`, minSdk 24, targetSdk 36, arm64-v8a / armeabi-v7a / x86_64.

Requires JDK 17 and an Android SDK with `platforms;android-36`,
`build-tools;36.0.0`, `platform-tools`, plus **NDK 28.2.13676358** and
**CMake 3.22.1** — the NDK is not for this project (there is no native code) but
for `path_provider_android` / `shared_preferences_android`, which pull `jni`
with a CMake build.

### Android permissions

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

`ACTIVITY_RECOGNITION` is for the step counter,
`FOREGROUND_SERVICE_LOCATION` for background tracking via `geolocator`.

## Known limits

- Android and iOS shells are regenerated (`flutter create`), not recovered —
  the APK only contains them compiled.
- No app icon, no keystore, no CI: the original had none either.
- State files live in the app support directory: `runs.json`, `territory.json`;
  preferences use `lang` and `tileServer`.
- Territory is drawn on the route screen only; adding it to the running screen
  means hundreds of polygons in a widget that already rebuilds once a second.

## Credits

Map data © OpenStreetMap contributors (ODbL). Routing via Overpass, Valhalla and
OSRM.
