import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/auth_state.dart';
import 'services/db_service.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthState(),
      child: MaterialApp(
        title: 'Siêu thị mini',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: const RootPage(),
      ),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  bool _initialized = false;
  bool _welcomeSeen = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      await DBService.init();
      // read flag from Hive settings box
      final box = DBService.settings();
      final seen = box.get('welcomeSeen', defaultValue: false) as bool;
      final savedRole = box.get('current_role')?.toString();
      final hasSession =
          DBService.currentUserId() != null &&
          (box.get('auth_token')?.toString().isNotEmpty ?? false);
      if (!mounted) return;
      if (hasSession && savedRole != null && savedRole.isNotEmpty) {
        Provider.of<AuthState>(context, listen: false).restore(savedRole);
      }
      setState(() {
        _welcomeSeen = seen;
        _initialized = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initError = e.toString();
        _initialized = true;
      });
    }
  }

  void _onStartPressed() async {
    final box = DBService.settings();
    await box.put('welcomeSeen', true);
    setState(() {
      _welcomeSeen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_initError != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  const Text(
                    'Không khởi động được ứng dụng',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(_initError!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _initialized = false;
                        _initError = null;
                      });
                      _loadSettings();
                    },
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_welcomeSeen) {
      return WelcomeScreen(onStart: _onStartPressed);
    }

    final auth = Provider.of<AuthState>(context);
    return HomeScreen(
      role: auth.role ?? 'customer',
      onLogout: () {
        auth.logout();
      },
    );
  }
}
