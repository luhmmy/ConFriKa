import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/widgets/confrika_brand_widgets.dart';
import '../connect/connect_call_screen.dart';
import '../home/home_screen.dart';
import '../learn/learn_and_tone_coach_screen.dart';
import '../profile/profile_and_trust_screen.dart';
import '../spaces/global_spaces_chat_screen.dart';
import '../translate/translate_screen.dart';

class ConFriKaShell extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleThemeMode;

  const ConFriKaShell({
    super.key,
    required this.isDarkMode,
    required this.onToggleThemeMode,
  });

  @override
  State<ConFriKaShell> createState() => _ConFriKaShellState();
}

class _ConFriKaShellState extends State<ConFriKaShell> {
  int _currentIndex = 0;
  String? _pendingCallee;

  void _startCall(String username) {
    setState(() {
      _pendingCallee = username;
      _currentIndex = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        onOpenGlobalSpaces: () => setState(() => _currentIndex = 1),
        onOpenToneCoach: () => setState(() => _currentIndex = 3),
        onOpenTranslate: () => setState(() => _currentIndex = 4),
        onStartCall: _startCall,
      ),
      GlobalSpacesChatScreen(onStartCall: _startCall),
      ConnectCallScreen(initialCallee: _pendingCallee),
      const LearnAndToneCoachScreen(),
      const TranslateScreen(),
      const ProfileAndTrustScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 14,
        title: const Row(
          children: [
            ConFriKaAppLogo(size: 34),
            SizedBox(width: 8),
            ConFriKaWordmark(fontSize: 19),
          ],
        ),
        actions: [
          IconButton(
            tooltip: widget.isDarkMode ? 'Light mode' : 'Dark mode',
            onPressed: widget.onToggleThemeMode,
            icon: Icon(widget.isDarkMode ? Icons.dark_mode : Icons.light_mode, size: 20),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign out?'),
                  content: const Text('You will need to log in again.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Sign out')),
                  ],
                ),
              );
              if (confirm == true) await ConFriKaSession.instance.signOut();
            },
            icon: const Icon(Icons.logout, size: 20),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(child: screens[_currentIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.public_outlined),
              selectedIcon: Icon(Icons.public),
              label: 'Spaces'),
          NavigationDestination(
              icon: Icon(Icons.phone_in_talk_outlined),
              selectedIcon: Icon(Icons.phone_in_talk),
              label: 'Calls'),
          NavigationDestination(
              icon: Icon(Icons.school_outlined),
              selectedIcon: Icon(Icons.school),
              label: 'Learn'),
          NavigationDestination(
              icon: Icon(Icons.translate_outlined),
              selectedIcon: Icon(Icons.translate),
              label: 'Translate'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }
}
