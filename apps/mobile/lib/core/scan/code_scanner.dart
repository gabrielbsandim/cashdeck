import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Builds the camera preview that reads a QR code or a barcode and hands the
/// raw text to [onCode]; main swaps in the device camera.
typedef CodeScannerBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onCode,
);

/// What the fake backend shows instead of a camera: a tile that reads
/// [sample] when tapped.
CodeScannerBuilder fakeCodeScanner(String sample) =>
    (context, onCode) => GestureDetector(
      key: fakeScannerKey,
      onTap: () => onCode(sample),
      child: const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Icon(Icons.qr_code_scanner, size: 96, color: Colors.white),
        ),
      ),
    );

const fakeScannerKey = Key('fake-code-scanner');

/// A fictional bolepix Pix payload, the code the fake camera reads.
const sampleScannedCode =
    '00020101021226880014br.gov.bcb.pix2566pix.exemplo.com.br/qr/v2/cobv/'
    '5f0c2a8e-61b2-4c1d-9a7e-3d2b8c1e4f505204000053039865406287'
    '.405802BR5914ENERGIA LUMINA6013FLORIANOPOLIS62070503***63046AD7';

final codeScannerProvider = Provider<CodeScannerBuilder>(
  (ref) => fakeCodeScanner(sampleScannedCode),
);
