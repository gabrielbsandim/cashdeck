import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/bills/presentation/bill_labels.dart';
import 'package:cashdeck/features/entities/domain/entity_profile.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/domain/tax_id.dart';
import 'package:cashdeck/features/entities/entities_providers.dart';
import 'package:cashdeck/features/entities/presentation/entity_profiles_provider.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/features/entities/presentation/tax_id_input_formatter.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The person's and the company's name, tax id and, for the company, regime.
class EntityProfilesScreen extends ConsumerWidget {
  const new({super.key});

  static Key nameKey(EntityKind kind) => Key('profile-name-${kind.name}');

  static Key taxIdKey(EntityKind kind) => Key('profile-tax-id-${kind.name}');

  static Key saveKey(EntityKind kind) => Key('profile-save-${kind.name}');

  static const regimeKey = Key('profile-regime');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final profiles = ref.watch(entityProfilesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profilesTitle)),
      body: switch (profiles) {
        AsyncValue(:final value?) => ListView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          children: [
            Text(
              l10n.profilesIntro,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
            for (final profile in value) ...[
              const SizedBox(height: AppSpacing.lg),
              _ProfileCard(key: ValueKey(profile.id), profile: profile),
            ],
          ],
        ),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(entityProfilesProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

class _ProfileCard extends ConsumerStatefulWidget {
  const new({required this.profile, super.key});

  final EntityProfile profile;

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  late final _name = TextEditingController(text: widget.profile.name);
  late final _taxId = TextEditingController(
    text: TaxIds.format(widget.profile.kind, widget.profile.taxId),
  );
  late TaxRegime? _regime = widget.profile.taxRegime;
  String? _nameError;
  String? _taxIdError;
  var _saving = false;

  EntityKind get _kind => widget.profile.kind;

  @override
  void dispose() {
    _name.dispose();
    _taxId.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    final invalidTaxId = switch (_kind) {
      EntityKind.personal => l10n.profileCpfInvalid,
      EntityKind.company => l10n.profileCnpjInvalid,
    };
    final nameError = name.isEmpty ? l10n.profileNameRequired : null;
    final taxIdError = TaxIds.isValid(_kind, _taxId.text) ? null : invalidTaxId;
    final valid = nameError == null && taxIdError == null;
    setState(() {
      _nameError = nameError;
      _taxIdError = taxIdError;
      _saving = valid;
    });
    if (!valid) return;
    final result = await ref
        .read(entityProfileRepositoryProvider)
        .update(
          widget.profile.copyWith(
            name: name,
            taxId: TaxIds.clean(_kind, _taxId.text),
            taxRegime: _regime,
          ),
        );
    if (!mounted) return;
    final failure = switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    };
    setState(() {
      _saving = false;
      _taxIdError = switch (failure) {
        ValidationFailure() => failure.userMessage(l10n),
        _ => null,
      };
    });
    showOutcomeToast(
      context,
      failure,
      success: l10n.profileSavedToast,
    ).ignore();
    if (failure == null) ref.invalidate(entityProfilesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final profile = widget.profile;
    final regime = _regime;
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              EntityKindBadge(kind: _kind),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: AppTextStyles.titleSm.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                    Text(
                      entityKindLabel(l10n, _kind),
                      style: AppTextStyles.bodyMd.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          CdTextField(
            key: EntityProfilesScreen.nameKey(_kind),
            label: l10n.profileNameLabel,
            controller: _name,
            errorText: _nameError,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          CdTextField(
            key: EntityProfilesScreen.taxIdKey(_kind),
            label: switch (_kind) {
              EntityKind.personal => l10n.profileCpfLabel,
              EntityKind.company => l10n.profileCnpjLabel,
            },
            controller: _taxId,
            errorText: _taxIdError,
            monospace: true,
            keyboardType: switch (_kind) {
              EntityKind.personal => TextInputType.number,
              EntityKind.company => TextInputType.text,
            },
            inputFormatters: [TaxIdInputFormatter(_kind)],
          ),
          if (regime != null) ...[
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<TaxRegime>(
              key: EntityProfilesScreen.regimeKey,
              initialValue: regime,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.profileTaxRegimeLabel,
              ),
              items: [
                for (final option in TaxRegime.values)
                  DropdownMenuItem(
                    value: option,
                    child: Text(taxRegimeLabel(l10n, option)),
                  ),
              ],
              onChanged: (value) => setState(() => _regime = value ?? regime),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          CdButton.filled(
            key: EntityProfilesScreen.saveKey(_kind),
            expand: true,
            loading: _saving,
            label: l10n.profileSaveButton,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

String taxRegimeLabel(AppLocalizations l10n, TaxRegime regime) =>
    switch (regime) {
      TaxRegime.simplesNacional => l10n.taxRegimeSimplesNacional,
      TaxRegime.mei => l10n.taxRegimeMei,
      TaxRegime.lucroPresumido => l10n.taxRegimeLucroPresumido,
      TaxRegime.lucroReal => l10n.taxRegimeLucroReal,
    };
