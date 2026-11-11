import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

double haversineM(LatLng a, LatLng b) {
  const r = 6371000.0;
  final rad = math.pi / 180;
  final dLat = (b.latitude - a.latitude) * rad;
  final dLon = (b.longitude - a.longitude) * rad;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(a.latitude * rad) * math.cos(b.latitude * rad) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(h)));
}

String fmtKm(double km) {
  final value = km >= 100 ? km.round() : (km * 10).round() / 10;
  return value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
}

String fmtDurationSec(int totalSeconds) {
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String fmtPace(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

LatLng offsetByMeters(LatLng from, double bearingDeg, double distanceM) {
  const earthRadius = 6371000.0;
  final bearing = bearingDeg * math.pi / 180;
  final lat1 = from.latitude * math.pi / 180;
  final lon1 = from.longitude * math.pi / 180;
  final angular = distanceM / earthRadius;
  final lat2 = math.asin(
    math.sin(lat1) * math.cos(angular) +
        math.cos(lat1) * math.sin(angular) * math.cos(bearing),
  );
  final lon2 = lon1 +
      math.atan2(
        math.sin(bearing) * math.sin(angular) * math.cos(lat1),
        math.cos(angular) - math.sin(lat1) * math.sin(lat2),
      );
  return LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi);
}
