import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/features/entities/domain/entity_profile.dart';
import 'package:cashdeck/features/entities/entities_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Invalidated after an edit, so every screen showing a name reloads it.
final FutureProvider<List<EntityProfile>> entityProfilesProvider =
    FutureProvider.autoDispose<List<EntityProfile>>(
      (ref) async =>
          (await ref.watch(entityProfileRepositoryProvider).list()).orThrow,
      retry: noRetry,
    );
