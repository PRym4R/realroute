import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/metrics.dart';
import '../l10n/app_strings.dart';
import '../services/pedestrian_router.dart';
import '../services/run_history.dart';
import '../services/run_tracker.dart';
import '../services/territory.dart';
import '../services/tile_prefetch.dart';
import '../theme.dart';

class RunMapScreen extends StatefulWidget {
  const RunMapScreen({
    super.key,
    required this.l10n,
    required this.routeResult,
    required this.start,
    this.mode = RunMode.run,
  });

  final L10n l10n;
  final RouteResult routeResult;
  final LatLng start;
  final RunMode mode;

  @override
  State<RunMapScreen> createState() => _RunMapScreenState();
}

class _RunMapScreenState extends State<RunMapScreen>
    with SingleTickerProviderStateMixin {
  late final L10n t = widget.l10n;
  late final RunTracker _tracker = RunTracker(
    widget.routeResult.points,
    widget.routeResult.lengthM,
    (key) => t.t(key),
    mode: widget.mode,
  );

  final MapController _mapController = MapController();
  final DateTime _startedAt = DateTime.now();

  Timer? _uiTimer;
  late final Ticker _cameraTicker;
  bool _overlayShown = false;
  bool _mapReady = false;
  RunStats? _lastBannerStats;

  /// Camera smoothing. The old code called `move()` every 500 ms straight to
  /// the raw GPS point: a half-second teleport is what reads as "jerky".
  LatLng? _camCenter;
  int _lastCamMoveMs = -1000;
  bool _follow = true;
  int _newCells = 0;

  @override
  void initState() {
    super.initState();
    _tracker.addListener(_onTracker);
    _tracker.start();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_tracker.phase == RunPhase.running) _maybeAutoFinish();
    });
    _cameraTicker = createTicker(_onCameraFrame)..start();
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _cameraTicker.dispose();
    _tracker.removeListener(_onTracker);
    _tracker.dispose();
    super.dispose();
  }

  void _onTracker() {
    if (!mounted) return;
    final stats = _tracker.stats;
    if (stats.offRoute != (_lastBannerStats?.offRoute ?? false)) {
      if (stats.offRoute) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(t.t('offRoute')),
            backgroundColor: AppColors.red,
            duration: const Duration(seconds: 3),
          ));
      }
      _lastBannerStats = RunStats(
        phase: stats.phase,
        elapsedSec: stats.elapsedSec,
        distanceM: stats.distanceM,
        totalM: stats.totalM,
        remainingM: stats.remainingM,
        currentSpeedKmh: stats.currentSpeedKmh,
        maxSpeedKmh: stats.maxSpeedKmh,
        steps: stats.steps,
        offRoute: stats.offRoute,
      );
    }

    if (stats.phase == RunPhase.finished && !_overlayShown) {
      _overlayShown = true;
      _finishAndShow();
    }
    setState(() {});
  }

  Future<void> _finishAndShow() async {
    final fresh = await _saveRun();
    if (!mounted) return;
    setState(() => _newCells = fresh);
    _showResult();
  }

  /// Saves the run, then claims its streets. Returns how many cells were new.
  Future<int> _saveRun() async {
    final stats = _tracker.stats;
    await RunHistory.instance.add(
      RunRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        startedAt: _startedAt,
        mode: widget.mode,
        plannedM: stats.totalM,
        distanceM: stats.distanceM,
        elapsedSec: stats.elapsedSec,
        maxSpeedKmh: stats.maxSpeedKmh,
        steps: stats.steps,
      ),
    );
    final fresh = await Territory.instance.addTrack(_tracker.track);
    return fresh.length;
  }

  void _maybeAutoFinish() {
    if (_tracker.shouldFinishNow()) {
      _tracker.finish();
    }
  }

  void _onCameraFrame(Duration elapsed) {
    if (!_mapReady) return;
    final camera = _mapController.camera;
    final target = _tracker.smoothedPosition;

    if (_camCenter == null) {
      _camCenter = camera.center;
      return;
    }
    if (!_follow || target == null) return;

    // The camera is not where we left it: the user panned or pinched.
    // Fighting them for the rest of the run was the other half of the bug.
    if (haversineM(_camCenter!, camera.center) > 150) {
      setState(() => _follow = false);
      return;
    }

    final nowMs = elapsed.inMilliseconds;
    if (nowMs - _lastCamMoveMs < 50) return; // 20 Hz is smooth enough
    _lastCamMoveMs = nowMs;

    final d = haversineM(camera.center, target);
    final next = d < 2
        ? target
        : LatLng(
            camera.center.latitude +
                (target.latitude - camera.center.latitude) * 0.3,
            camera.center.longitude +
                (target.longitude - camera.center.longitude) * 0.3,
          );

    _camCenter = next;
    try {
      // keep the user's zoom: following should centre, not re-zoom
      _mapController.move(next, camera.zoom);
    } catch (_) {}
  }

  void _recenter() {
    _camCenter = null; // reseed from the real camera, so no false "user panned"
    setState(() => _follow = true);
  }

  Future<void> _confirmAbort() async {
    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.t('abortQuestion')),
        content: Text(t.t('abortHint')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.t('keepRunning')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.t('abort')),
          ),
        ],
      ),
    );
    if (keep == true && mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  void _showResult() {
    final stats = _tracker.stats;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ResultDialog(
        l10n: t,
        stats: stats,
        newCells: _newCells,
        onFinish: () => Navigator.of(context).popUntil((r) => r.isFirst),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _tracker.stats;
    final route = widget.routeResult.points;
    final covered = _tracker.coveredPoints();
    final dot = _tracker.smoothedPosition;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.routeResult.start,
                initialZoom: 16,
                minZoom: 12,
                maxZoom: 17,
                keepAlive: true,
                initialCameraFit: CameraFit.coordinates(
                  coordinates: [...widget.routeResult.points],
                  padding: const EdgeInsets.all(60),
                ),
                onMapReady: () => _mapReady = true,
              ),
              children: [
                TileLayer(
                  urlTemplate: '${TilePrefetcher.instance.tileServer}/{z}/{x}/{y}.png',
                  userAgentPackageName: 'app.sass.realroute',
                  tileProvider: TilePrefetcher.instance.tileProvider,
                ),
                PolylineLayer(
                  polylines: [
                    if (covered.isNotEmpty && covered.length >= 2)
                      Polyline(
                        points: covered,
                        color: AppColors.teal,
                        strokeWidth: 6,
                      ),
                    Polyline(
                      points: route,
                      color: AppColors.accent.withValues(alpha: 0.45),
                      strokeWidth: 5,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (dot != null)
                      Marker(
                        point: dot,
                        child: const _YouDot(),
                      ),
                  ],
                ),
                RichAttributionWidget(
                  attributions: const [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: SafeArea(
                child: _StatsBar(stats: stats, l10n: t),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: SafeArea(
                child: _Controls(
                  l10n: t,
                  phase: stats.phase,
                  onPause: _tracker.pause,
                  onResume: _tracker.resume,
                  onAbort: _confirmAbort,
                ),
              ),
            ),
            if (!_follow)
              Positioned(
                right: 16,
                bottom: 96,
                child: SafeArea(
                  child: FloatingActionButton.small(
                    heroTag: 'recenter',
                    backgroundColor: AppColors.surface2,
                    foregroundColor: AppColors.accent,
                    onPressed: _recenter,
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.stats, required this.l10n});

  final RunStats stats;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final paceSecPerKm = stats.avgPaceSecPerKm;
    final pace = paceSecPerKm > 0 && paceSecPerKm < 2000
        ? l10n.t('paceVal', {
            'm': (paceSecPerKm ~/ 60).toString(),
            'ss': (paceSecPerKm % 60).round().toString().padLeft(2, '0'),
          })
        : '—';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                l10n.t('remaining', {'n': stats.remainingKm.toStringAsFixed(2)}),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: AppColors.accent,
                ),
              ),
              const Spacer(),
              if (stats.offRoute)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.wrong_location, color: AppColors.red, size: 20),
                ),
              Text(
                fmtDurationSec(stats.elapsedSec),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Stat(label: l10n.t('distance'), value: '${stats.distanceKm.toStringAsFixed(2)} km'),
              _Stat(label: l10n.t('pace'), value: pace),
              _Stat(
                label: l10n.t('avgSpeed'),
                value: l10n.t('speedVal', {'n': stats.avgSpeedKmh.toStringAsFixed(1)}),
              ),
              _Stat(
                label: l10n.t('maxSpeed'),
                value: l10n.t('speedVal', {'n': stats.maxSpeedKmh.toStringAsFixed(1)}),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.l10n,
    required this.phase,
    required this.onPause,
    required this.onResume,
    required this.onAbort,
  });

  final L10n l10n;
  final RunPhase phase;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onAbort;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.surface2,
              foregroundColor: AppColors.text,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.line),
              ),
            ),
            icon: Icon(phase == RunPhase.paused
                ? Icons.play_arrow
                : Icons.pause),
            label: Text(phase == RunPhase.paused
                ? l10n.t('resume')
                : l10n.t('pause')),
            onPressed: phase == RunPhase.paused ? onResume : onPause,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: const BorderSide(color: AppColors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.close),
            label: Text(l10n.t('abort')),
            onPressed: onAbort,
          ),
        ),
      ],
    );
  }
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({
    required this.l10n,
    required this.stats,
    required this.onFinish,
    this.newCells = 0,
  });

  final L10n l10n;
  final RunStats stats;
  final VoidCallback onFinish;
  final int newCells;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(l10n.t('finish'),
          style: const TextStyle(color: AppColors.teal)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Res(l10n: l10n, label: l10n.t('distance'), value: '${stats.distanceKm.toStringAsFixed(2)} km'),
          _Res(l10n: l10n, label: l10n.t('resultTime'), value: fmtDurationSec(stats.elapsedSec)),
          _Res(
            l10n: l10n,
            label: l10n.t('maxSpeed'),
            value: l10n.t('speedVal', {'n': stats.maxSpeedKmh.toStringAsFixed(1)}),
          ),
          _Res(
            l10n: l10n,
            label: l10n.t('avgSpeed'),
            value: l10n.t('speedVal', {'n': stats.avgSpeedKmh.toStringAsFixed(1)}),
          ),
          _Res(
            l10n: l10n,
            label: l10n.t('lowSpeed'),
            value: stats.minMovingKmh == null
                ? '—'
                : l10n.t('speedVal', {'n': stats.minMovingKmh!.toStringAsFixed(1)}),
          ),
          _Res(label: l10n.t('steps'), l10n: l10n, value: stats.steps.toString()),
          const SizedBox(height: 12),
          Text(
            l10n.t('historySaved'),
            style: const TextStyle(color: AppColors.teal, fontSize: 12),
          ),
          if (newCells > 0) ...[
            const SizedBox(height: 4),
            Text(
              l10n.t('territoryNew', {'n': newCells.toString()}),
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            final nav = Navigator.of(context);
            nav.pop(); // close the dialog
            nav.popUntil((r) => r.isFirst); // leave the finished run
            nav.pushNamed('/history');
          },
          child: Text(l10n.t('history')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: onFinish,
          child: Text(l10n.t('home')),
        ),
      ],
    );
  }
}

class _Res extends StatelessWidget {
  const _Res({required this.l10n, required this.label, required this.value});

  final L10n l10n;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _YouDot extends StatelessWidget {
  const _YouDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.accent,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0x66FF7A2D), blurRadius: 12, spreadRadius: 2),
        ],
      ),
    );
  }
}
