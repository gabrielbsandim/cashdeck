import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/capture/data/api_capture_repository.dart';
import 'package:cashdeck/features/capture/data/fake_capture_repository.dart';
import 'package:cashdeck/features/capture/domain/capture_sources.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final captureRepositoryProvider = Provider<CaptureRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeCaptureRepository(ref.watch(clockProvider)),
    Backend.api => ApiCaptureRepository(ref.watch(dioProvider)),
  };
});
