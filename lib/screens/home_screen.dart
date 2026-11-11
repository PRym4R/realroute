import 'package:flutter/material.dart';

import '../core/metrics.dart';
import '../l10n/app_strings.dart';
import '../services/run_history.dart';
import '../services/run_tracker.dart' show RunMode;
import '../theme.dart';
import 'route_map_screen.dart';

const List<double> distanceOptionsKm = [
  0.3,
  0.5,
  0.8,
  1.0,
  1.5,
  2.0,
  5.0,
  10.0,
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.l10n});

  final L10n l10n;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _selectedKm = 1.0;
  RunMode _mode = RunMode.run;

  L10n get t => widget.l10n;

  String _distanceLabel(double km) {
    if (km < 1) {
      return t.t('distanceMt', {'n': (km * 1000).round().toString()});
    }
    return t.t('distanceKm', {'n': fmtNum(km)});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const BrandTitle(size: 22),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: t.t('history'),
            onPressed: () => Navigator.pushNamed(context, '/history'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: t.t('settings'),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                t.t('tagline'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 15,
                ),
              ),
              ListenableBuilder(
                listenable: RunHistory.instance,
                builder: (context, _) {
                  final history = RunHistory.instance;
                  if (history.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      t.t('historyTotals', {
                        'c': history.runs.length.toString(),
                        'n': fmtKm(history.totalKm),
                      }),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              Text(
                t.t('pickDistance'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final d in distanceOptionsKm)
                    _DistanceChip(
                      label: _distanceLabel(d),
                      selected: _selectedKm == d,
                      onTap: () => setState(() => _selectedKm = d),
                    ),
                ],
              ),
              const SizedBox(height: 26),
              Text(
                t.t('pickMode'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<RunMode>(
                style: SegmentedButton.styleFrom(
                  backgroundColor: AppColors.surface2,
                  foregroundColor: AppColors.muted,
                  selectedForegroundColor: const Color(0xFF1B0F05),
                  selectedBackgroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.line),
                ),
                segments: [
                  for (final mode in RunMode.values)
                    ButtonSegment(
                      value: mode,
                      icon: Icon(switch (mode) {
                        RunMode.walk => Icons.directions_walk,
                        RunMode.run => Icons.directions_run,
                        RunMode.sprint => Icons.bolt,
                      }),
                      label: Text(t.t(switch (mode) {
                        RunMode.walk => 'modeWalk',
                        RunMode.run => 'modeRun',
                        RunMode.sprint => 'modeSprint',
                      })),
                    ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: const Color(0xFF1B0F05),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  t.t('generate'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => RouteMapScreen(
                        l10n: t,
                        targetKm: _selectedKm,
                        mode: _mode,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String fmtNum(double d) => d % 1 == 0 ? d.toInt().toString() : d.toString();

class _DistanceChip extends StatelessWidget {
  const _DistanceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: selected ? const Color(0xFF1B0F05) : AppColors.muted,
      ),
      selectedColor: AppColors.accent,
      backgroundColor: AppColors.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? AppColors.accent : AppColors.line),
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    );
  }
}
