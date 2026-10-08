import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/files/file_chooser.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/invoices/domain/issuer_setup.dart';
import 'package:cashdeck/features/invoices/invoices_providers.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

final FutureProvider<(IssuerSetup, List<ServiceCode>)> issuerFormProvider =
    FutureProvider.autoDispose<(IssuerSetup, List<ServiceCode>)>((ref) async {
      final repository = ref.watch(issuerRepositoryProvider);
      final setup = (await repository.setup()).orThrow;
      final codes = (await repository.serviceCodes()).orThrow;
      return (setup, codes);
    }, retry: noRetry);

/// Which issuer emits the company's invoices, its A1 certificate and the
/// defaults every invoice starts with.
class InvoiceIssuerSetupScreen extends ConsumerWidget {
  const new({super.key});

  static Key kindKey(IssuerKind kind) => Key('issuer-${kind.name}');
  static const testKey = Key('issuer-test');
  static const saveKey = Key('issuer-save');
  static const remindKey = Key('issuer-remind');
  static const uploadKey = Key('issuer-upload');
  static const serviceKey = Key('issuer-service');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final form = ref.watch(issuerFormProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.issuerTitle)),
      body: switch (form) {
        AsyncData(value: (final setup, final codes)) => _IssuerForm(
          initial: setup,
          codes: codes,
        ),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(issuerFormProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

class _IssuerForm extends ConsumerStatefulWidget {
  const new({required this.initial, required this.codes});

  final IssuerSetup initial;
  final List<ServiceCode> codes;

  @override
  ConsumerState<_IssuerForm> createState() => _IssuerFormState();
}

class _IssuerFormState extends ConsumerState<_IssuerForm> {
  late IssuerSetup _setup = widget.initial;
  var _remindLater = false;
  var _testing = false;
  var _saving = false;
  TestEmission? _test;

  Future<void> _emitTest() async {
    setState(() => _testing = true);
    final result = await ref.read(issuerRepositoryProvider).emitTest(_setup);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _test = switch (result) {
        Ok(:final value) => value,
        Err() => null,
      };
    });
  }

  Future<void> _upload() async {
    final l10n = AppLocalizations.of(context);
    final file = await ref.read(fileChooserProvider).choose(const [
      'pfx',
      'p12',
    ]);
    if (file == null || !mounted) return;
    final password = await showCdBottomSheet<String>(
      context,
      title: l10n.certificatePasswordTitle,
      builder: (_) => const _PasswordSheet(),
    );
    if (password == null || !mounted) return;
    final result = await ref
        .read(issuerRepositoryProvider)
        .uploadCertificate(file, password);
    if (!mounted) return;
    if (result case Ok(:final value)) {
      setState(() {
        _setup = value;
        _remindLater = false;
      });
    }
    await showOutcomeToast(context, switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    }, success: l10n.certificateUploadedToast(file.name));
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final result = await ref.read(issuerRepositoryProvider).save(_setup);
    if (!mounted) return;
    setState(() => _saving = false);
    await showOutcomeToast(context, switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    }, success: l10n.issuerSavedToast);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final today = CalendarDate.brazilToday(ref.watch(clockProvider).now());
    final test = _test;
    final options = [
      (
        IssuerKind.national,
        l10n.issuerNational,
        l10n.issuerNationalHint(_setup.city),
      ),
      (IssuerKind.municipal, l10n.issuerMunicipal, l10n.issuerMunicipalHint),
    ];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      children: [
        CdSectionHeader(title: l10n.issuerSection, small: true),
        const SizedBox(height: AppSpacing.sm),
        RadioGroup<IssuerKind>(
          groupValue: _setup.kind,
          onChanged: (kind) =>
              setState(() => _setup = _setup.copyWith(kind: kind)),
          child: Column(
            children: [
              for (final (kind, title, hint) in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: CdCard(
                    key: InvoiceIssuerSetupScreen.kindKey(kind),
                    selected: _setup.kind == kind,
                    padding: EdgeInsets.zero,
                    onTap: () =>
                        setState(() => _setup = _setup.copyWith(kind: kind)),
                    child: RadioListTile<IssuerKind>(
                      value: kind,
                      title: Text(title, style: AppTextStyles.titleSm),
                      subtitle: Text(hint, style: AppTextStyles.bodyMd),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _CertificateCard(
          setup: _setup,
          today: today,
          remindLater: _remindLater,
          onRemind: () => setState(() => _remindLater = true),
          onUpload: _upload,
        ),
        const SizedBox(height: AppSpacing.lg),
        CdTextField(
          label: l10n.municipalRegistration,
          initialValue: _setup.municipalRegistration,
          keyboardType: TextInputType.number,
          onChanged: (value) =>
              _setup = _setup.copyWith(municipalRegistration: value),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<ServiceCode>(
          key: InvoiceIssuerSetupScreen.serviceKey,
          initialValue: _setup.serviceCode,
          isExpanded: true,
          decoration: InputDecoration(labelText: l10n.serviceCodeLabel),
          items: [
            for (final code in widget.codes)
              DropdownMenuItem(
                value: code,
                child: Text(
                  '${code.code} · ${code.description}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (code) =>
              setState(() => _setup = _setup.copyWith(serviceCode: code)),
        ),
        const SizedBox(height: AppSpacing.lg),
        CdCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.testEmissionTitle,
                      style: AppTextStyles.titleSm.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                  ),
                  CdButton.tonal(
                    key: InvoiceIssuerSetupScreen.testKey,
                    dense: true,
                    loading: _testing,
                    label: l10n.emitTestButton,
                    onPressed: _emitTest,
                  ),
                ],
              ),
              if (test != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Symbols.check_circle_rounded,
                      size: 16,
                      color: context.money.paid,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        l10n.testEmissionResult(
                          test.protocol,
                          (test.elapsed.inMilliseconds / 1000)
                              .toStringAsFixed(1)
                              .replaceAll('.', ','),
                        ),
                        style: AppTextStyles.bodyMd.copyWith(
                          color: context.money.paid,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: InvoiceIssuerSetupScreen.saveKey,
          expand: true,
          loading: _saving,
          label: l10n.saveButton,
          onPressed: _save,
        ),
      ],
    );
  }
}

class _CertificateCard extends StatelessWidget {
  const new({
    required this.setup,
    required this.today,
    required this.remindLater,
    required this.onRemind,
    required this.onUpload,
  });

  final IssuerSetup setup;
  final CalendarDate today;
  final bool remindLater;
  final VoidCallback onRemind;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final state = certificateStateOf(setup.certificateExpiresOn, today);
    final days = today.daysUntil(setup.certificateExpiresOn);
    final date = setup.certificateExpiresOn.display;
    final (tone, label) = switch (state) {
      CertificateState.valid => (MoneyTone.paid, l10n.validUntil(date)),
      CertificateState.expiringSoon => (
        MoneyTone.pending,
        l10n.certificateExpiresIn(days, date),
      ),
      CertificateState.expired => (
        MoneyTone.failed,
        l10n.certificateExpired(date),
      ),
    };
    final urgent = state != CertificateState.valid && !remindLater;
    return CdCard(
      tone: urgent ? context.tone(tone) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Symbols.workspace_premium_rounded,
                color: context.tone(tone).foreground,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.certificateA1,
                      style: AppTextStyles.titleSm.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                    Text(
                      setup.certificateName,
                      style: AppTextStyles.code.copyWith(
                        fontSize: 13,
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    CdStatusBadge(
                      tone: tone,
                      label: label,
                      icon: Symbols.schedule_rounded,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (urgent) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                CdButton.filled(
                  key: InvoiceIssuerSetupScreen.uploadKey,
                  dense: true,
                  icon: Symbols.upload_rounded,
                  label: l10n.uploadNewButton,
                  onPressed: onUpload,
                ),
                CdButton.text(
                  key: InvoiceIssuerSetupScreen.remindKey,
                  dense: true,
                  label: l10n.remindLaterButton,
                  onPressed: onRemind,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PasswordSheet extends StatefulWidget {
  const new();

  static const fieldKey = Key('issuer-certificate-password');
  static const confirmKey = Key('issuer-certificate-confirm');

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  var _password = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdTextField(
          key: _PasswordSheet.fieldKey,
          label: l10n.pfxPasswordLabel,
          secret: true,
          onChanged: (value) => setState(() => _password = value),
        ),
        const SizedBox(height: AppSpacing.md),
        CdButton.filled(
          key: _PasswordSheet.confirmKey,
          expand: true,
          label: l10n.sendCertificateButton,
          onPressed: _password.isEmpty
              ? null
              : () => Navigator.of(context).pop(_password),
        ),
      ],
    );
  }
}
