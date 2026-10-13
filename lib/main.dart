import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'core/date_format.dart';
import 'core/env.dart';
import 'core/theme.dart';
import 'data/local/local_store.dart';
import 'data/repositories/local_repository.dart';
import 'data/repositories/paceup_repository.dart';
import 'data/repositories/supabase_repository.dart';
import 'providers.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Format tanggal Indonesia (mis. "Senin, 3 Maret 2026").
  await AppDate.ensureLoaded();

  final store = await LocalStore.open();

  // Pilih backend: Supabase bila dikonfigurasi, kalau tidak mode lokal.
  late final PaceUpRepository repository;
  if (AppEnv.hasSupabase) {
    await sb.Supabase.initialize(
      url: AppEnv.supabaseUrl,
      publishableKey: AppEnv.supabaseAnonKey,
    );
    repository = SupabaseRepository(sb.Supabase.instance.client);
  } else {
    repository = LocalRepository(store);
  }

  await repository.bootstrap();

  runApp(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        repositoryProvider.overrideWithValue(repository),
      ],
      child: const PaceUpApp(),
    ),
  );
}

class PaceUpApp extends ConsumerStatefulWidget {
  const PaceUpApp({super.key});

  @override
  ConsumerState<PaceUpApp> createState() => _PaceUpAppState();
}

class _PaceUpAppState extends ConsumerState<PaceUpApp> {
  late final _router = buildRouter(ref);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppEnv.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: _router,
      builder: (context, child) {
        // Batasi skala teks agar tata letak tetap rapi pada aksesibilitas tinggi.
        final scale = MediaQuery.of(context).textScaler.scale(1).clamp(0.85, 1.3);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale.toDouble()),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
