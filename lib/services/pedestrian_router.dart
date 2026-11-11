import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:latlong2/latlong.dart';

import '../core/metrics.dart';

class RouterError implements Exception {
  const RouterError(this.key);

  final String key;
}

class PedGraph {
  PedGraph(this.nodeCoords, this.edges);

  final Map<int, LatLng> nodeCoords;
  final Map<int, Map<int, double>> edges;
}

class RouteResult {
  RouteResult(this.points, this.lengthM, this.start, this.end);

  final List<LatLng> points;
  final double lengthM;
  final LatLng start;
  final LatLng end;

  double get lengthKm => lengthM / 1000;
}

class _HeapItem {
  _HeapItem(this.priority, this.node);

  final double priority;
  final int node;
}

class _MinHeap {
  final List<_HeapItem> _items = <_HeapItem>[];

  bool get isEmpty => _items.isEmpty;

  bool get isNotEmpty => _items.isNotEmpty;

  void push(double priority, int node) {
    _items.add(_HeapItem(priority, node));
    var i = _items.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_items[parent].priority <= _items[i].priority) break;
      final tmp = _items[parent];
      _items[parent] = _items[i];
      _items[i] = tmp;
      i = parent;
    }
  }

  _HeapItem pop() {
    final top = _items.first;
    final last = _items.removeLast();
    if (_items.isEmpty) return top;
    _items[0] = last;
    var i = 0;
    for (;;) {
      final l = i * 2 + 1;
      final r = l + 1;
      var smallest = i;
      if (l < _items.length && _items[l].priority < _items[smallest].priority) smallest = l;
      if (r < _items.length && _items[r].priority < _items[smallest].priority) smallest = r;
      if (smallest == i) break;
      final tmp = _items[smallest];
      _items[smallest] = _items[i];
      _items[i] = tmp;
      i = smallest;
    }
    return top;
  }
}

const Set<String> _pedestrianHighways = {
  'footway',
  'path',
  'pedestrian',
  'steps',
  'track',
  'living_street',
  'service',
  'residential',
  'unclassified',
  'tertiary',
  'tertiary_link',
  'secondary',
  'secondary_link',
  'primary',
};

const List<String> _overpassEndpoints = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
];

const Duration _overpassTimeout = Duration(seconds: 60);
const Duration _graphCacheTtl = Duration(hours: 24);
const double _graphCacheToleranceM = 400;

class GraphSession {
  static PedGraph? _graph;
  static double? _lat;
  static double? _lng;
  static int? _radiusM;
  static DateTime? _at;

  static void keep(PedGraph graph, double lat, double lng, int radiusM) {
    _graph = graph;
    _lat = lat;
    _lng = lng;
    _radiusM = radiusM;
    _at = DateTime.now();
  }

  static PedGraph? take(double lat, double lng, int radiusM) {
    final g = _graph;
    final at = _at;
    if (g == null || at == null) return null;
    if (DateTime.now().difference(at) > _graphCacheTtl) return null;
    if (radiusM > (_radiusM ?? 0)) return null;
    if (haversineM(
          LatLng(_lat!, _lng!),
          LatLng(lat, lng),
        ) >
        _graphCacheToleranceM) {
      return null;
    }
    return g;
  }
}

class PedestrianRouter {
  final http.Client _client = http.Client();

  String _query(double lat, double lng, int radiusM) {
    final highways = _pedestrianHighways.join('|');
    return '[out:json][timeout:45];'
        'way["highway"~"^($highways)\$"](around:$radiusM,$lat,$lng);'
        'out geom;';
  }

  Future<PedGraph> fetchGraph({
    required double lat,
    required double lng,
    required int radiusM,
  }) async {
    final cached = GraphSession.take(lat, lng, radiusM);
    if (cached != null) return cached;

    final disk = await GraphDiskCache.load(lat, lng, radiusM);
    if (disk != null) {
      GraphSession.keep(disk, lat, lng, radiusM);
      return disk;
    }

    final body = 'data=${Uri.encodeQueryComponent(_query(lat, lng, radiusM))}';

    final completer = Completer<PedGraph>();
    var pending = _overpassEndpoints.length;
    RouterError? firstError;

    void failWith(RouterError err) {
      firstError ??= err;
      pending--;
      if (pending == 0 && !completer.isCompleted) {
        completer.completeError(firstError ?? const RouterError('network'));
      }
    }

    void succeed(PedGraph graph) {
      if (!completer.isCompleted) completer.complete(graph);
    }

    for (final endpoint in _overpassEndpoints) {
      () async {
        try {
          final response = await _client
              .post(
                Uri.parse(endpoint),
                headers: {
                  'Content-Type': 'application/x-www-form-urlencoded',
                  'User-Agent': 'RealRouteRPG/1.0 (route requests)',
                },
                body: body,
              )
              .timeout(_overpassTimeout);
          if (response.statusCode == 429 || response.statusCode >= 500) {
            throw Exception('Overpass HTTP ${response.statusCode}');
          }
          if (response.statusCode != 200) {
            throw const RouterError('network');
          }
          final json =
              jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          if (json['elements'] is! List) {
            throw const RouterError('network');
          }
          final graph = _buildGraph(json['elements'] as List);
          if (graph.nodeCoords.isEmpty || graph.edges.isEmpty) {
            throw const RouterError('noData');
          }
          try {
            await GraphDiskCache.save(
              lat: lat,
              lng: lng,
              radiusM: radiusM,
              elements: json['elements'] as List,
            );
          } catch (_) {}
          succeed(graph);
        } on RouterError catch (e) {
          failWith(e);
        } catch (_) {
          failWith(const RouterError('network'));
        }
      }();
    }

    final graph = await completer.future;
    GraphSession.keep(graph, lat, lng, radiusM);
    return graph;
  }

  static PedGraph _buildGraph(List elements) {
    final coords = <int, LatLng>{};
    final edges = <int, Map<int, double>>{};

    for (final raw in elements) {
      if (raw is! Map<String, dynamic>) continue;
      if (raw['type'] != 'way') continue;
      final nodes = raw['nodes'];
      final geometry = raw['geometry'];
      if (nodes is! List || geometry is! List) continue;

      final tags = raw['tags'];
      final highway = tags?['highway'] as String?;
      if (highway == null || !_pedestrianHighways.contains(highway)) continue;
      final foot = tags?['foot'] as String?;
      if (foot == 'no') continue;
      final access = tags?['access'] as String?;
      if (access == 'private' || access == 'no') continue;
      final motorroad = tags?['motorroad'] as String?;
      if (motorroad == 'yes') continue;

      final gNodes = nodes.whereType<int>().toList();
      final gGeom = geometry
          .whereType<Map>()
          .map((p) {
            final latP = p['lat'];
            final lonP = p['lon'];
            if (latP is! num || lonP is! num) return null;
            return LatLng(latP.toDouble(), lonP.toDouble());
          })
          .whereType<LatLng>()
          .toList();
      if (gGeom.length < 2) continue;

      for (var i = 0; i < gNodes.length && i < gGeom.length; i++) {
        coords[gNodes[i]] = gGeom[i];
      }
      for (var i = 0; i < gNodes.length - 1 && i < gGeom.length - 1; i++) {
        final a = gNodes[i];
        final b = gNodes[i + 1];
        if (!coords.containsKey(a) || !coords.containsKey(b)) continue;
        final w = haversineM(coords[a]!, coords[b]!);
        edges.putIfAbsent(a, () => <int, double>{})[b] = w;
        edges.putIfAbsent(b, () => <int, double>{})[a] = w;
      }
    }

    final used = coords.keys.where((id) => edges.containsKey(id)).toSet();
    final cleanCoords = {for (final id in used) id: coords[id]!};
    final cleanEdges = <int, Map<int, double>>{};
    edges.forEach((a, to) {
      final kept = {for (final b in to.keys.where(used.contains)) b: to[b]!};
      if (kept.isNotEmpty) cleanEdges[a] = kept;
    });
    return PedGraph(cleanCoords, cleanEdges);
  }

  LatLng snapToNearest(PedGraph graph, LatLng point) {
    var best = -1;
    var bestDist = double.infinity;
    graph.nodeCoords.forEach((id, coord) {
      final d = haversineM(point, coord);
      if (d < bestDist) {
        bestDist = d;
        best = id;
      }
    });
    if (best < 0) throw const RouterError('noData');
    return graph.nodeCoords[best]!;
  }

  ({int node, Map<int, int> parents, Map<int, double> dist}) _dijkstra(
    PedGraph graph,
    int startNode,
  ) {
    final dist = <int, double>{};
    final parents = <int, int>{};
    final done = <int>{};
    final heap = _MinHeap();

    dist[startNode] = 0;
    heap.push(0, startNode);

    while (heap.isNotEmpty) {
      final item = heap.pop();
      if (done.contains(item.node)) continue;
      done.add(item.node);
      final to = graph.edges[item.node];
      if (to == null) continue;
      for (final entry in to.entries) {
        final nd = dist[item.node]! + entry.value;
        if (nd < (dist[entry.key] ?? double.infinity)) {
          dist[entry.key] = nd;
          parents[entry.key] = item.node;
          heap.push(nd, entry.key);
        }
      }
    }
    return (node: startNode, parents: parents, dist: dist);
  }

  RouteResult pickRoute({
    required PedGraph graph,
    required LatLng start,
    required double targetKm,
  }) {
    var startId = -1;
    var bestDist = double.infinity;
    graph.nodeCoords.forEach((id, coord) {
      final d = haversineM(start, coord);
      if (d < bestDist) {
        bestDist = d;
        startId = id;
      }
    });
    if (startId < 0) throw const RouterError('noData');

    final targetM = targetKm * 1000;
    final dij = _dijkstra(graph, startId);
    final dist = dij.dist;

    final reached = <({int id, double pathM, double straightM})>[];
    graph.nodeCoords.forEach((id, coord) {
      final pathM = dist[id];
      if (pathM == null) return;
      final straightM = haversineM(start, coord);
      reached.add((id: id, pathM: pathM, straightM: straightM));
    });

    final minStraight = math.min(250.0, targetM * 0.8);
    final valid = reached.where((c) => c.straightM >= minStraight).toList();
    if (valid.isEmpty) throw const RouterError('noData');

    ({int id, double pathM, double straightM})? chosen;
    var seed = DateTime.now().microsecondsSinceEpoch;
    int nextRandom(int n) {
      seed = (seed * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF;
      return (seed >>> 33) % n;
    }

    final candidates = valid
        .where((c) => c.pathM >= targetM * 0.55 && c.pathM <= targetM * 2.0)
        .toList();
    if (candidates.isEmpty) throw const RouterError('noData');

    candidates.sort((a, b) => (a.pathM - targetM)
        .abs()
        .compareTo((b.pathM - targetM).abs()));
    final closestCandidates = candidates
        .where((c) => (c.pathM - targetM).abs() <= targetM * 0.3)
        .toList();
    chosen = closestCandidates.isEmpty
        ? candidates.first
        : closestCandidates[nextRandom(closestCandidates.length)];

    final path = <int>[chosen.id];
    var cursor = chosen.id;
    var guard = 0;
    while (cursor != startId && guard < 500000) {
      cursor = dij.parents[cursor]!;
      path.add(cursor);
      guard++;
    }
    final points = <LatLng>[for (final id in path.reversed) graph.nodeCoords[id]!];

    return RouteResult(
      points,
      chosen.pathM,
      points.first,
      points.last,
    );
  }

  void dispose() {
    _client.close();
  }
}

class GraphDiskCache {
  static File? _cacheFile;

  static Future<File> _file() async {
    final f = _cacheFile;
    if (f != null) return f;
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}'
      '${Platform.pathSeparator}rtl_graph',
    );
    await dir.create(recursive: true);
    return _cacheFile = File('${dir.path}${Platform.pathSeparator}graph.json.gz');
  }

  static Future<void> save({
    required double lat,
    required double lng,
    required int radiusM,
    required List elements,
  }) async {
    try {
      final payload = jsonEncode(<String, Object?>{
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'lat': lat,
        'lng': lng,
        'radiusM': radiusM,
        'elements': elements,
      });
      final gz = gzip.encode(utf8.encode(payload));
      final f = await _file();
      await f.writeAsBytes(gz, flush: true);
    } catch (_) {}
  }

  static Future<PedGraph?> load(double lat, double lng, int radiusM) async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final bytes = await f.readAsBytes();
      final payload = jsonDecode(utf8.decode(gzip.decode(bytes)));
      if (payload is! Map<String, dynamic>) return null;

      final savedAt = payload['savedAt'];
      final sLat = payload['lat'];
      final sLng = payload['lng'];
      final sRadius = payload['radiusM'];
      if (savedAt is! int || sLat is! num || sLng is! num || sRadius is! num) {
        return null;
      }
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(savedAt),
      );
      if (age > _graphCacheTtl) return null;
      if (radiusM > sRadius) return null;
      if (haversineM(
            LatLng(sLat.toDouble(), sLng.toDouble()),
            LatLng(lat, lng),
          ) >
          _graphCacheToleranceM) {
        return null;
      }

      final elements = payload['elements'];
      if (elements is! List) return null;
      final graph = PedestrianRouter._buildGraph(elements);
      if (graph.nodeCoords.isEmpty || graph.edges.isEmpty) return null;
      return graph;
    } catch (_) {
      return null;
    }
  }
}
