import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/capture/data/fake_capture_repository.dart';
import 'package:cashdeck/features/capture/domain/capture_sources.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// No capture endpoint yet, so both backends read the fake.
final captureRepositoryProvider = Provider<CaptureRepository>(
  (ref) => FakeCaptureRepository(ref.watch(clockProvider)),
);
