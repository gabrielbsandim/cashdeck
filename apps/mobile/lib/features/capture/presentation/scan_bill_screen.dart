import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/scan/code_scanner.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/features/capture/capture_providers.dart';
import 'package:cashdeck/features/capture/domain/scanned_code.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Points the camera at a bill: the Pix QR or the boleto barcode, whichever
/// it finds first. The server prefers the Pix when a bill has both.
class ScanBillScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ScanBillScreen> createState() => _ScanBillScreenState();
}

class _ScanBillScreenState extends ConsumerState<ScanBillScreen> {
  var _sending = false;

  Future<void> _read(String raw) async {
    if (_sending) return;
    final l10n = AppLocalizations.of(context);
    final code = classifyScannedCode(raw);
    if (code == null) {
      await showCdToast(
        context,
        icon: Symbols.error_rounded,
        message: l10n.scanUnknownCode,
      );
      return;
    }
    setState(() => _sending = true);
    final owner = switch (ref.read(entityScopeProvider)) {
      EntityScope.company => EntityKind.company,
      EntityScope.personal || EntityScope.consolidated => EntityKind.personal,
    };
    final result = await ref
        .read(captureRepositoryProvider)
        .submitCode(code, owner);
    if (!mounted) return;
    setState(() => _sending = false);
    final failure = switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    };
    if (failure == null) context.go(AppRoutes.bills);
    await showOutcomeToast(
      context,
      failure,
      success: switch (code.kind) {
        ScannedKind.pix => l10n.scanPixRead,
        ScannedKind.boleto => l10n.scanBoletoRead,
        ScannedKind.taxGuide => l10n.scanTaxRead,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanTitle)),
      body: Column(
        children: [
          Expanded(child: ref.watch(codeScannerProvider)(context, _read)),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: _sending
                ? const LinearProgressIndicator()
                : Text(
                    l10n.scanHint,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
