# Why the run screen felt jerky, and what changed

Four independent causes, all in the code — not in the GPS and not in the
network.

## 1. The camera teleported every 500 ms

`run_map_screen.dart` called `_followUser()` from a `Timer.periodic(500ms)`:

```dart
_mapController.move(LatLng(pos.latitude, pos.longitude), 16.5, id: 'follow');
```

`move()` in flutter_map is an **instant** jump, not an animation. So twice a
second the map snapped to the raw GPS fix, at a hard-coded zoom of 16.5. With
10–30 m of accuracy that is tens of pixels of jump per frame. The same code also
**stole the camera** twice a second, so panning the map to look ahead was
impossible.

**Now:** a `Ticker` at 60 Hz eases the centre towards the smoothed position
(`k = 0.3`, capped at 20 Hz), and the zoom stays whatever the user chose. If the
camera ends up somewhere we did not put it (>150 m) the user panned: following
switches off and a "back to me" button appears.

## 2. The marker was drawn from the raw fix

`run_tracker.dart` handed `lastPosition` to `MarkerLayer` unchanged, while the
stream ran at `intervalDuration: 3s` with `distanceFilter: 0`. Three seconds
between fixes at 15–30 m accuracy means the jitter is larger than the movement:
standing still, the dot wandered 10–20 m.

**Now:**

- stream at 1 fix/second with `distanceFilter: 2` (more samples to smooth over);
- `_smooth()` — a low-pass filter with a 2 m deadband (standing still, the dot
  does not move at all) and an accuracy-dependent α: 0.6 at ≤8 m, 0.4 at ≤15 m,
  0.22 beyond. A genuine jump >25 m (a fresh fix after losing signal) is accepted
  outright instead of being smeared;
- the marker, the track tail (`coveredPoints`) and the camera all read
  `smoothedPosition`.

## 3. The whole screen rebuilt on every step

`_onSteps` called `_publish()` on **every step** — two or three full rebuilds of
`FlutterMap` (tiles + polylines + markers) per second, on top of the GPS
updates. That is where the stutter came from.

**Now:** step-driven publishes are throttled to about once per 900 ms, and the
stats ticker in the screen runs at 1 s instead of 500 ms.

## 4. Anti-cheat removed entirely

`_updateCheat` and everything around it (`RunPhase.failed`, `CheatReason`,
`RunModeTuning` speed limits, the `_overLimitSeconds` / `_noStepSeconds`
counters, the "QUEST FAILED" dialog) are **gone**. A run can no longer be lost:
GPS lies, phones lie, and punishing the runner for it is a bad trade.

Speed in the HUD is still a median (so the number does not flicker) but it no
longer decides anything. `minMovingKmh` ("Min" in the results) still works.

## Worth checking on a phone

1. **Stand still for a minute** — the dot must not shake, speed ~0.
2. **Walk 50 m** — the dot should move smoothly.
3. **Pan the map mid-run** — it must not snap back; the "my location" button
   resumes following.
4. **Finish a short route** — "Run saved to history", the home screen shows
   "Runs: 1 · 0.4 km", the finish dialog reports new territory cells.
5. **Kill the app and reopen** — history and territory survive (`runs.json`,
   `territory.json`).
6. **Airplane mode** — the map is blank (no tiles), but a missing tile now gives
   up in 8 s instead of hanging on the TCP timeout.

## Verification

On Flutter 3.47.9 / Dart 3.13.7:

```
flutter analyze  → No issues found!
flutter test     → 27 tests, All tests passed!
```

The compiler caught two real errors on the way, both fixed:
`position.accuracy <= 0 ? 999 : ...` produced `num` where `double` was needed,
and digit separators in `tile_prefetch.dart` required `sdk: >=3.6.0` in the
pubspec (the recovered manifest said `>=3.0.0`).
