import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:realroute/core/tiles.dart';

void main() {
  group('cellFor', () {
    test('stays inside the grid', () {
      for (final zoom in [10, 14, 16, 18]) {
        final n = 1 << zoom;
        for (final p in const [
          LatLng(0, 0),
          LatLng(55.751244, 37.618423),
          LatLng(-33.8688, 151.2093),
          LatLng(60.0, -170.0),
        ]) {
          final cell = cellFor(p, zoom: zoom);
          expect(cell.z, zoom);
          expect(cell.x, inInclusiveRange(0, n - 1));
          expect(cell.y, inInclusiveRange(0, n - 1));
        }
      }
    });

    test('the point lies inside its own cell', () {
      const p = LatLng(55.751244, 37.618423);
      final corners = cellCorners(cellFor(p));
      final north = corners[0].latitude;
      final south = corners[2].latitude;
      final west = corners[0].longitude;
      final east = corners[2].longitude;
      expect(p.latitude, inInclusiveRange(south, north));
      expect(p.longitude, inInclusiveRange(west, east));
    });

    test('corners go NW, NE, SE, SW', () {
      final c = cellCorners(cellFor(const LatLng(10, 10)));
      expect(c[0].latitude, greaterThan(c[2].latitude)); // NW above SE
      expect(c[0].longitude, lessThan(c[1].longitude)); // NW left of NE
      expect(c[1].latitude, closeTo(c[0].latitude, 1e-9));
      expect(c[3].longitude, closeTo(c[0].longitude, 1e-9));
    });
  });

  group('TileCell.parse', () {
    test('round trips through its key', () {
      const cell = TileCell(16, 12345, 6789);
      expect(TileCell.parse(cell.key), cell);
    });

    test('rejects junk and out-of-range cells', () {
      expect(TileCell.parse(''), isNull);
      expect(TileCell.parse('16/1'), isNull);
      expect(TileCell.parse('a/b/c'), isNull);
      expect(TileCell.parse('3/8/0'), isNull); // 2^3 = 8, so x must be < 8
      expect(TileCell.parse('16/-1/5'), isNull);
    });
  });

  group('cellsForTrack', () {
    test('marks a contiguous strip for a straight 1 km run', () {
      final track = <LatLng>[
        for (var i = 0; i <= 10; i++) LatLng(55.75 + i * 0.0009, 37.61),
      ];
      final cells = cellsForTrack(track);
      expect(cells.length, greaterThan(1));
      // every cell must be the same zoom
      expect(cells.every((c) => c.z == territoryZoom), isTrue);
    });

    test('samples long segments instead of only their endpoints', () {
      final sparse = <LatLng>[
        const LatLng(55.75, 37.61),
        const LatLng(55.79, 37.61), // ~4.4 km apart
      ];
      final cells = cellsForTrack(sparse);
      expect(cells.length, greaterThan(5));
    });

    test('an empty track marks nothing', () {
      expect(cellsForTrack(const []), isEmpty);
    });
  });
}
