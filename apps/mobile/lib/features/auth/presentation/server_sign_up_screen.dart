import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/auth/auth_providers.dart';
import 'package:cashdeck/features/auth/domain/account.dart';
import 'package:cashdeck/features/auth/presentation/account_providers.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The first screen on a new server: creates the administrator, or signs in
/// when the server already has users.
class ServerSignUpScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(serverInfoProvider);
    return Scaffold(
      appBar: AppBar(),
      body: switch (server) {
        AsyncData(:final value) => _AccountForm(server: value),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(serverInfoProvider),
        ),
        _ => const CdSkeleton(rows: 3),
      },
    );
  }
}

class _AccountForm extends ConsumerStatefulWidget {
  const new({required this.server});

  final ServerInfo server;

  @override
  ConsumerState<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<_AccountForm> {
  var _name = '';
  var _email = '';
  var _password = '';
  var _confirmation = '';
  var _submitted = false;
  var _sending = false;
  String? _failure;

  bool get _signIn => widget.server.hasUsers;

  Set<SignUpField> get _errors => signUpErrorsOf(
    name: _signIn ? '-' : _name,
    email: _email,
    password: _password,
    confirmation: _signIn ? _password : _confirmation,
  );

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (_errors.isNotEmpty) return;
    setState(() => _sending = true);
    final l10n = AppLocalizations.of(context);
    final result = _signIn
        ? await ref
              .read(accountRepositoryProvider)
              .signIn(email: _email, password: _password)
        : await ref
              .read(signUpProvider)
              .call(
                name: _name,
                email: _email,
                password: _password,
                confirmation: _confirmation,
              );
    if (!mounted) return;
    setState(() => _sending = false);
    switch (result) {
      case Ok():
        context.go(AppRoutes.home);
      case Err(:final failure):
        setState(() => _failure = failure.userMessage(l10n));
    }
  }

  String? _errorFor(SignUpField field, String message) =>
      _submitted && _errors.contains(field) ? message : null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final strength = passwordStrengthOf(_password);
    final failure = _failure;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: palette.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.dns_rounded,
                  size: 16,
                  color: palette.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  widget.server.host,
                  style: AppTextStyles.labelMd.copyWith(
                    color: palette.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          _signIn ? l10n.signInTitle : l10n.signUpTitle,
          style: AppTextStyles.headlineMd.copyWith(color: palette.onSurface),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _signIn ? l10n.signInBody : l10n.signUpBody,
          style: AppTextStyles.bodyMd.copyWith(color: palette.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (!_signIn) ...[
          CdTextField(
            key: const Key('sign-up-name'),
            label: l10n.fieldName,
            autofillHints: const [AutofillHints.name],
            textInputAction: TextInputAction.next,
            errorText: _errorFor(SignUpField.name, l10n.errorNameRequired),
            onChanged: (value) => setState(() => _name = value),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        CdTextField(
          key: const Key('sign-up-email'),
          label: l10n.fieldEmail,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          errorText: _errorFor(SignUpField.email, l10n.errorEmailInvalid),
          onChanged: (value) => setState(() => _email = value),
        ),
        const SizedBox(height: AppSpacing.md),
        CdTextField(
          key: const Key('sign-up-password'),
          label: l10n.fieldPassword,
          secret: true,
          autofillHints: [
            if (_signIn) AutofillHints.password,
            if (!_signIn) AutofillHints.newPassword,
          ],
          errorText: _errorFor(SignUpField.password, l10n.errorPasswordWeak),
          onChanged: (value) => setState(() => _password = value),
        ),
        if (!_signIn && _password.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _StrengthMeter(strength: strength, length: _password.length),
        ],
        if (!_signIn) ...[
          const SizedBox(height: AppSpacing.md),
          CdTextField(
            key: const Key('sign-up-confirmation'),
            label: l10n.fieldConfirmPassword,
            secret: true,
            valid: _confirmation.isNotEmpty && _confirmation == _password,
            errorText: _errorFor(
              SignUpField.confirmation,
              l10n.errorPasswordMismatch,
            ),
            onChanged: (value) => setState(() => _confirmation = value),
          ),
        ],
        if (failure != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            failure,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: const Key('sign-up-submit'),
          expand: true,
          loading: _sending,
          label: _signIn ? l10n.signInButton : l10n.signUpButton,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  const new({required this.strength, required this.length});

  final PasswordStrength strength;
  final int length;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final (tone, label, filled) = switch (strength) {
      PasswordStrength.weak => (MoneyTone.failed, l10n.passwordWeak, 1),
      PasswordStrength.fair => (MoneyTone.pending, l10n.passwordFair, 2),
      PasswordStrength.strong => (MoneyTone.paid, l10n.passwordStrong, 3),
    };
    final colors = context.tone(tone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var bar = 0; bar < 4; bar++) ...[
              if (bar > 0) const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: bar < filled
                        ? colors.foreground
                        : palette.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Icon(
              strength == PasswordStrength.strong
                  ? Symbols.check_circle_rounded
                  : Symbols.info_rounded,
              size: 16,
              color: colors.foreground,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              l10n.passwordStrengthLine(label, length),
              style: AppTextStyles.bodyMd.copyWith(color: colors.foreground),
            ),
          ],
        ),
      ],
    );
  }
}
