import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/brand/cd_mark.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/features/auth/auth_providers.dart';
import 'package:cashdeck/features/auth/presentation/account_providers.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The lock after five idle minutes: the device check, or the password.
class UnlockScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const sensorKey = Key('unlock-sensor');
  static const passwordToggleKey = Key('unlock-use-password');
  static const passwordKey = Key('unlock-password');
  static const submitKey = Key('unlock-submit');

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  var _usePassword = false;
  var _password = '';
  String? _error;

  Future<void> _sensor() async {
    final l10n = AppLocalizations.of(context);
    final ok = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate(l10n.unlockReason);
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = l10n.confirmDenied);
      return;
    }
    context.go(AppRoutes.home);
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final result = await ref.read(accountRepositoryProvider).unlock(_password);
    if (!mounted) return;
    switch (result) {
      case Ok():
        context.go(AppRoutes.home);
      case Err(:final failure):
        setState(() => _error = failure.userMessage(l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final name = ref.watch(sessionProvider).value?.firstName;
    final error = _error;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          children: [
            const SizedBox(height: AppSpacing.xxxl),
            const Center(child: CdMark(size: 64)),
            const SizedBox(height: AppSpacing.xl),
            Text(
              name == null ? l10n.unlockTitleAnonymous : l10n.unlockTitle(name),
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLg.copyWith(color: palette.onSurface),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              ref.watch(serverInfoProvider).value?.host ?? '',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xxxl),
            if (!_usePassword) ...[
              Center(
                child: Semantics(
                  button: true,
                  label: l10n.unlockSensor,
                  child: InkResponse(
                    key: UnlockScreen.sensorKey,
                    onTap: _sensor,
                    radius: 48,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: palette.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Symbols.fingerprint_rounded,
                        size: 44,
                        color: palette.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.unlockSensor,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLg.copyWith(color: palette.onSurface),
              ),
            ],
            if (_usePassword) ...[
              CdTextField(
                key: UnlockScreen.passwordKey,
                label: l10n.fieldPassword,
                secret: true,
                autofillHints: const [AutofillHints.password],
                onChanged: (value) => _password = value,
              ),
              const SizedBox(height: AppSpacing.md),
              CdButton.filled(
                key: UnlockScreen.submitKey,
                expand: true,
                label: l10n.unlockButton,
                onPressed: _submit,
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                error,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd.copyWith(
                  color: context.money.failed,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Center(
              child: CdButton.text(
                key: UnlockScreen.passwordToggleKey,
                label: _usePassword ? l10n.useSensorButton : l10n.usePassword,
                onPressed: () => setState(() {
                  _usePassword = !_usePassword;
                  _error = null;
                }),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Symbols.lock_rounded,
                  size: 16,
                  color: palette.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    l10n.unlockIdleNote,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
