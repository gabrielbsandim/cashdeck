import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';

final class ListAssets {
  const new(this._repository);

  final AssetsRepository _repository;

  Future<Result<AssetsSummary>> call() => _repository.list();
}

/// A draft with a problem never reaches the server.
final class CreateAsset {
  const new(this._repository, this._clock);

  final AssetsRepository _repository;
  final Clock _clock;

  Future<Result<Asset>> call(AssetDraft draft) {
    final today = CalendarDate.brazilToday(_clock.now());
    if (draft.problemOn(today) != null) {
      return Future.value(const Err(UnexpectedFailure()));
    }
    return _repository.create(draft);
  }
}

final class RevalueAsset {
  const new(this._repository);

  final AssetsRepository _repository;

  Future<Result<Asset>> call(String id, Money value) {
    if (value.cents <= 0) {
      return Future.value(const Err(UnexpectedFailure()));
    }
    return _repository.revalue(id, value);
  }
}

final class MarkAssetSold {
  const new(this._repository, this._clock);

  final AssetsRepository _repository;
  final Clock _clock;

  Future<Result<Asset>> call(String id) =>
      _repository.markSold(id, CalendarDate.brazilToday(_clock.now()));
}

final class DeleteAsset {
  const new(this._repository);

  final AssetsRepository _repository;

  Future<Result<void>> call(String id) => _repository.delete(id);
}
