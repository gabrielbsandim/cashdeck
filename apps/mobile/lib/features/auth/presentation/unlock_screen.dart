import 'package:cashdeck/core/security/app_lock.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/brand/cd_mark.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/features/auth/auth_providers.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The lock at launch and after five idle minutes: the device check, which
/// takes the PIN when biometrics fail.
class UnlockScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const sensorKey = Key('unlock-sensor');
  static const signOutKey = Key('unlock-sign-out');

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
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
    ref.read(appLockProvider.notifier).unlock();
  }

  Future<void> _signOut() async {
    await ref.read(signOutProvider).call();
    ref.read(appLockProvider.notifier).unlock();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
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
              l10n.unlockTitleAnonymous,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLg.copyWith(color: palette.onSurface),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              ref.watch(serverSessionProvider)?.host ?? '',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xxxl),
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
                key: UnlockScreen.signOutKey,
                label: l10n.signOutButton,
                onPressed: _signOut,
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
