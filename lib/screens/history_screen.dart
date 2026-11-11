import 'package:flutter/material.dart';

import '../core/metrics.dart';
import '../l10n/app_strings.dart';
import '../services/run_history.dart';
import '../services/run_tracker.dart' show RunMode;
import '../services/territory.dart';
import '../theme.dart';

/// The game's memory: totals on top, every finished run below.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final t = l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.t('history')),
        actions: [
          ListenableBuilder(
            listenable: RunHistory.instance,
            builder: (context, _) {
              if (RunHistory.instance.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: t.t('historyClear'),
                onPressed: () => _confirmClear(context),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: RunHistory.instance,
        builder: (context, _) {
          final history = RunHistory.instance;
          if (history.isEmpty) return _Empty(text: t.t('historyEmpty'));
          final runs = history.runs;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: runs.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == 0) return _Totals(history: history, t: t);
              return _RunTile(record: runs[i - 1], t: t);
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('historyClearTitle')),
        content: Text(l10n.t('historyClearBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.t('offlineCancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.t('historyClear')),
          ),
        ],
      ),
    );
    if (ok == true) await RunHistory.instance.clear();
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.history, required this.t});

  final RunHistory history;
  final L10n t;

  @override
  Widget build(BuildContext context) {
    final best = history.bestPace;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.t('historyTotals', {
              'c': history.runs.length.toString(),
              'n': fmtKm(history.totalKm),
            }),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.accent,
            ),
          ),
          if (best != null) ...[
            const SizedBox(height: 6),
            Text(
              t.t('historyBestPace', {
                'm': (best.avgPaceSecPerKm ~/ 60).toString(),
                'ss': (best.avgPaceSecPerKm % 60)
                    .round()
                    .toString()
                    .padLeft(2, '0'),
              }),
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
          if (Territory.instance.count > 0) ...[
            const SizedBox(height: 4),
            Text(
              t.t('territoryCount', {'n': '${Territory.instance.count}'}),
              style: const TextStyle(
                color: AppColors.teal,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.record, required this.t});

  final RunRecord record;
  final L10n t;

  @override
  Widget build(BuildContext context) {
    final pace = record.avgPaceSecPerKm;
    final paceLabel = pace > 0
        ? t.t('paceVal', {
            'm': (pace ~/ 60).toString(),
            'ss': (pace % 60).round().toString().padLeft(2, '0'),
          })
        : null;
    final when = _fmtDate(record.startedAt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Icon(
            switch (record.mode) {
              RunMode.walk => Icons.directions_walk,
              RunMode.run => Icons.directions_run,
              RunMode.sprint => Icons.bolt,
            },
            color: AppColors.accent,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fmtKm(record.distanceM / 1000)} km · ${fmtDurationSec(record.elapsedSec)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  paceLabel == null ? when : '$when · $paceLabel',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (record.steps > 0)
            Text(
              '${record.steps} ${t.t('steps').toLowerCase()}',
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.route_outlined, size: 46, color: AppColors.muted),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtDate(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$d.$m · $hh:$mm';
}
