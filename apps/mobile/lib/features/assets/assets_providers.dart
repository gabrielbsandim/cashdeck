import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/assets/application/assets_use_cases.dart';
import 'package:cashdeck/features/assets/data/api_assets_repository.dart';
import 'package:cashdeck/features/assets/data/fake_assets_repository.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final assetsRepositoryProvider = Provider<AssetsRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeAssetsRepository(ref.watch(clockProvider)),
    Backend.api => ApiAssetsRepository(ref.watch(dioProvider)),
  };
});

final listAssetsProvider = Provider<ListAssets>(
  (ref) => ListAssets(ref.watch(assetsRepositoryProvider)),
);

final createAssetProvider = Provider<CreateAsset>(
  (ref) => CreateAsset(
    ref.watch(assetsRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

final editAssetProvider = Provider<EditAsset>(
  (ref) =>
      EditAsset(ref.watch(assetsRepositoryProvider), ref.watch(clockProvider)),
);

final revalueAssetProvider = Provider<RevalueAsset>(
  (ref) => RevalueAsset(ref.watch(assetsRepositoryProvider)),
);

final markAssetSoldProvider = Provider<MarkAssetSold>(
  (ref) => MarkAssetSold(
    ref.watch(assetsRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

final deleteAssetProvider = Provider<DeleteAsset>(
  (ref) => DeleteAsset(ref.watch(assetsRepositoryProvider)),
);

final browseVehiclesProvider = Provider<BrowseVehicles>(
  (ref) => BrowseVehicles(ref.watch(assetsRepositoryProvider)),
);

final loadRentBillProvider = Provider<LoadRentBill>(
  (ref) => LoadRentBill(ref.watch(assetsRepositoryProvider)),
);
