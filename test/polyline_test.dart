import 'package:flutter_test/flutter_test.dart';
import 'package:realroute/services/valhalla_router.dart';

void main() {
  group('decodePolyline', () {
    // The canonical example from Google's polyline algorithm docs.
    const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

    test('decodes the reference example at precision 5', () {
      final points = decodePolyline(encoded, precision: 5);
      expect(points.length, 3);
      expect(points[0].latitude, closeTo(38.5, 1e-5));
      expect(points[0].longitude, closeTo(-120.2, 1e-5));
      expect(points[1].latitude, closeTo(40.7, 1e-5));
      expect(points[1].longitude, closeTo(-120.95, 1e-5));
      expect(points[2].latitude, closeTo(43.252, 1e-5));
      expect(points[2].longitude, closeTo(-126.453, 1e-5));
    });

    test('returns nothing for an empty string', () {
      expect(decodePolyline(''), isEmpty);
    });

    test('decodePolyline6 is the same as precision 6', () {
      final a = decodePolyline6(encoded);
      final b = decodePolyline(encoded, precision: 6);
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].latitude, closeTo(b[i].latitude, 1e-9));
        expect(a[i].longitude, closeTo(b[i].longitude, 1e-9));
      }
    });
  });
}
