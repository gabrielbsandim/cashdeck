import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/assets/assets_providers.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';
import 'package:cashdeck/features/outlook/presentation/outlook_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The person's properties, vehicles and other goods; any change moves the
/// net worth, so it reloads too.
class AssetsController extends AsyncNotifier<AssetsSummary> {
  @override
  Future<AssetsSummary> build() async =>
      (await ref.watch(listAssetsProvider).call()).orThrow;

  Future<AppFailure?> _after(Result<Object?> result) async {
    if (result case Err(:final failure)) return failure;
    ref
      ..invalidateSelf()
      ..invalidate(netWorthProvider);
    return null;
  }

  Future<AppFailure?> create(AssetDraft draft) async =>
      await _after(await ref.read(createAssetProvider).call(draft));

  Future<AppFailure?> edit(Asset before, AssetDraft draft) async =>
      await _after(await ref.read(editAssetProvider).call(before, draft));

  Future<AppFailure?> revalue(String id, Money value) async =>
      await _after(await ref.read(revalueAssetProvider).call(id, value));

  Future<AppFailure?> markSold(String id) async =>
      await _after(await ref.read(markAssetSoldProvider).call(id));

  Future<AppFailure?> delete(String id) async =>
      await _after(await ref.read(deleteAssetProvider).call(id));
}

final AsyncNotifierProvider<AssetsController, AssetsSummary>
assetsControllerProvider =
    AsyncNotifierProvider.autoDispose<AssetsController, AssetsSummary>(
      AssetsController.new,
      retry: noRetry,
    );
