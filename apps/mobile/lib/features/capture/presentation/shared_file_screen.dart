import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_inline_banner.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/features/capture/capture_providers.dart';
import 'package:cashdeck/features/capture/domain/bill_draft.dart';
import 'package:cashdeck/features/capture/presentation/capture_details_sheet.dart';
import 'package:cashdeck/features/capture/presentation/capture_flow.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

/// A PDF or photo another app shared in: the user says whose bill it is and
/// the server reads it.
class SharedFileScreen extends ConsumerStatefulWidget {
  const new({required this.file, super.key});

  static const sendKey = Key('shared-file-send');
  static const pasteKey = Key('shared-file-paste');

  final LocalFile file;

  @override
  ConsumerState<SharedFileScreen> createState() => _SharedFileScreenState();
}

class _SharedFileScreenState extends ConsumerState<SharedFileScreen> {
  late EntityKind _owner = defaultOwner(ref);
  var _sending = false;
  CaptureOutcome? _problem;

  /// A PDF is sent as is, so one over the cap is refused before sending;
  /// a photo is shrunk first and only fails if it still does not fit.
  late final bool _pdfTooLarge =
      widget.file.extension == 'pdf' &&
      widget.file.bytes.length > maxUploadBytes;

  Future<void> _send({CaptureDetails? details}) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _sending = true);
    final result = await ref
        .read(captureRepositoryProvider)
        .submitFile(
          widget.file,
          _owner,
          amount: details?.amount,
          dueDate: details?.dueDate,
        );
    if (!mounted) return;
    setState(() => _sending = false);
    switch (result) {
      case Ok(value: CaptureDetailsNeeded(:final amount)):
        await _askDetails(askAmount: amount);
      case Ok(value: BillCaptured(:final duplicate)):
        context.go(AppRoutes.bills);
        await showOutcomeToast(
          context,
          null,
          success: duplicate
              ? l10n.captureDuplicateToast
              : l10n.sharedFileSentToast,
        );
      case Ok(:final value):
        setState(() => _problem = value);
      case Err(:final failure):
        await showOutcomeToast(context, failure, success: '');
    }
  }

  /// The server read a code without an amount; the same file goes again
  /// with what the user fills in. Closing the sheet keeps the screen.
  Future<void> _askDetails({required bool askAmount}) async {
    final details = await showCaptureDetailsSheet(
      context,
      askAmount: askAmount,
      today: CalendarDate.brazilToday(ref.read(clockProvider).now()),
    );
    if (details == null || !mounted) return;
    await _send(details: details);
  }

  String? _problemMessage(AppLocalizations l10n) {
    final tooLarge = l10n.sharedFileTooLarge(
      l10n.fileSizeMb(_megabytes(widget.file.bytes.length, l10n.localeName)),
      l10n.fileSizeMb(_megabytes(maxUploadBytes, l10n.localeName)),
    );
    if (_pdfTooLarge) return tooLarge;
    return switch (_problem) {
      CaptureFileTooLarge() => tooLarge,
      CaptureNothingFound() => l10n.sharedFileNothingFound,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final kilobytes = (widget.file.bytes.length / 1024).ceil();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.sharedFileTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        children: [
          CdCard(
            child: Row(
              children: [
                CdIconTile(
                  widget.file.extension == 'pdf'
                      ? Symbols.picture_as_pdf_rounded
                      : Symbols.image_rounded,
                  circle: false,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.file.name,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelLg.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                      Text(
                        l10n.fileSizeKb(kilobytes),
                        style: AppTextStyles.bodyMd.copyWith(
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_problemMessage(l10n) case final message?) ...[
            const SizedBox(height: AppSpacing.md),
            CdInlineBanner(
              icon: Symbols.error_rounded,
              tone: MoneyTone.failed,
              message: message,
              actionLabel: l10n.pasteCodeButton,
              actionKey: SharedFileScreen.pasteKey,
              onAction: () => context.push(AppRoutes.pasteCode).ignore(),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.sharedFileBody,
            style: AppTextStyles.bodyMd.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          CdSegmented<EntityKind>(
            segments: [
              CdSegment(EntityKind.personal, l10n.entityPersonal),
              CdSegment(EntityKind.company, l10n.entityCompany),
            ],
            selected: _owner,
            onChanged: (owner) => setState(() => _owner = owner),
          ),
          const SizedBox(height: AppSpacing.xl),
          CdButton.filled(
            key: SharedFileScreen.sendKey,
            expand: true,
            loading: _sending,
            icon: Symbols.send_rounded,
            label: l10n.sharedFileSend,
            onPressed: _pdfTooLarge ? null : _send,
          ),
        ],
      ),
    );
  }
}

String _megabytes(int bytes, String locale) =>
    NumberFormat('0.0', locale).format(bytes / 1000000);
