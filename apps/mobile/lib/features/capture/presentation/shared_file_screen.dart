import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/features/capture/capture_providers.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// A PDF or photo another app shared in: the user says whose bill it is and
/// the server reads it.
class SharedFileScreen extends ConsumerStatefulWidget {
  const new({required this.file, super.key});

  static const sendKey = Key('shared-file-send');

  final LocalFile file;

  @override
  ConsumerState<SharedFileScreen> createState() => _SharedFileScreenState();
}

class _SharedFileScreenState extends ConsumerState<SharedFileScreen> {
  late EntityKind _owner = switch (ref.read(entityScopeProvider)) {
    EntityScope.company => EntityKind.company,
    EntityScope.personal || EntityScope.consolidated => EntityKind.personal,
  };
  var _sending = false;

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _sending = true);
    final result = await ref
        .read(captureRepositoryProvider)
        .submitFile(widget.file, _owner);
    if (!mounted) return;
    setState(() => _sending = false);
    final failure = switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    };
    if (failure == null) context.go(AppRoutes.bills);
    await showOutcomeToast(context, failure, success: l10n.sharedFileSentToast);
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
            onPressed: _send,
          ),
        ],
      ),
    );
  }
}
