import 'package:flutter/material.dart';

import 'core/services/audio_service.dart';
import 'core/services/callkit_service.dart';
import 'core/session.dart';
import 'core/theme/confrika_theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/shell/confrika_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ConFriKaCallKitService().initialize();
  ConFriKaAudioService().initialize();
  await ConFriKaSession.instance.load();
  runApp(const ConFriKaApp());
}

class ConFriKaApp extends StatefulWidget {
  const ConFriKaApp({super.key});

  @override
  State<ConFriKaApp> createState() => _ConFriKaAppState();
}

class _ConFriKaAppState extends State<ConFriKaApp> {
  bool _isDarkMode = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ConFriKa — Connect Africa',
      debugShowCheckedModeBanner: false,
      theme: ConFriKaTheme.lightTheme,
      darkTheme: ConFriKaTheme.darkTheme,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: AnimatedBuilder(
        animation: ConFriKaSession.instance,
        builder: (context, _) {
          if (!ConFriKaSession.instance.isAuthenticated) {
            return const ConFriKaAuthScreen();
          }
          return ConFriKaShell(
            isDarkMode: _isDarkMode,
            onToggleThemeMode: () => setState(() => _isDarkMode = !_isDarkMode),
          );
        },
      ),
    );
  }
}
