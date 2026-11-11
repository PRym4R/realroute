import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/metrics.dart';
import 'pedestrian_router.dart' show RouteResult, RouterError;

class ValhallaRouter {
  static const String baseUrl = 'https://valhalla1.openstreetmap.de';
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
    final response = await _client
        .post(
          Uri.parse('$baseUrl/route'),
          headers: const {
            'Content-Type': 'application/json',
            'User-Agent': 'RealRouteRPG/1.0 (route requests)',
          },
          body: jsonEncode({
            'locations': [
              {'lat': from.latitude, 'lon': from.longitude},
              {'lat': to.latitude, 'lon': to.longitude},
            ],
            'costing': 'pedestrian',
            'units': 'kilometers',
          }),
        )
        .timeout(timeout);

    if (response.statusCode != 200) return null;
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, dynamic>) return null;
    final trip = json['trip'];
    if (trip is! Map) return null;
    final summary = trip['summary'];
    final legs = trip['legs'];
    if (summary is! Map || legs is! List || legs.isEmpty) return null;
    final length = summary['length'];
    if (length is! num) return null;

    final shape = <LatLng>[];
    for (final leg in legs.whereType<Map>()) {
      final encoded = leg['shape'];
      if (encoded is String) {
        shape.addAll(decodePolyline(encoded, precision: 6));
      }
    }
    if (shape.length < 2) return null;
    return (lengthM: length.toDouble() * 1000, shape: shape);
  }

  void dispose() {
    _client.close();
  }
}

List<LatLng> decodePolyline(String encoded, {int precision = 6}) {
  final scale = math.pow(10, precision).toDouble();
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;

  int nextValue() {
    var shift = 0;
    var result = 0;
    while (true) {
      final b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
      if (b < 0x20) break;
    }
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  while (index < encoded.length) {
    lat += nextValue();
    lng += nextValue();
    points.add(LatLng(lat / scale, lng / scale));
  }
  return points;
}

List<LatLng> decodePolyline6(String encoded) =>
    decodePolyline(encoded, precision: 6);
