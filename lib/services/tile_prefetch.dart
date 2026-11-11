import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../core/metrics.dart';

/// Wraps a client so that a request can never hang forever.
class _TimeoutClient extends http.BaseClient {
  _TimeoutClient(this._inner, this._timeout);

  final http.Client _inner;
  final Duration _timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request).timeout(_timeout);

  @override
  void close() => _inner.close();
}

class TilePrefetcher extends ChangeNotifier {
  TilePrefetcher._();

  static final TilePrefetcher instance = TilePrefetcher._();

  static const String defaultTileServer = 'https://tile.openstreetmap.org';
  static const Duration tileFreshness = Duration(days: 60);
  static const int maxZoomForStandard = 14;
  static const int maxZoomForDetailed = 15;

  String tileServer = defaultTileServer;

  void setTileServer(String url) {
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    tileServer = trimmed.isEmpty ? defaultTileServer : trimmed;
    notifyListeners();
  }

  final http.Client _client = http.Client();

  bool _running = false;
  bool _corridorRunning = false;
  bool _paused = false;
  bool _cancelRequested = false;
  int _done = 0;
  int _successful = 0;
  int _total = 0;
  int _failed = 0;
  String? _error;

  bool get running => _running;
  bool get corridorRunning => _corridorRunning;
  bool get paused => _paused;
  int get done => _done;
  int get successful => _successful;
  int get total => _total;
  int get failed => _failed;
  String? get error => _error;

  NetworkTileProvider _tileProvider = NetworkTileProvider(
    headers: {'User-Agent': 'RealRouteRPG/1.0'},
    httpClient: _newTileClient(),
    silenceExceptions: true,
  );

  NetworkTileProvider get tileProvider => _tileProvider;

  /// Offline, a tile request used to sit until the OS TCP timeout — minutes
  /// per tile, with the map blank the whole time. A 5 s connect and 8 s total
  /// budget turns that into a transparent tile quickly.
  static http.Client _newTileClient() {
    final io = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..idleTimeout = const Duration(seconds: 10);
    return _TimeoutClient(IOClient(io), const Duration(seconds: 8));
  }

  static const int prefetchMinZoom = 12;

  Future<void> initCache() async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}'
      '${Platform.pathSeparator}rtl_cache',
    );
    await dir.create(recursive: true);
    final caching = BuiltInMapCachingProvider.getOrCreateInstance(
      cacheDirectory: dir.path,
      maxCacheSize: 2_000_000_000,
      overrideFreshAge: tileFreshness,
    );
    _tileProvider = NetworkTileProvider(
      headers: {'User-Agent': 'RealRouteRPG/1.0'},
      httpClient: _newTileClient(),
      silenceExceptions: true,
      cachingProvider: caching,
    );
    _cacheDir = dir;
    notifyListeners();
  }

  Directory? _cacheDir;

  /// Approximate tile count for a circular region, zooms [12..maxZoom].
  static int estimateTileCount(double lat, double radiusKm, int maxZoom) {
    final latRad = lat * math.pi / 180;
    final cos = math.cos(latRad).abs().clamp(0.05, 1.0);
    var count = 0.0;
    final dLat = radiusKm * 1000 / 111320.0;
    for (var z = prefetchMinZoom; z <= maxZoom; z++) {
      final n = 1 << z;
      final dLonDeg = radiusKm * 1000 / (111320.0 * cos);
      final spanX = (2 * dLonDeg / 360 * n).clamp(1.0, 4.0 * n);
      final y1 = _mercatorY(lat + dLat, n);
      final y0 = _mercatorY(lat - dLat, n);
      final spanY = math.max(1.0, (y1 - y0).abs().ceilToDouble());
      count += spanX * spanY;
    }
    return count.ceil();
  }

  static double _mercatorY(double latDeg, int n) {
    final r = latDeg.clamp(-85.05112878, 85.05112878) * math.pi / 180;
    return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) * n / 2;
  }

  (int, int, int, int)? _tileRange(double lat, double lon, int z, double radiusM) {
    final n = 1 << z;
    final latRad = lat * math.pi / 180;
    final cos = math.cos(latRad).abs().clamp(0.05, 1.0);
    final dLat = radiusM / 111320.0;
    final dLon = radiusM / (111320.0 * cos) * (180 / math.pi);
    final latMin = (lat - dLat).clamp(-85.05112878, 85.05112878);
    final latMax = (lat + dLat).clamp(-85.05112878, 85.05112878);
    final lonMin = lon - dLon;
    final lonMax = lon + dLon;
    int xFor(double lonDeg) =>
        ((lonDeg + 180) / 360 * n).floor().clamp(0, n - 1);
    final x0 = xFor(lonMin), x1 = xFor(lonMax);
    final y0 = _mercatorY(latMax, n).floor().clamp(0, n - 1);
    final y1 = _mercatorY(latMin, n).floor().clamp(0, n - 1);
    return (x0, x1, y0, y1);
  }

  Future<void> start({
    required LatLng center,
    required double radiusKm,
    required int maxZoom,
  }) async {
    if (_running || _corridorRunning) return;
    if (_cacheDir == null) await initCache();

    _running = true;
    _paused = false;
    _cancelRequested = false;
    _done = 0;
    _successful = 0;
    _failed = 0;
    _error = null;
    notifyListeners();

    try {
      final queue = <({int z, int x, int y})>[];
      for (var z = prefetchMinZoom; z <= maxZoom; z++) {
        final range = _tileRange(
          center.latitude,
          center.longitude,
          z,
          radiusKm * 1000,
        );
        if (range == null) continue;
        final (x0, x1, y0, y1) = range;
        for (var y = y0; y <= y1; y++) {
          for (var x = x0; x <= x1; x++) {
            queue.add((z: z, x: x, y: y));
          }
        }
      }
      _total = queue.length;
      notifyListeners();

      var next = 0;
      Future<void> worker() async {
        while (!_cancelRequested) {
          while (_paused && !_cancelRequested) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          if (_cancelRequested) return;
          final i = next;
          next = i + 1;
          if (i >= queue.length) return;

          final t = queue[i];
          try {
            final added = await _downloadTile(t.z, t.x, t.y);
            if (added) _successful++;
          } catch (_) {
            _failed++;
          }
          _done++;
          notifyListeners();
        }
      }

      const concurrency = 3;
      await Future.wait(
        List.generate(math.min(concurrency, _total), (_) => worker()),
      );

      if (!_cancelRequested && _failed > 0 && _successful == 0) {
        _error = 'network';
      }
      if (_cancelRequested) _error = null;
    } catch (e) {
      _error = 'network';
    } finally {
      _running = false;
      _paused = false;
      notifyListeners();
    }
  }

  /// Caches the tiles the runner will actually look at: the route corridor
  /// on the working zooms of the run screen. Silent and non-blocking.
  Future<int> prefetchCorridor(
    List<LatLng> points, {
    int minZoom = 13,
    int maxZoom = 17,
    double bufferM = 350,
  }) async {
    if (_corridorRunning || _running) return 0;
    if (points.length < 2) return 0;
    if (_cacheDir == null) await initCache();
    _corridorRunning = true;

    try {
      final keys = <String>{};
      for (var i = 1; i < points.length; i++) {
        final a = points[i - 1];
        final b = points[i];
        final segmentM = haversineM(a, b);
        final steps = math.max(1, (segmentM / 60).ceil());
        for (var s = 0; s <= steps; s++) {
          final t = s / steps;
          final lat = a.latitude + (b.latitude - a.latitude) * t;
          final lon = a.longitude + (b.longitude - a.longitude) * t;
          for (var z = minZoom; z <= maxZoom; z++) {
            final range = _tileRange(lat, lon, z, bufferM);
            if (range == null) continue;
            final (x0, x1, y0, y1) = range;
            for (var y = y0; y <= y1; y++) {
              for (var x = x0; x <= x1; x++) {
                keys.add('$z/$x/$y');
              }
            }
          }
        }
      }

      final queue = keys.toList();
      var next = 0;

      Future<void> worker() async {
        while (true) {
          final i = next++;
          if (i >= queue.length) return;
          final parts = queue[i].split('/');
          try {
            await _downloadTile(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
          } catch (_) {}
        }
      }

      await Future.wait(
        List.generate(math.min(3, queue.length), (_) => worker()),
      );
      return queue.length;
    } finally {
      _corridorRunning = false;
    }
  }

  Future<bool> _downloadTile(int z, int x, int y) async {
    final caching = _tileProvider.cachingProvider;
    if (caching == null) throw StateError('cache not initialised');

    final url = '$tileServer/$z/$x/$y.png';
    final existing = await caching.getTile(url);
    if (existing != null && !existing.metadata.isStale) return false;

    final response = await _client
        .get(
          Uri.parse(url),
          headers: {'User-Agent': 'RealRouteRPG/1.0 (offline prefetch)'},
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw Exception('tile HTTP ${response.statusCode}');
    }

    await caching.putTile(
      url: url,
      metadata: CachedMapTileMetadata(
        staleAt: DateTime.timestamp().add(tileFreshness),
        lastModified: null,
        etag: null,
      ),
      bytes: response.bodyBytes,
    );
    return true;
  }

  void pause() {
    if (!_running) return;
    _paused = true;
    notifyListeners();
  }

  void resume() {
    if (!_running) return;
    _paused = false;
    notifyListeners();
  }

  void cancel() {
    if (!_running) return;
    _cancelRequested = true;
    _paused = false;
    notifyListeners();
  }

  Future<int> cacheSizeBytes() async {
    final dir = _cacheDir;
    if (dir == null) return 0;
    final fmCache = Directory('${dir.path}${Platform.pathSeparator}fm_cache');
    if (!await fmCache.exists()) return 0;
    var total = 0;
    await for (final entity in fmCache.list()) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<void> clearCache() async {
    if (_running) return;
    final dir = _cacheDir;
    if (dir == null) return;
    final fmCache = Directory('${dir.path}${Platform.pathSeparator}fm_cache');
    if (await fmCache.exists()) {
      await for (final entity in fmCache.list()) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

String fmtCacheSizeBytes(double mb) {
  final m = mb;
  if (m >= 1024) return '${(m / 1024).toStringAsFixed(2)} GB';
  if (m < 1) return '<1 MB';
  return '${m.toStringAsFixed(m < 10 ? 1 : 0)} MB';
}
