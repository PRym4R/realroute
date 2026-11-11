import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:realroute/core/metrics.dart';

void main() {
  group('haversineM', () {
    test('one degree of longitude at the equator is ~111.2 km', () {
      final d = haversineM(const LatLng(0, 0), const LatLng(0, 1));
      expect(d, closeTo(111195, 50));
    });

    test('is symmetric', () {
      const a = LatLng(55.751244, 37.618423);
      const b = LatLng(55.760000, 37.640000);
      expect(haversineM(a, b), closeTo(haversineM(b, a), 0.001));
    });

    test('is zero for the same point', () {
      const p = LatLng(59.9386, 30.3141);
      expect(haversineM(p, p), 0);
    });
  });

  group('offsetByMeters', () {
    test('lands the requested distance away, whatever the bearing', () {
      const start = LatLng(55.75, 37.61);
      for (final bearing in [0.0, 45.0, 90.0, 180.0, 270.0, 359.0]) {
        final end = offsetByMeters(start, bearing, 1000);
        expect(
          haversineM(start, end),
          closeTo(1000, 1.5),
          reason: 'bearing $bearing',
        );
      }
    });

    test('bearing 90 goes east, bearing 0 goes north', () {
      const start = LatLng(0, 0);
      final east = offsetByMeters(start, 90, 10000);
      final north = offsetByMeters(start, 0, 10000);
      expect(east.longitude, greaterThan(0));
      expect(east.latitude, closeTo(0, 1e-9));
      expect(north.latitude, greaterThan(0));
      expect(north.longitude, closeTo(0, 1e-9));
    });
  });

  group('formatting', () {
    test('fmtDurationSec', () {
      expect(fmtDurationSec(0), '0:00');
      expect(fmtDurationSec(9), '0:09');
      expect(fmtDurationSec(65), '1:05');
      expect(fmtDurationSec(600), '10:00');
      expect(fmtDurationSec(3661), '1:01:01');
    });

    test('fmtPace', () {
      expect(fmtPace(305), '5:05');
      expect(fmtPace(59), '0:59');
      expect(fmtPace(3600), '60:00');
    });

    test('fmtKm', () {
      expect(fmtKm(1), '1');
      expect(fmtKm(2.25), '2.3');
      expect(fmtKm(0.5), '0.5');
      expect(fmtKm(150), '150');
    });
  });
}
