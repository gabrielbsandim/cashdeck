import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/scan/code_scanner.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/features/capture/domain/bill_draft.dart';
import 'package:cashdeck/features/capture/domain/scanned_code.dart';
import 'package:cashdeck/features/capture/presentation/capture_flow.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Points the camera at a bill: the Pix QR or the boleto barcode, whichever
/// it finds first. The server prefers the Pix when a bill has both.
class ScanBillScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const pasteKey = Key('scan-paste');

  @override
  ConsumerState<ScanBillScreen> createState() => _ScanBillScreenState();
}

class _ScanBillScreenState extends ConsumerState<ScanBillScreen> {
  var _busy = false;
  var _sending = false;

  Future<void> _read(String raw) async {
    if (_busy) return;
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
    _busy = true;
    final result = await captureAsking(
      context,
      ref,
      BillDraft.fromScanned(code, defaultOwner(ref)),
      onSending: (sending) => setState(() => _sending = sending),
    );
    _busy = false;
    if (!mounted || result == null) return;
    final (failure, duplicate) = switch (result) {
      Ok(value: BillCaptured(:final duplicate)) => (null, duplicate),
      Ok() => (null, false),
      Err(:final failure) => (failure, false),
    };
    if (failure == null) context.go(AppRoutes.bills);
    await showOutcomeToast(
      context,
      failure,
      success: switch ((duplicate, code.kind)) {
        (true, _) => l10n.captureDuplicateToast,
        (_, ScannedKind.pix) => l10n.scanPixRead,
        (_, ScannedKind.boleto) => l10n.scanBoletoRead,
        (_, ScannedKind.taxGuide) => l10n.scanTaxRead,
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
                : Column(
                    children: [
                      Text(
                        l10n.scanHint,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMd.copyWith(
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      CdButton.text(
                        key: ScanBillScreen.pasteKey,
                        icon: Symbols.content_paste_rounded,
                        label: l10n.pasteCodeButton,
                        onPressed: () =>
                            context.push(AppRoutes.pasteCode).ignore(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
