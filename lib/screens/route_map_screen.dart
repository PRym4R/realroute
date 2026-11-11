import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/tiles.dart';
import '../l10n/app_strings.dart';
import '../services/osrm_router.dart';
import '../services/pedestrian_router.dart';
import '../services/territory.dart';
import '../services/valhalla_router.dart';
import '../services/run_tracker.dart' show RunMode;
import '../services/tile_prefetch.dart';
import '../theme.dart';
import 'run_map_screen.dart';

enum _Stage { locating, downloading, computing, ready, error, permission }

class RouteMapScreen extends StatefulWidget {
  const RouteMapScreen({
    super.key,
    required this.l10n,
    required this.targetKm,
    this.mode = RunMode.run,
  });

  final L10n l10n;
  final double targetKm;
  final RunMode mode;

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final PedestrianRouter _router = PedestrianRouter();
  final ValhallaRouter _valhalla = ValhallaRouter();
  final OsrmRouter _osrm = OsrmRouter();
  bool _useOverpass = false;
  int _offlineTiles = 0;
  List<Polygon> _territoryPolys = const [];
  String _diag = '';
  final MapController _mapController = MapController();

  _Stage _stage = _Stage.locating;
  L10n get t => widget.l10n;

  String _errorKey = 'network';
  LatLng? _myPos;
  PedGraph? _graph;
  RouteResult? _route;
  int _elapsedSec = 0;
  Timer? _tick;
  int _attempts = 0;
  final Stopwatch _sw = Stopwatch();

  void _startTick() {
    _sw.reset();
    _sw.start();
    _elapsedSec = 0;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _sw.isRunning == false) return;
      setState(() => _elapsedSec = _sw.elapsed.inSeconds);
    });
  }

  void _stopTick() {
    _sw.stop();
    _tick?.cancel();
    _tick = null;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _stopTick();
    _router.dispose();
    _valhalla.dispose();
    _osrm.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _startTick();
    setState(() => _stage = _Stage.locating);

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.permission;
        _errorKey = 'permissionNeeded';
      });
      return;
    }

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorKey = 'locationOff';
      });
      return;
    }

    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) {
        if (!mounted) return;
        setState(() => _stage = _Stage.error);
        return;
      }
      pos = last;
    }

    if (!mounted) return;
    setState(() {
      _myPos = LatLng(pos.latitude, pos.longitude);
      _stage = _Stage.downloading;
    });

    await _fetchRoute(regenerate: false);
  }

  Future<void> _fetchRoute({required bool regenerate}) async {
    final pos = _myPos;
    if (pos == null) return;

    setState(() {
      _stage = _Stage.computing;
      _errorKey = 'network';
    });
    _startTick();

    if (!_useOverpass) {
      final notes = <String>[];
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final route = await _valhalla.generate(
            start: pos,
            targetKm: widget.targetKm,
          );
          _stopTick();
          if (!mounted) return;
          setState(() {
            _route = route;
            _stage = _Stage.ready;
          });
          _cacheOfflineMap(route.points);
          _fitMap();
          return;
        } catch (e) {
          notes.add('valhalla:${_shortError(e)}');
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 900));
          }
        }
      }
      try {
        final route = await _osrm.generate(
          start: pos,
          targetKm: widget.targetKm,
        );
        _stopTick();
        if (!mounted) return;
        setState(() {
          _route = route;
          _stage = _Stage.ready;
        });
        _cacheOfflineMap(route.points);
        _fitMap();
        return;
      } catch (e) {
        notes.add('osrm:${_shortError(e)}');
      }
      _diag = notes.join(' · ');
      _useOverpass = true;
    }

    final radiusM = (500 + 350 * widget.targetKm).round().clamp(1000, 4200);
    final sessionHit = regenerate
        ? null
        : GraphSession.take(pos.latitude, pos.longitude, radiusM);
    if (sessionHit != null) {
      setState(() {
        _graph = sessionHit;
        _stage = _Stage.computing;
      });
    } else if (_graph == null) {
      setState(() => _stage = _Stage.downloading);
    }

    try {
      final graph = _graph ?? sessionHit ?? await _router.fetchGraph(
            lat: pos.latitude,
            lng: pos.longitude,
            radiusM: radiusM,
          );
      final route = _router.pickRoute(
        graph: graph,
        start: pos,
        targetKm: widget.targetKm,
      );

      _stopTick();
      if (!mounted) return;
      _attempts = 0;
      setState(() {
        _graph = graph;
        _route = route;
        _territoryPolys = _conqueredPolygons(route.start);
        _stage = _Stage.ready;
      });
      _cacheOfflineMap(route.points);
      _fitMap();
    } on RouterError catch (e) {
      _stopTick();
      if (!mounted) return;
      if (e.key == 'network' && _attempts < 2 && _graph == null) {
        _attempts++;
        await Future<void>.delayed(const Duration(seconds: 4));
        if (!mounted) return;
        if (_myPos != null) {
          _startTick();
          setState(() => _stage = _Stage.downloading);
          return _fetchRoute(regenerate: false);
        }
      }
      setState(() {
        _errorKey = e.key == 'noData' ? 'noData' : e.key;
        _diag = 'overpass:${e.key}${_diag.isEmpty ? '' : ' · $_diag'}';
        _stage = _Stage.error;
      });
    } catch (_) {
      _stopTick();
      if (!mounted) return;
      setState(() {
        _errorKey = 'network';
        _diag = 'overpass:exception${_diag.isEmpty ? '' : ' · $_diag'}';
        _stage = _Stage.error;
      });
    }
  }

  Future<void> _cacheOfflineMap(List<LatLng> points) async {
    final count = await TilePrefetcher.instance.prefetchCorridor(points);
    if (!mounted || count == 0) return;
    setState(() => _offlineTiles = count);
  }

  /// The streets already conquered around the start, as translucent cells.
  /// Computed once per route: building a few hundred polygons on every rebuild
  /// would be wasteful.
  List<Polygon> _conqueredPolygons(LatLng around) {
    final cells = Territory.instance.near(around, radiusM: 2000);
    return [
      for (final cell in cells)
        Polygon(
          points: cellCorners(cell),
          color: AppColors.teal.withValues(alpha: 0.16),
          borderColor: AppColors.teal.withValues(alpha: 0.38),
          borderStrokeWidth: 1,
        ),
    ];
  }

  String _shortError(Object e) {    final text = e.toString();
    return text.length <= 60 ? text : text.substring(0, 60);
  }

  void _fitMap() {
    final route = _route;
    final pos = _myPos;
    if (route == null || pos == null) return;
    final points = [pos, route.start, ...route.points, route.end];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: points,
            padding: const EdgeInsets.all(48),
          ),
        );
      } catch (_) {}
    });
  }

  /// Overpass servers give no content-length, so real percentages are
  /// impossible — the bar approximates the expected pace of this stage and
  /// saturates at 90% until the real result arrives.
  double _estimatedProgress(double expectedSeconds) {
    if (expectedSeconds <= 0 || !_sw.isRunning) return 0;
    final p = _sw.elapsed.inMilliseconds / (expectedSeconds * 1000);
    return (p * 0.9).clamp(0.02, 0.9);
  }

  void _retryPermission() {
    _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: BrandTitle()),
      body: switch (_stage) {
        _Stage.permission => _CenterMessage(
            title: t.t('permissionNeeded'),
            actionLabel: t.t('grant'),
            onAction: _retryPermission,
          ),
        _Stage.locating ||
        _Stage.downloading ||
        _Stage.computing =>
          _Loading(
            text: switch (_stage) {
              _Stage.locating => t.t('locating'),
              _Stage.downloading => t.t('downloading'),
              _ => t.t('computing'),
            },
            progress: switch (_stage) {
              _Stage.locating => _estimatedProgress(8),
              _Stage.downloading => _estimatedProgress(60),
              _ => _estimatedProgress(4),
            },
            seconds: _elapsedSec,
            slowHint: _elapsedSec >= 12 && _stage != _Stage.locating
                ? t.t('serverBusy')
                : null,
          ),
        _Stage.error => _CenterMessage(
            title: t.t(_errorKey),
            subtitle: _diag.isEmpty ? null : _diag,
            actionLabel: t.t('generate'),
            onAction: () => _fetchRoute(regenerate: _graph != null || _myPos != null),
          ),
        _Stage.ready => _buildReady(),
      },
    );
  }

  Widget _buildReady() {
    final route = _route!;
    final pos = _myPos!;
    final approxMin = (route.lengthKm * 9).round();

    return Column(
      children: [
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: route.start,
              initialZoom: 14,
              minZoom: 12,
              maxZoom: 17,
              keepAlive: true,
            ),
            children: [
              TileLayer(
                urlTemplate: '${TilePrefetcher.instance.tileServer}/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.sass.realroute',
                tileProvider: TilePrefetcher.instance.tileProvider,
              ),
              if (_territoryPolys.isNotEmpty)
                PolygonLayer(polygons: _territoryPolys),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: route.points,
                    color: AppColors.accent,
                    strokeWidth: 5,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: pos,
                    child: _YouDot(),
                  ),
                ],
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.t('routeReady', {
                              'n': route.lengthKm.toStringAsFixed(1),
                              'm': approxMin.toString(),
                            }),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _offlineTiles > 0
                                ? t.t('offlineRouteReady',
                                    {'n': '$_offlineTiles'})
                                : t.t('routeHint'),
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12.5,
                            ),
                          ),
                          if (Territory.instance.count > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              t.t('territoryCount',
                                  {'n': '${Territory.instance.count}'}),
                              style: const TextStyle(
                                color: AppColors.teal,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: t.t('regenerate'),
                      icon: const Icon(Icons.casino_outlined),
                      color: AppColors.accent2,
                      onPressed: () => _fetchRoute(regenerate: true),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: const Color(0xFF1B0F05),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.directions_run),
                  label: Text(
                    t.t('startRun'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => RunMapScreen(
                          l10n: t,
                          routeResult: route,
                          start: pos,
                          mode: widget.mode,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CenterMessage extends StatelessWidget {
  const _CenterMessage({
    required this.title,
    required this.actionLabel,
    required this.onAction,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_off_outlined,
                size: 44, color: AppColors.muted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.4),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 10),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.muted, fontSize: 11, height: 1.3),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.accent),
                foregroundColor: AppColors.accent,
              ),
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({
    required this.text,
    this.progress = 0,
    this.seconds = 0,
    this.slowHint,
  });

  final String text;
  final double progress;
  final int seconds;
  final String? slowHint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              color: AppColors.accent,
              backgroundColor: AppColors.surface2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            seconds > 0 ? '$text · ${seconds}s' : text,
            style: const TextStyle(color: AppColors.muted),
          ),
          if (slowHint != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                slowHint!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _YouDot extends StatelessWidget {
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
