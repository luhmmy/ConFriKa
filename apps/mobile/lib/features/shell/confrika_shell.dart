import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/theme/confrika_theme.dart';
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
  String _listeningLang = 'English';

  void _startCall(String username) {
    setState(() {
      _pendingCallee = username;
      _currentIndex = 2;
    });
  }

  void _openDirectMessage(Map<String, dynamic> contact) {
    setState(() {
      _currentIndex = 1; // Switches to Global Spaces / Direct Messages tab
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;

    final screens = [
      HomeScreen(
        onOpenGlobalSpaces: () => setState(() => _currentIndex = 1),
        onOpenToneCoach: () => setState(() => _currentIndex = 3),
        onOpenTranslate: () => setState(() => _currentIndex = 4),
        onStartCall: _startCall,
        onOpenDirectMessage: _openDirectMessage,
      ),
      GlobalSpacesChatScreen(onStartCall: _startCall),
      ConnectCallScreen(initialCallee: _pendingCallee),
      const LearnAndToneCoachScreen(),
      const TranslateScreen(),
      const ProfileAndTrustScreen(),
    ];

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: AppBar(
          titleSpacing: 10,
          elevation: 0,
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          title: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 1. ConFriKa Logo & Wordmark
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    ConFriKaAppLogo(size: 32),
                    SizedBox(width: 6),
                    ConFriKaWordmark(fontSize: 18),
                  ],
                ),
                const SizedBox(width: 8),

                // 2. Account Pill
                InkWell(
                  onTap: () => setState(() => _currentIndex = 5),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: ConFriKaColors.oceanBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Account',
                      style: TextStyle(
                        color: ConFriKaColors.oceanBlue,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // 3. Theme Toggle (Sun/Moon icon)
                InkWell(
                  onTap: widget.onToggleThemeMode,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white12 : const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        isDark ? '🌙' : '☀️',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // 4. Listening Language Selector: 🎧 English ⌵
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _listeningLang,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      onChanged: (val) {
                        if (val != null) setState(() => _listeningLang = val);
                      },
                      items: const [
                        DropdownMenuItem(
                          value: 'English',
                          child: Text('🎧 English'),
                        ),
                        DropdownMenuItem(
                          value: 'Yorùbá',
                          child: Text('🎧 🇳🇬 Yorùbá'),
                        ),
                        DropdownMenuItem(
                          value: 'Swahili',
                          child: Text('🎧 🇰🇪 Swahili'),
                        ),
                        DropdownMenuItem(
                          value: 'Zulu',
                          child: Text('🎧 🇿🇦 isiZulu'),
                        ),
                        DropdownMenuItem(
                          value: 'Amharic',
                          child: Text('🎧 🇪🇹 Amharic'),
                        ),
                        DropdownMenuItem(
                          value: 'Français',
                          child: Text('🎧 Français'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // 5. Battery / Connection Status Pill: ● 94%
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '●',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4),
                      Text(
                        '94%',
                        style: TextStyle(
                          color: Color(0xFF047857),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(child: screens[_currentIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public),
            label: 'Spaces',
          ),
          NavigationDestination(
            icon: Icon(Icons.phone_in_talk_outlined),
            selectedIcon: Icon(Icons.phone_in_talk),
            label: 'Calls',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: 'Learn',
          ),
          NavigationDestination(
            icon: Icon(Icons.translate_outlined),
            selectedIcon: Icon(Icons.translate),
            label: 'Translate',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
