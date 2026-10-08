import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';

extension FailureMessage on AppFailure {
  String userMessage(AppLocalizations l10n) {
    return switch (this) {
      NetworkFailure() => l10n.errorNetwork,
      UnauthorizedFailure() => l10n.errorSessionExpired,
      ForbiddenFailure() => l10n.errorForbidden,
      NotFoundFailure() => l10n.errorNotFound,
      ValidationFailure(:final message) => message,
      RateLimitedFailure() => l10n.errorRateLimited,
      ServerFailure() => l10n.errorServer,
      UnexpectedFailure() => l10n.errorUnexpected,
      UnsupportedFailure() => l10n.errorUnsupported,
    };
  }
}
