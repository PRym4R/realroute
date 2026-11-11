import 'package:flutter_test/flutter_test.dart';
import 'package:realroute/services/run_history.dart';
import 'package:realroute/services/run_tracker.dart' show RunMode;

RunRecord _record({
  String id = 'r1',
  DateTime? startedAt,
  RunMode mode = RunMode.run,
  double distanceM = 1000,
  int elapsedSec = 300,
  double maxSpeedKmh = 14.2,
  int steps = 1200,
}) {
  return RunRecord(
    id: id,
    startedAt: startedAt ?? DateTime.utc(2026, 11, 11, 7, 30),
    mode: mode,
    plannedM: 1000,
    distanceM: distanceM,
    elapsedSec: elapsedSec,
    maxSpeedKmh: maxSpeedKmh,
    steps: steps,
  );
}

void main() {
  group('RunRecord metrics', () {
    test('pace is seconds per kilometre', () {
      expect(_record(distanceM: 1000, elapsedSec: 300).avgPaceSecPerKm, 300);
      expect(_record(distanceM: 2000, elapsedSec: 600).avgPaceSecPerKm, 300);
    });

    test('pace is 0 for a run too short to mean anything', () {
      expect(_record(distanceM: 20, elapsedSec: 10).avgPaceSecPerKm, 0);
    });

    test('average speed is km/h', () {
      expect(_record(distanceM: 1000, elapsedSec: 300).avgSpeedKmh,
          closeTo(12, 1e-9));
    });

    test('zero elapsed time does not divide by zero', () {
      expect(_record(elapsedSec: 0).avgSpeedKmh, 0);
    });
  });

  group('RunRecord json', () {
    test('survives a round trip', () {
      final before = _record(mode: RunMode.sprint);
      final after = RunRecord.fromJson(before.toJson())!;
      expect(after.id, before.id);
      expect(after.startedAt, before.startedAt);
      expect(after.mode, before.mode);
      expect(after.plannedM, before.plannedM);
      expect(after.distanceM, before.distanceM);
      expect(after.elapsedSec, before.elapsedSec);
      expect(after.maxSpeedKmh, before.maxSpeedKmh);
      expect(after.steps, before.steps);
    });

    test('rejects junk instead of throwing', () {
      expect(RunRecord.fromJson(null), isNull);
      expect(RunRecord.fromJson('nope'), isNull);
      expect(RunRecord.fromJson(<String, Object?>{}), isNull);
      expect(
        RunRecord.fromJson(<String, Object?>{'startedAt': 'not-a-date'}),
        isNull,
      );
    });

    test('an unknown mode falls back to run', () {
      final json = _record().toJson()..['mode'] = 'teleport';
      expect(RunRecord.fromJson(json)!.mode, RunMode.run);
    });

    test('missing optional numbers default to zero', () {
      final json = <String, Object?>{
        'startedAt': '2026-11-11T07:30:00.000Z',
        'distanceM': 500,
        'elapsedSec': 200,
      };
      final record = RunRecord.fromJson(json)!;
      expect(record.steps, 0);
      expect(record.maxSpeedKmh, 0);
      expect(record.plannedM, 0);
    });
  });
}
