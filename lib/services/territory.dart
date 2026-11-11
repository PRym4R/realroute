import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../core/tiles.dart';

/// Every street cell the player has ever run through — the "RPG" part.
///
/// Cells are kept as `z/x/y` keys in `territory.json` next to the run history.
/// A set is enough: conquest is monotonic, nothing is ever un-conquered.
class Territory extends ChangeNotifier {
  Territory._();

  static final Territory instance = Territory._();

  static const String fileName = 'territory.json';

  final Set<String> _cells = <String>{};
  File? _file;
  bool _loaded = false;

  /// How many distinct streets are on the map.
  int get count => _cells.length;

  bool get isEmpty => _cells.isEmpty;

  bool contains(TileCell cell) => _cells.contains(cell.key);

  /// All cells as objects; parsing is lazy because most callers only need
  /// a subset (the ones near the current view).
  Iterable<TileCell> get cells =>
      _cells.map(TileCell.parse).whereType<TileCell>();

  /// Cells near [center] within about [radiusM] — what the map draws.
  List<TileCell> near(LatLng center, {double radiusM = 2500}) {
    final result = <TileCell>[];
    final cosLat =
        math.cos(center.latitude * math.pi / 180).abs().clamp(0.05, 1.0);
    for (final cell in cells) {
      final c = cellCenter(cell);
      final dLat = (c.latitude - center.latitude).abs() * 111320;
      if (dLat > radiusM) continue;
      final dLon = (c.longitude - center.longitude).abs() * 111320 * cosLat;
      if (dLon > radiusM) continue;
      result.add(cell);
    }
    return result;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _resolveFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final raw = decoded['cells'];
      if (raw is! List) return;
      _cells
        ..clear()
        ..addAll(raw.whereType<String>().where((k) => TileCell.parse(k) != null));
      notifyListeners();
    } catch (_) {
      // A corrupt territory file must never block the app from starting.
    }
  }

  /// Adds a finished run's track. Returns the keys that were new — that is
  /// what the result dialog brags about.
  Future<Set<String>> addTrack(List<LatLng> track) async {
    final fresh = <String>{};
    for (final cell in cellsForTrack(track)) {
      if (_cells.add(cell.key)) fresh.add(cell.key);
    }
    if (fresh.isNotEmpty) {
      notifyListeners();
      await _persist();
    }
    return fresh;
  }

  Future<void> clear() async {
    _cells.clear();
    notifyListeners();
    await _persist();
  }

  Future<File> _resolveFile() async {
    final existing = _file;
    if (existing != null) return existing;
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    _file = file;
    return file;
  }

  Future<void> _persist() async {
    try {
      final file = await _resolveFile();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(<String, Object?>{'cells': _cells.toList()..sort()}),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    } catch (_) {
      // Best effort: losing a write must not break the finish screen.
    }
  }
}
