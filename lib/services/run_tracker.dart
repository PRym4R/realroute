import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:pedometer/pedometer.dart';

import '../core/metrics.dart';

const double maxAccuracyM = 35;
const double routeFinishMarginM = 35;
const double offRouteMarginM = 70;
const double trackPointMinDistanceM = 2.5;

enum RunMode { walk, run, sprint }

class RunPhase {
  const RunPhase._(this.name);

  static const RunPhase idle = RunPhase._('idle');
  static const RunPhase running = RunPhase._('running');
  static const RunPhase paused = RunPhase._('paused');
  static const RunPhase finished = RunPhase._('finished');

  final String name;
}

class RunStats {
  RunStats({
    required this.phase,
    required this.elapsedSec,
    required this.distanceM,
    required this.totalM,
    required this.remainingM,
    required this.currentSpeedKmh,
    required this.maxSpeedKmh,
    required this.steps,
    required this.offRoute,
    this.minMovingKmh,
  });

  final RunPhase phase;
  final int elapsedSec;
  final double distanceM;
  final double totalM;
  final double remainingM;
  final double currentSpeedKmh;
  final double maxSpeedKmh;
  final double? minMovingKmh;
  final int steps;
  final bool offRoute;

  double get progress =>
      totalM <= 0 ? 0 : (1 - remainingM / totalM).clamp(0.0, 1.0);

  double get avgSpeedKmh =>
      elapsedSec <= 0 ? 0 : distanceM / elapsedSec * 3.6;

  double get avgPaceSecPerKm =>
      distanceM < 30 ? 0 : elapsedSec / (distanceM / 1000);

  double get distanceKm => distanceM / 1000;

  double get remainingKm => remainingM / 1000;
}

class RunTracker extends ChangeNotifier {
  RunTracker(this.routePoints, this.totalM, this._t, {this.mode = RunMode.run});

  final RunMode mode;
  final List<LatLng> routePoints;
  final double totalM;
  final String Function(String key) _t;

  final List<double> _cumulativeLengths = <double>[0];
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<StepCount>? _stepSub;
  Timer? _ticker;

  RunPhase _phase = RunPhase.idle;

  final List<LatLng> track = <LatLng>[];

  int _elapsedSec = 0;
  double _distanceM = 0;
  double _currentSpeedKmh = 0;
  double _maxSpeedKmh = 0;
  double? _minMovingKmh;
  late int _stepBaseline;
  late int _latestStepValue;
  bool _hasSteps = false;

  Position? _lastPosition;
  bool _offRoute = false;

  /// Smoothed position for drawing: raw fixes jitter by 10-30 m, which made
  /// the dot (and the camera chasing it) jump around while standing still.
  LatLng? _smoothed;
  LatLng? get smoothedPosition => _smoothed ?? _lastPositionPoint;

  LatLng? get _lastPositionPoint => _lastPosition == null
      ? null
      : LatLng(_lastPosition!.latitude, _lastPosition!.longitude);

  /// Rolling window so one noisy fix cannot blink the speed to 70 km/h.
  static const int _speedWindowSize = 5;
  final List<double> _speedWindow = <double>[];

  /// Step events arrive every step; repainting the whole map that often is
  /// pointless, so step-driven publishes are throttled.
  int _lastStepPublishMs = 0;
  static const int _stepPublishIntervalMs = 900;

  double _routeProgressM = 0;
  int _lastSegmentIndex = 0;

  RunStats? _stats;
  RunStats get stats =>
      _stats ?? _snapshot(RunPhase.idle);

  RunPhase get phase => _phase;

  Position? get lastPosition => _lastPosition;

  double get routeProgressM => _routeProgressM;

  RunStats _snapshot(RunPhase phase) {
    final double remaining;
    if (phase == RunPhase.finished) {
      remaining = 0;
    } else {
      remaining = (totalM - _routeProgressM).clamp(0, totalM);
    }
    return RunStats(
      phase: phase,
      elapsedSec: _elapsedSec,
      distanceM: _distanceM,
      totalM: totalM,
      remainingM: remaining,
      currentSpeedKmh: phase == RunPhase.running ? _currentSpeedKmh : 0,
      maxSpeedKmh: _maxSpeedKmh,
      steps: _hasSteps ? math.max(0, _latestStepValue - _stepBaseline) : 0,
      offRoute: _offRoute,
      minMovingKmh: _minMovingKmh,
    );
  }

  void _publish() {
    _stats = _snapshot(_phase);
    notifyListeners();
  }

  void start() {
    if (_phase == RunPhase.running) return;
    _phase = RunPhase.running;

    for (var i = 1; i < routePoints.length; i++) {
      _cumulativeLengths
          .add(_cumulativeLengths[i - 1] + haversineM(routePoints[i - 1], routePoints[i]));
    }

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_phase == RunPhase.running) {
        _elapsedSec++;
        _publish();
      }
    });

    _positionSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        // One fix per second (was 3 s): more samples is what makes the
        // smoothing below work, and it is what running apps normally use.
        distanceFilter: 2,
        intervalDuration: const Duration(seconds: 1),
        maxUpdateAge: const Duration(seconds: 15),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'RealRoute RPG',
          notificationText: _t('waitForGps'),
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
    ).listen(_onPosition, onError: (Object _) {});

    _stepSub = Pedometer.stepCountStream.listen(_onSteps, onError: (Object _) {});

    _publish();
  }

  void _onSteps(StepCount event) {
    if (!_hasSteps) {
      _hasSteps = true;
      _stepBaseline = event.steps;
    }
    _latestStepValue = event.steps;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastStepPublishMs < _stepPublishIntervalMs) return;
    _lastStepPublishMs = nowMs;
    _publish();
  }

  void _onPosition(Position position) {
    if (_phase != RunPhase.running) return;

    final accuracy = position.accuracy <= 0 ? 999.0 : position.accuracy;
    if (accuracy > maxAccuracyM) return;

    final here = LatLng(position.latitude, position.longitude);
    final nowMs = position.timestamp.millisecondsSinceEpoch;

    // Everything drawn comes from the smoothed point; raw fixes jitter.
    _smooth(here, accuracy);

    var dtSec = 1.0;
    var segmentM = 0.0;
    if (_lastPosition != null) {
      final lastMs = _lastPosition!.timestamp.millisecondsSinceEpoch;
      dtSec = (nowMs - lastMs) / 1000.0;
      segmentM = haversineM(LatLng(_lastPosition!.latitude, _lastPosition!.longitude), here);
      if (dtSec <= 0 || dtSec > 60 || segmentM > 400) {
        _lastPosition = position;
        return;
      }
    }

    final speedKmh = _measureSpeed(position, segmentM, dtSec);
    _currentSpeedKmh = speedKmh;
    _maxSpeedKmh = math.max(_maxSpeedKmh, speedKmh);

    if (_lastPosition == null || segmentM >= trackPointMinDistanceM) {
      _distanceM += segmentM;
      track.add(here);
    }

    if (speedKmh > 1.0) {
      final min = _minMovingKmh;
      _minMovingKmh = min == null ? speedKmh : math.min(min, speedKmh);
    }

    _updateProgress(here);

    _lastPosition = position;
    _publish();
  }

  /// Low-pass filter with a deadband: it hides GPS noise but never lags behind
  /// a real move. Standing still produces 10-30 m of scatter, and that is what
  /// used to shake the dot and drag the camera back and forth.
  void _smooth(LatLng here, double accuracy) {
    final prev = _smoothed;
    if (prev == null) {
      _smoothed = here;
      return;
    }
    final dist = haversineM(prev, here);
    if (dist < 2.0) return; // standing still: this is noise, not movement

    final alpha = dist > 25
        ? 1.0 // a genuine jump (fresh fix after a gap) must not be blurred
        : accuracy <= 8
            ? 0.6
            : accuracy <= 15
                ? 0.4
                : 0.22; // a 30 m fix deserves less trust

    _smoothed = LatLng(
      prev.latitude + (here.latitude - prev.latitude) * alpha,
      prev.longitude + (here.longitude - prev.longitude) * alpha,
    );
  }

  /// Speed for the HUD. One bad fix must not blink the number to 70 km/h, so
  /// this is the median of the last few samples, and the GPS doppler speed is
  /// only trusted when its own accuracy says it deserves it.
  double _measureSpeed(Position position, double segmentM, double dtSec) {
    final dopplerOk = position.speedAccuracy > 0 && position.speedAccuracy <= 3.0;
    final double? doppler = dopplerOk && position.speed >= 0
        ? position.speed * 3.6
        : null;
    final double? derived = dtSec >= 0.8 && position.accuracy <= 25
        ? segmentM / dtSec * 3.6
        : null;

    double? instant;
    if (derived != null && doppler != null) {
      instant = math.min(derived, doppler);
    } else {
      instant = derived ?? doppler;
    }
    if (instant == null) return _currentSpeedKmh;

    _speedWindow.add(instant);
    if (_speedWindow.length > _speedWindowSize) _speedWindow.removeAt(0);
    final sorted = List<double>.of(_speedWindow)..sort();
    return sorted[sorted.length ~/ 2];
  }

  void _updateProgress(LatLng here) {
    final n = routePoints.length;
    if (n < 2) return;
    final searchFrom = math.max(0, _lastSegmentIndex - 12);
    final searchTo = math.min(n - 2, _lastSegmentIndex + 60);

    var bestSeg = -1;
    var bestT = 0.0;
    var bestDistM = double.infinity;

    for (var seg = searchFrom; seg <= searchTo; seg++) {
      final a = routePoints[seg];
      final b = routePoints[seg + 1];
      final t = _projectionT(a, b, here);
      final projected = LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );
      final d = haversineM(here, projected);
      if (d < bestDistM) {
        bestDistM = d;
        bestSeg = seg;
        bestT = t;
      }
    }

    if (bestSeg < 0) return;

    if (bestDistM > offRouteMarginM) {
      _offRoute = true;
      return;
    }
    _offRoute = false;

    final along = _cumulativeLengths[bestSeg] +
        bestT * (_cumulativeLengths[bestSeg + 1] - _cumulativeLengths[bestSeg]);
    if (along > _routeProgressM - 2) {
      _routeProgressM = math.max(_routeProgressM, along);
    }
    if (bestSeg + 1 < n - 1) _lastSegmentIndex = bestSeg + 1;
  }

  double _projectionT(LatLng a, LatLng b, LatLng p) {
    final cosLat = math.cos(p.latitude * math.pi / 180);
    double fx(LatLng x) => x.longitude * cosLat;
    double fy(LatLng x) => x.latitude;
    final ax = fx(a), ay = fy(a);
    final bx = fx(b), by = fy(b);
    final px = fx(p), py = fy(p);
    final abx = bx - ax;
    final aby = by - ay;
    final denom = abx * abx + aby * aby;
    if (denom < 1e-12) return 0;
    return (((px - ax) * abx + (py - ay) * aby) / denom).clamp(0.0, 1.0);
  }

  void finish() {
    if (_phase == RunPhase.finished) return;
    _phase = RunPhase.finished;
    stopStreams(notify: true);
  }

  void pause() {
    if (_phase != RunPhase.running) return;
    _phase = RunPhase.paused;
    _lastPosition = null;
    _currentSpeedKmh = 0;
    _speedWindow.clear();
    _publish();
  }

  void resume() {
    if (_phase != RunPhase.paused) return;
    _phase = RunPhase.running;
    // The first fix after a pause must not be compared with the pre-pause one.
    _lastPosition = null;
    _speedWindow.clear();
    _publish();
  }

  bool shouldFinishNow() {
    if (totalM <= 0) return false;
    return totalM - _routeProgressM <= routeFinishMarginM;
  }

  List<LatLng> coveredPoints() {
    if (routePoints.isEmpty) return const [];
    final covered = <LatLng>[...routePoints.take(_lastSegmentIndex + 1)];
    final pos = smoothedPosition;
    if (pos != null) covered.add(pos);
    return covered;
  }

  void stopStreams({bool notify = false}) {
    _positionSub?.cancel();
    _positionSub = null;
    _stepSub?.cancel();
    _stepSub = null;
    _ticker?.cancel();
    _ticker = null;
    if (notify) _publish();
  }

  @override
  void dispose() {
    stopStreams();
    super.dispose();
  }
}
