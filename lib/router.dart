import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/env.dart';
import 'data/models/models.dart';
import 'features/activity/activity_detail_page.dart';
import 'features/auth/login_page.dart';
import 'features/auth/signup_page.dart';
import 'features/home/home_page.dart';
import 'features/leaderboard/athlete_page.dart';
import 'features/leaderboard/leaderboard_page.dart';
import 'features/profile/profile_page.dart';
import 'features/profile/settings_page.dart';
import 'features/record/record_page.dart';
import 'features/record/record_summary_page.dart';
import 'services/recording_controller.dart';
import 'providers.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

/// Router aplikasi. Halaman feed/record/leaderboard/profil memakai bottom
/// navigation (ShellRoute) supaya rekaman tetap hidup saat berpindah tab.
GoRouter buildRouter(WidgetRef ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final profile = ref.read(currentProfileProvider);
      final loggingIn =
          state.matchedLocation == '/login' || state.matchedLocation == '/signup';
      if (profile == null && !loggingIn) return '/login';
      if (profile != null && loggingIn) return '/';
      return null;
    },
    refreshListenable: _AuthRefresh(ref),
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupPage(),
      ),
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomePage()),
          ),
          GoRoute(
            path: '/record',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: RecordPage()),
          ),
          GoRoute(
            path: '/leaderboard',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: LeaderboardPage()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ProfilePage()),
          ),
        ],
      ),
      GoRoute(
        path: '/activity/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            ActivityDetailPage(activityId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/record/summary',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            RecordSummaryPage(activity: state.extra as Activity?),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/athlete/:username',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            AthletePage(username: state.pathParameters['username']!),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Halaman tidak ditemukan')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('404 — rute tidak dikenal'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('Kembali ke beranda'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Memberi tahu GoRouter saat status login berubah.
///
/// GoRouter membutuhkan `Listenable`; kita jembatani dari stream auth
/// milik repository.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(WidgetRef ref) {
    _sub = ref.read(repositoryProvider).watchAuth().listen((profile) {
      if (_last?.id != profile?.id) {
        _last = profile;
        notifyListeners();
      }
    });
  }

  late final StreamSubscription<Profile?> _sub;
  Profile? _last;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// Kerangka dengan bottom navigation. Tombol "Rekam" dibuat menonjol.
class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  static const _items = [
    (icon: Icons.dynamic_feed_outlined, active: Icons.dynamic_feed, label: 'Feed', path: '/'),
    (icon: Icons.leaderboard_outlined, active: Icons.leaderboard, label: 'Peringkat', path: '/leaderboard'),
    (icon: Icons.play_circle_fill, active: Icons.play_circle_fill, label: 'Rekam', path: '/record'),
    (icon: Icons.person_outline, active: Icons.person, label: 'Profil', path: '/profile'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final recording = ref.watch(recordingControllerProvider);

    // Indeks terpilih: '/' -> 0, '/record' -> 2, dst.
    var index = _items.indexWhere((i) => i.path == location);
    if (index < 0) {
      index = _items.indexWhere((i) => i.path != '/' && location.startsWith(i.path));
      if (index < 0) index = 0;
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF2C353F))),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: const Color(0xFF161B22),
            indicatorColor: const Color(0xFFFC5200).withValues(alpha: 0.18),
            labelTextStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          child: NavigationBar(
            selectedIndex: index,
            height: 64,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (i) => context.go(_items[i].path),
            destinations: [
              for (final item in _items)
                NavigationDestination(
                  icon: _icon(item.icon, recording, item.path),
                  selectedIcon: _icon(item.active, recording, item.path),
                  label: item.label,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _icon(IconData icon, RecordingController controller, String path) {
    // Tampilkan titik merah di tab Rekam saat perekaman sedang berjalan.
    final isRecording = path == '/record' && controller.status.isActive;
    if (isRecording) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, color: const Color(0xFFFC5200)),
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFE5484D),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      );
    }
    return Icon(icon);
  }
}

/// Banner kecil penanda mode demo.
class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppEnv.hasSupabase) {
      return Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF5C518).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFF5C518).withValues(alpha: 0.4)),
        ),
        child: const Text(
          'DEMO',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Color(0xFFF5C518),
            letterSpacing: 0.8,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
