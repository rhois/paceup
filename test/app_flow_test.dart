import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paceup/core/date_format.dart';
import 'package:paceup/core/theme.dart';
import 'package:paceup/data/local/local_store.dart';
import 'package:paceup/data/models/models.dart';
import 'package:paceup/data/repositories/paceup_repository.dart';
import 'package:paceup/data/repositories/local_repository.dart';
import 'package:paceup/providers.dart';
import 'package:paceup/router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Test alur aplikasi sungguhan dengan mode lokal (tanpa backend).
///
/// Ini memverifikasi wiring nyata: injeksi dependensi, repository,
/// routing berbasis login, penyemaian data demo, dan render halaman.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Muat data locale seperti yang dilakukan main.dart.
    await AppDate.ensureLoaded();
  });

  /// Set viewport seukuran ponsel supaya seluruh form/bottom-nav terlihat.
  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<(Widget, LocalRepository)> bootApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final repo = LocalRepository(store);
    await repo.bootstrap();

    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        repositoryProvider.overrideWithValue(repo),
      ],
    );
    // Penting: dispose container SETELAH widget dibongkar, supaya
    // RecordingController tidak dipakai setelah dibuang.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    // Widget root setara `PaceUpApp` di main.dart.
    final widget = UncontrolledProviderScope(
      container: container,
      child: _TestApp(container: container),
    );
    return (widget, repo);
  }

  testWidgets('menampilkan halaman login saat belum masuk', (tester) async {
    usePhoneViewport(tester);
    final (app, _) = await bootApp(tester);
    await tester.pumpWidget(app);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Selamat datang kembali'), findsOneWidget);
    expect(find.text('Masuk'), findsWidgets);
    // Banner mode demo + kredensial contoh harus terlihat.
    expect(find.text('MODE DEMO'), findsOneWidget);
    expect(find.text('demo@paceup.app / paceup123'), findsOneWidget);
  });

  testWidgets('login demo berhasil dan feed terisi data', (tester) async {
    usePhoneViewport(tester);
    final (app, repo) = await bootApp(tester);
    await tester.pumpWidget(app);
    await tester.pump(const Duration(milliseconds: 100));

    // Isi otomatis lalu submit.
    await tester.tap(find.text('Isi otomatis'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Sudah masuk & repository menyimpan sesi.
    expect(repo.cachedProfile, isNotNull);
    expect(repo.cachedProfile!.username, 'kamu');

    // Beranda: dasbor mingguan + aktivitas.
    expect(find.textContaining('Halo'), findsOneWidget);
    expect(find.text('Aktivitas terbaru'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing); // pakai NavigationBar
    expect(find.byType(NavigationBar), findsOneWidget);

    // Data demo benar-benar tersedia dari repository.
    final feed = await repo.feed(limit: 50);
    expect(feed, isNotEmpty, reason: 'feed demo harus berisi aktivitas');
    expect(
      feed.any((f) => f.activity.distanceMeters > 0),
      isTrue,
      reason: 'aktivitas demo harus punya jarak',
    );
  });

  testWidgets('navigasi antar tab berfungsi', (tester) async {
    usePhoneViewport(tester);
    final (app, _) = await bootApp(tester);
    await tester.pumpWidget(app);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Isi otomatis'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Ke tab Peringkat.
    await tester.tap(find.widgetWithText(NavigationDestination, 'Peringkat'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Peringkat'), findsWidgets);

    // Ke tab Profil.
    await tester.tap(find.widgetWithText(NavigationDestination, 'Profil'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Profil'), findsWidgets);
  });

  testWidgets('layar rekam tampil dengan tombol MULAI LARI', (tester) async {
    usePhoneViewport(tester);
    final (app, _) = await bootApp(tester);
    await tester.pumpWidget(app);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Isi otomatis'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.widgetWithText(NavigationDestination, 'Rekam'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // GPS tidak tersedia di dalam test -> layar menampilkan status/error,
    // yang penting halaman ter-render tanpa crash.
    expect(
      find.textContaining('GPS').evaluate().isNotEmpty ||
          find.text('MULAI LARI').evaluate().isNotEmpty,
      isTrue,
      reason: 'halaman rekam harus merender status GPS atau tombol mulai',
    );
  });

  test('repository lokal: kudos & komentar memengaruhi counter', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final repo = LocalRepository(store);
    await repo.bootstrap();
    await repo.signInWithPassword(
      email: 'demo@paceup.app',
      password: 'paceup123',
    );

    final feed = await repo.feed(limit: 5);
    final first = feed.first;

    final before = await repo.toggleKudos(first.activity.id);
    final after = await repo.toggleKudos(first.activity.id);
    expect(before, isNot(equals(after)));

    final comment = await repo.addComment(first.activity.id, 'Mantap!');
    expect(comment.body, 'Mantap!');

    final comments = await repo.comments(first.activity.id);
    expect(comments.length, greaterThanOrEqualTo(1));
    expect(comments.any((c) => c.body == 'Mantap!'), isTrue);
  });

  test('repository lokal: leaderboard terurut sesuai metrik', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final repo = LocalRepository(store);
    await repo.bootstrap();

    final byDistance = await repo.leaderboard();
    expect(byDistance, isNotEmpty);
    for (var i = 1; i < byDistance.length; i++) {
      expect(
        byDistance[i - 1].totalDistanceMeters,
        greaterThanOrEqualTo(byDistance[i].totalDistanceMeters),
      );
    }

    final byElevation = await repo.leaderboard(
      metric: LeaderboardMetric.elevation,
    );
    for (var i = 1; i < byElevation.length; i++) {
      expect(
        byElevation[i - 1].totalElevationMeters,
        greaterThanOrEqualTo(byElevation[i].totalElevationMeters),
      );
    }
  });

  test('repository lokal: ringkasan mingguan & PR terhitung', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final repo = LocalRepository(store);
    await repo.bootstrap();
    final me = await repo.signInWithPassword(
      email: 'demo@paceup.app',
      password: 'paceup123',
    );

    final summary = await repo.weeklySummary(me.id);
    expect(summary.dailyDistances.length, 7);
    expect(summary.weekStart.weekday, DateTime.monday);

    final prs = await repo.personalRecords(me.id);
    expect(prs, isNotEmpty);
    expect(prs.any((p) => p.label == 'Jarak terjauh'), isTrue);
  });

  test('repository lokal: menolak login dengan sandi salah', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final repo = LocalRepository(store);
    await repo.bootstrap();

    expect(
      () => repo.signInWithPassword(
        email: 'demo@paceup.app',
        password: 'salah',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('repository lokal: signup lalu aktivitas baru muncul di daftar', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final repo = LocalRepository(store);
    await repo.bootstrap();

    final profile = await repo.signUp(
      email: 'baru@paceup.app',
      password: 'rahasia123',
      username: 'pelaribaru',
      displayName: 'Pelari Baru',
    );
    expect(profile.username, 'pelaribaru');

    var mine = await repo.activitiesOf(profile.id);
    expect(mine, isEmpty);

    final activity = Activity(
      id: 'test-1',
      userId: profile.id,
      type: ActivityType.run,
      startedAt: DateTime.now(),
      title: 'Lari uji',
      distanceMeters: 5000,
      movingSeconds: 1500,
      elapsedSeconds: 1600,
    );
    await repo.saveActivity(activity);

    mine = await repo.activitiesOf(profile.id);
    expect(mine.length, 1);
    expect(mine.first.title, 'Lari uji');
  });
}

/// Widget root untuk test: memakai router asli dengan container override.
class _TestApp extends StatelessWidget {
  const _TestApp({required this.container});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context) {
    return _RouterHost(container: container);
  }
}

class _RouterHost extends ConsumerStatefulWidget {
  const _RouterHost({required this.container});

  final ProviderContainer container;

  @override
  ConsumerState<_RouterHost> createState() => _RouterHostState();
}

class _RouterHostState extends ConsumerState<_RouterHost> {
  GoRouter? _router;

  @override
  Widget build(BuildContext context) {
    // buildRouter() memakai WidgetRef; di dalam ConsumerState kita punya `ref`.
    _router ??= buildRouter(ref);
    return MaterialApp.router(
      title: 'PaceUp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: _router,
    );
  }
}
