import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/app_strings.dart';
import '../main.dart' show RealRouteApp;
import '../services/tile_prefetch.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.l10n});

  final L10n l10n;

  static const String appVersion = '0.1.0';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TilePrefetcher _prefetcher = TilePrefetcher.instance;

  double _radiusKm = 10;
  int _maxZoom = TilePrefetcher.maxZoomForStandard;
  double _cacheMb = 0;

  @override
  void initState() {
    super.initState();
    _prefetcher.addListener(_onPrefetch);
    _refreshCacheSize();
  }

  @override
  void dispose() {
    _prefetcher.removeListener(_onPrefetch);
    super.dispose();
  }

  Future<void> _refreshCacheSize() async {
    final size = await _prefetcher.cacheSizeBytes();
    if (!mounted) return;
    setState(() => _cacheMb = size / (1024 * 1024));
  }

  void _onPrefetch() {
    if (!mounted) return;
    setState(() {});
    if (!_prefetcher.running) _refreshCacheSize();
  }

  L10n get t => widget.l10n;

  int _estimated() => TilePrefetcher.estimateTileCount(50, _radiusKm, _maxZoom);

  Future<void> _startDownload() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t.t('permissionNeeded')),
      ));
      return;
    }

    final position = await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 10),
          ),
        );

    if (!mounted) return;
    await _prefetcher.start(
      center: LatLng(position.latitude, position.longitude),
      radiusKm: _radiusKm,
      maxZoom: _maxZoom,
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.t('offlineClearConfirmTitle')),
        content: Text(t.t('offlineClearConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.t('cheatOk')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.t('offlineClear')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _prefetcher.clearCache();
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefetch = _prefetcher;
    final running = prefetch.running;

    return Scaffold(
      appBar: AppBar(title: Text(t.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t.t('language'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                for (final code in supportedLanguages)
                  _LangTile(
                    code: code,
                    name: appStrings[code]!['langName']!,
                    selected: code == t.code,
                    onTap: () {
                      RealRouteApp.of(context).setLang(code);
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            t.t('offlineTitle'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t.t('offlineHint'),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    t.t('offlineRadius'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final r in const [10.0, 30.0]) ...[
                        ChoiceChip(
                          label: Text(t.t('distanceKm', {'n': r.toStringAsFixed(0)})),
                          selected: _radiusKm == r,
                          onSelected: running
                              ? null
                              : (_) => setState(() => _radiusKm = r),
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _radiusKm == r
                                ? const Color(0xFF1B0F05)
                                : AppColors.muted,
                          ),
                          selectedColor: AppColors.accent,
                          showCheckmark: false,
                        ),
                        const SizedBox(width: 10),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    t.t('offlineQuality'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _ZoomToggle(
                          label: t.t('offlineQualityStd'),
                          subtitle: 'z12–14',
                          selected: _maxZoom == TilePrefetcher.maxZoomForStandard,
                          onTap: running
                              ? null
                              : () => setState(
                                    () => _maxZoom = TilePrefetcher.maxZoomForStandard,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ZoomToggle(
                          label: t.t('offlineQualityHigh'),
                          subtitle: 'z12–15',
                          selected: _maxZoom == TilePrefetcher.maxZoomForDetailed,
                          onTap: running
                              ? null
                              : () => setState(
                                    () => _maxZoom = TilePrefetcher.maxZoomForDetailed,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.t('offlineEstimated', {
                      'n': _estimated().toString(),
                    }),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12.5,
                    ),
                  ),
                  if (_estimated() > 250) ...[
                    const SizedBox(height: 8),
                    Text(
                      t.t('offlineWarn'),
                      style: const TextStyle(
                        color: Color(0xFFE7B75F),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (running)
                    _PrefetchProgress(prefetcher: prefetch, t: t)
                  else
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: const Color(0xFF1B0F05),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.download_rounded),
                      label: Text(t.t('offlineDownload')),
                      onPressed: _startDownload,
                    ),
                  if (prefetch.error != null && !running) ...[
                    const SizedBox(height: 10),
                    Text(t.t(prefetch.error!),
                        style: const TextStyle(
                            color: AppColors.red, fontSize: 12.5)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              title: Text(t.t('offlineCacheSize')),
              subtitle: Text(fmtCacheSizeBytes(_cacheMb)),
              trailing: TextButton(
                onPressed: running ? null : _confirmClear,
                child: Text(
                  t.t('offlineClear'),
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandTitle(size: 18),
                  const SizedBox(height: 12),
                  Text(
                    t.t('aboutBody'),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${t.t('version')} ${SettingsScreen.appVersion}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PrefetchProgress extends StatelessWidget {
  const _PrefetchProgress({required this.prefetcher, required this.t});

  final TilePrefetcher prefetcher;
  final L10n t;

  @override
  Widget build(BuildContext context) {
    final progress =
        prefetcher.total == 0 ? 0.0 : prefetcher.done / prefetcher.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${prefetcher.done}/${prefetcher.total} · ${prefetcher.failed > 0 ? '+${prefetcher.failed} err' : 'ok'}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const Spacer(),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            color: AppColors.accent,
            backgroundColor: AppColors.surface2,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(prefetcher.paused
                    ? Icons.play_arrow
                    : Icons.pause),
                label: Text(prefetcher.paused
                    ? t.t('offlineResume')
                    : t.t('offlinePause')),
                onPressed:
                    prefetcher.paused ? prefetcher.resume : prefetcher.pause,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.red),
                  foregroundColor: AppColors.red,
                ),
                icon: const Icon(Icons.close),
                label: Text(t.t('offlineCancel')),
                onPressed: prefetcher.cancel,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ZoomToggle extends StatelessWidget {
  const _ZoomToggle({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.line,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? const Color(0xFF1B0F05) : AppColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: selected
                      ? const Color(0x991B0F05)
                      : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LangTile extends StatelessWidget {
  const _LangTile({
    required this.code,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        name,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          color: selected ? AppColors.accent : AppColors.text,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: AppColors.accent)
          : null,
      onTap: onTap,
    );
  }
}
