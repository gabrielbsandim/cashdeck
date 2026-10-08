import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/brand/cd_mark.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/features/auth/auth_providers.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The first screen on a new device: the server address and its token. The
/// router leaves it once the session holds them.
class ServerSignInScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const urlKey = Key('sign-in-url');
  static const tokenKey = Key('sign-in-token');
  static const submitKey = Key('sign-in-submit');

  @override
  ConsumerState<ServerSignInScreen> createState() => _ServerSignInScreenState();
}

class _ServerSignInScreenState extends ConsumerState<ServerSignInScreen> {
  late String _url = ref.read(appConfigProvider).apiBaseUrl;
  var _token = '';
  var _submitted = false;
  var _sending = false;
  String? _failure;

  Set<SignInField> get _errors =>
      signInErrorsOf(serverUrl: _url, token: _token);

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (_errors.isNotEmpty) return;
    setState(() => _sending = true);
    final l10n = AppLocalizations.of(context);
    final result = await ref
        .read(signInProvider)
        .call(serverUrl: _url, token: _token);
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        await ref.read(serverSessionProvider.notifier).signIn(value);
      case Err(:final failure):
        setState(() {
          _sending = false;
          _failure = failure.userMessage(l10n);
        });
    }
  }

  String? _errorFor(SignInField field, String message) =>
      _submitted && _errors.contains(field) ? message : null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final failure = _failure;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          children: [
            const SizedBox(height: AppSpacing.xxl),
            const Align(alignment: Alignment.centerLeft, child: CdMark()),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.signInTitle,
              style: AppTextStyles.headlineMd.copyWith(
                color: palette.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.signInBody,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            CdTextField(
              key: ServerSignInScreen.urlKey,
              label: l10n.fieldServerUrl,
              initialValue: _url,
              keyboardType: TextInputType.url,
              autofillHints: const [AutofillHints.url],
              textInputAction: TextInputAction.next,
              errorText: _errorFor(
                SignInField.serverUrl,
                l10n.errorServerUrlInvalid,
              ),
              onChanged: (value) => setState(() => _url = value),
            ),
            const SizedBox(height: AppSpacing.md),
            CdTextField(
              key: ServerSignInScreen.tokenKey,
              label: l10n.fieldAccessToken,
              secret: true,
              monospace: true,
              autofillHints: const [AutofillHints.password],
              errorText: _errorFor(SignInField.token, l10n.errorTokenRequired),
              onChanged: (value) => setState(() => _token = value),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.accessTokenHint,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
            if (failure != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                failure,
                style: AppTextStyles.bodyMd.copyWith(
                  color: context.money.failed,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            CdButton.filled(
              key: ServerSignInScreen.submitKey,
              expand: true,
              loading: _sending,
              label: l10n.signInButton,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
