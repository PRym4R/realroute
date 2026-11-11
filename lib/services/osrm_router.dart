import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/metrics.dart';
import 'pedestrian_router.dart' show RouteResult, RouterError;
import 'valhalla_router.dart' show decodePolyline;

class OsrmRouter {
  static const String baseUrl =
      'https://routing.openstreetmap.de/routed-foot';
  static const Duration timeout = Duration(seconds: 20);

  final http.Client _client = http.Client();
  final math.Random _random = math.Random();

  Future<RouteResult> generate({
    required LatLng start,
    required double targetKm,
  }) async {
    if (targetKm <= 0) throw const RouterError('noData');

    final targetM = targetKm * 1000;
    final baseBearing = _random.nextDouble() * 360;
    var straightM = targetM * 0.85;

    ({double lengthM, List<LatLng> shape})? best;
    var bestDiff = double.infinity;

    for (var attempt = 0; attempt < 4; attempt++) {
      final bearing = (baseBearing + attempt * 97) % 360;
      final dest = offsetByMeters(start, bearing, straightM);
      final route = await _route(start, dest);
      if (route == null) continue;
      final diff = (route.lengthM - targetM).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = route;
      }
      if (route.lengthM >= targetM * 0.8 && route.lengthM <= targetM * 1.25) {
        break;
      }
      final perStraight = route.lengthM / straightM;
      if (perStraight > 0.3 && perStraight < 3) {
        straightM = (targetM / perStraight).clamp(targetM * 0.25, targetM * 2.5);
      }
    }

    if (best == null) throw const RouterError('noData');
    return RouteResult(
      best.shape,
      best.lengthM,
      best.shape.first,
      best.shape.last,
    );
  }

  Future<({double lengthM, List<LatLng> shape})?> _route(
    LatLng from,
    LatLng to,
  ) async {
    final uri = Uri.parse(
      '$baseUrl/route/v1/foot/'
      '${from.longitude},${from.latitude};'
      '${to.longitude},${to.latitude}'
      '?geometries=polyline&overview=full&steps=false',
    );
    final response = await _client.get(
      uri,
      headers: const {'User-Agent': 'RealRouteRPG/1.0 (route requests)'},
    ).timeout(timeout);

    if (response.statusCode != 200) return null;
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, dynamic> || json['code'] != 'Ok') return null;
    final routes = json['routes'];
    if (routes is! List || routes.isEmpty) return null;
    final route = routes.first;
    if (route is! Map) return null;
    final distance = route['distance'];
    final geometry = route['geometry'];
    if (distance is! num || geometry is! String) return null;
    final shape = decodePolyline(geometry, precision: 5);
    if (shape.length < 2) return null;
    return (lengthM: distance.toDouble(), shape: shape);
  }

  void dispose() {
    _client.close();
  }
}
