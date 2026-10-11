import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'models/user.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/share_view_screen.dart';
import 'services/api.dart';
import 'services/auth_store.dart';
import 'theme/ink_theme.dart';

class ClipboardApp extends StatefulWidget {
  const ClipboardApp({super.key});

  @override
  State<ClipboardApp> createState() => _ClipboardAppState();
}

class _ClipboardAppState extends State<ClipboardApp> {
  final _store = AuthStore();
  late final ClipApi _api = ClipApi(_store);
  final _nav = GlobalKey<NavigatorState>();

  ClipUser? _user;
  bool _ready = false;
  String? _pendingShareToken;

  @override
  void initState() {
    super.initState();
    _boot();
    _listenLinks();
  }

  Future<void> _boot() async {
    await _api.load();
    try {
      _user = await _api.me();
    } catch (_) {
      _user = null;
    }
    if (mounted) setState(() => _ready = true);
    if (_pendingShareToken != null && _ready) {
      _openShare(_pendingShareToken!);
      _pendingShareToken = null;
    }
  }

  void _listenLinks() {
    try {
      final links = AppLinks();
      links.uriLinkStream.listen((uri) {
        final token = _tokenFromUri(uri);
        if (token != null) {
          if (_ready) {
            _openShare(token);
          } else {
            _pendingShareToken = token;
          }
        }
      });
      links.getInitialLink().then((uri) {
        if (uri == null) return;
        final token = _tokenFromUri(uri);
        if (token != null) _pendingShareToken = token;
      });
    } catch (_) {}
  }

  String? _tokenFromUri(Uri uri) {
    final parts = uri.pathSegments;
    final i = parts.indexOf('s');
    if (i >= 0 && i + 1 < parts.length) return parts[i + 1];
    if (uri.host == 's' && parts.isNotEmpty) return parts.first;
    return null;
  }

  void _openShare(String token) {
    _nav.currentState?.push(
      MaterialPageRoute(builder: (_) => ShareViewScreen(api: _api, token: token)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _nav,
      title: '剪贴板',
      debugShowCheckedModeBanner: false,
      theme: buildInkTheme(Brightness.light),
      darkTheme: buildInkTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: !_ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _user == null
              ? LoginScreen(
                  api: _api,
                  store: _store,
                  onLoggedIn: (user) => setState(() => _user = user),
                )
              : HomeScreen(
                  api: _api,
                  user: _user!,
                  onLogout: () async {
                    await _api.logout();
                    setState(() => _user = null);
                  },
                  onOpenSettings: () {
                    _nav.currentState?.push(
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                          api: _api,
                          store: _store,
                          onSaved: () async {
                            _user = await _api.me();
                            setState(() {});
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
