import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'metrics.dart';

/// Zoom level of the territory grid. 16 is ~350 m per cell in mid-latitudes:
/// coarse enough to fill in visibly after a few runs, fine enough that two
/// routes through the same block count as the same street.
const int territoryZoom = 16;

/// A cell of the territory grid (a slippy-map tile).
class TileCell {
  const TileCell(this.z, this.x, this.y);

  final int z;
  final int x;
  final int y;

  String get key => '$z/$x/$y';

  /// Returns null for anything that is not a `z/x/y` triple.
  static TileCell? parse(String key) {
    final parts = key.split('/');
    if (parts.length != 3) return null;
    final z = int.tryParse(parts[0]);
    final x = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (z == null || x == null || y == null || z < 0 || z > 22) return null;
    final n = 1 << z;
    if (x < 0 || y < 0 || x >= n || y >= n) return null;
    return TileCell(z, x, y);
  }

  @override
  bool operator ==(Object other) =>
      other is TileCell && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => key;
}

/// The cell that contains [point].
TileCell cellFor(LatLng point, {int zoom = territoryZoom}) {
  final n = 1 << zoom;
  final x = ((point.longitude + 180) / 360 * n).floor().clamp(0, n - 1);
  final latRad = point.latitude * math.pi / 180;
  final mercator =
      math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi;
  final y = ((1 - mercator) / 2 * n).floor().clamp(0, n - 1);
  return TileCell(zoom, x, y);
}

/// The four corners of the cell, in drawing order (NW, NE, SE, SW).
List<LatLng> cellCorners(TileCell cell) {
  final n = 1 << cell.z;
  LatLng at(int x, int y) {
    final lon = x / n * 360 - 180;
    // dart:math has no sinh(); atanh(sin) form is the usual substitute.
    final t = math.pi * (1 - 2 * y / n);
    final sinh = (math.exp(t) - math.exp(-t)) / 2;
    final lat = math.atan(sinh) * 180 / math.pi;
    return LatLng(lat, lon);
  }

  return [
    at(cell.x, cell.y),
    at(cell.x + 1, cell.y),
    at(cell.x + 1, cell.y + 1),
    at(cell.x, cell.y + 1),
  ];
}

LatLng cellCenter(TileCell cell) {
  final corners = cellCorners(cell);
  return LatLng(
    (corners[0].latitude + corners[2].latitude) / 2,
    (corners[0].longitude + corners[2].longitude) / 2,
  );
}

/// Every cell the track passes through.
///
/// Consecutive fixes can be 30-300 m apart, so a segment is walked in ~[sampleM]
/// steps instead of only marking its endpoints — otherwise a long straight run
/// would mark two cells and leave a hole in the middle.
Set<TileCell> cellsForTrack(
  List<LatLng> points, {
  int zoom = territoryZoom,
  double sampleM = 40,
}) {
  final cells = <TileCell>{};
  if (points.isEmpty) return cells;
  cells.add(cellFor(points.first, zoom: zoom));
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final distance = haversineM(a, b);
    final steps = math.max(1, (distance / sampleM).ceil());
    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      cells.add(cellFor(
        LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        ),
        zoom: zoom,
      ));
    }
  }
  return cells;
}
