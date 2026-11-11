import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'run_tracker.dart' show RunMode;

/// One finished run, as it is kept on disk.
class RunRecord {
  const RunRecord({
    required this.id,
    required this.startedAt,
    required this.mode,
    required this.plannedM,
    required this.distanceM,
    required this.elapsedSec,
    required this.maxSpeedKmh,
    required this.steps,
  });

  final String id;
  final DateTime startedAt;
  final RunMode mode;
  final double plannedM;
  final double distanceM;
  final int elapsedSec;
  final double maxSpeedKmh;
  final int steps;

  double get avgSpeedKmh => elapsedSec <= 0 ? 0 : distanceM / elapsedSec * 3.6;

  double get avgPaceSecPerKm =>
      distanceM < 30 ? 0 : elapsedSec / (distanceM / 1000);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'mode': mode.name,
        'plannedM': plannedM,
        'distanceM': distanceM,
        'elapsedSec': elapsedSec,
        'maxSpeedKmh': maxSpeedKmh,
        'steps': steps,
      };

  /// Returns null for anything unreadable: a half-written file must never
  /// take the whole history down with it.
  static RunRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, Object?>();
    final startedAt = DateTime.tryParse(map['startedAt'] as String? ?? '');
    final distanceM = (map['distanceM'] as num?)?.toDouble();
    final elapsedSec = (map['elapsedSec'] as num?)?.toInt();
    if (startedAt == null || distanceM == null || elapsedSec == null) {
      return null;
    }
    final modeName = map['mode'] as String? ?? 'run';
    return RunRecord(
      id: map['id'] as String? ?? startedAt.microsecondsSinceEpoch.toString(),
      startedAt: startedAt,
      mode: RunMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => RunMode.run,
      ),
      plannedM: (map['plannedM'] as num?)?.toDouble() ?? 0,
      distanceM: distanceM,
      elapsedSec: elapsedSec,
      maxSpeedKmh: (map['maxSpeedKmh'] as num?)?.toDouble() ?? 0,
      steps: (map['steps'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The game's memory: every finished run, kept in `runs.json` in the app
/// support directory (the same place the street graph and tile cache live).
class RunHistory extends ChangeNotifier {
  RunHistory._();

  static final RunHistory instance = RunHistory._();

  /// Old records are dropped from the tail; a phones care about the recent
  /// months, and the file stays small enough to rewrite on every finish.
  static const int maxRecords = 500;
  static const String fileName = 'runs.json';

  final List<RunRecord> _runs = <RunRecord>[];
  File? _file;
  bool _loaded = false;

  List<RunRecord> get runs => List<RunRecord>.unmodifiable(_runs);

  bool get isEmpty => _runs.isEmpty;

  double get totalM => _runs.fold<double>(0, (a, r) => a + r.distanceM);

  double get totalKm => totalM / 1000;

  int get totalSeconds => _runs.fold<int>(0, (a, r) => a + r.elapsedSec);

  RunRecord? get bestPace {
    RunRecord? best;
    for (final run in _runs) {
      final pace = run.avgPaceSecPerKm;
      if (pace <= 0) continue;
      if (best == null || pace < best.avgPaceSecPerKm) best = run;
    }
    return best;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _resolveFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      _runs
        ..clear()
        ..addAll(decoded.map(RunRecord.fromJson).whereType<RunRecord>());
      _runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      notifyListeners();
    } catch (_) {
      // A corrupt history must never block the app from starting.
    }
  }

  Future<void> add(RunRecord record) async {
    _runs.insert(0, record);
    if (_runs.length > maxRecords) {
      _runs.removeRange(maxRecords, _runs.length);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    _runs.clear();
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
        jsonEncode(_runs.map((r) => r.toJson()).toList()),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    } catch (_) {
      // Best effort: a failed write must not break the run screen.
    }
  }
}
