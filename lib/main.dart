import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_strings.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/run_history.dart';
import 'services/territory.dart';
import 'services/tile_prefetch.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('lang');
  final savedServer = prefs.getString('tileServer');
  if (savedServer != null && savedServer.isNotEmpty) {
    TilePrefetcher.instance.setTileServer(savedServer);
  }
  await TilePrefetcher.instance.initCache();
  await RunHistory.instance.load();
  await Territory.instance.load();
  final initial = L10n.isSupported(saved) ? saved! : null;
  runApp(RealRouteApp(initialLang: initial));
}

class RealRouteApp extends StatefulWidget {
  const RealRouteApp({super.key, this.initialLang});

  final String? initialLang;

  static RealRouteAppState of(BuildContext context) =>
      context.findAncestorStateOfType<RealRouteAppState>()!;

  @override
  State<RealRouteApp> createState() => RealRouteAppState();
}

class RealRouteAppState extends State<RealRouteApp> {
  late String _lang = L10n.isSupported(widget.initialLang)
      ? widget.initialLang!
      : defaultFallbackLang;

  L10n get l10n => L10n(_lang);

  void setLang(String code) {
    setState(() => _lang = code);
    SharedPreferences.getInstance().then((p) => p.setString('lang', code));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RealRoute RPG',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomeScreen(l10n: l10n),
      routes: {
        '/settings': (_) => SettingsScreen(l10n: l10n),
        '/history': (_) => HistoryScreen(l10n: l10n),
      },
    );
  }
}

const defaultFallbackLang = 'en';
