import 'package:cashdeck/core/scan/code_scanner.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The device camera, reading the Pix QR and the boleto barcode (ITF).
Widget cameraCodeScanner(BuildContext context, ValueChanged<String> onCode) =>
    _CameraScanner(onCode: onCode);

const CodeScannerBuilder cameraScanner = cameraCodeScanner;

class _CameraScanner extends StatefulWidget {
  const new({required this.onCode});

  final ValueChanged<String> onCode;

  @override
  State<_CameraScanner> createState() => _CameraScannerState();
}

class _CameraScannerState extends State<_CameraScanner> {
  final _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.itf2of5,
      BarcodeFormat.itf14,
    ],
  );
  var _done = false;

  @override
  void dispose() {
    _controller.dispose().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MobileScanner(
    controller: _controller,
    onDetect: (capture) {
      final raw = capture.barcodes.firstOrNull?.rawValue;
      if (_done || raw == null) return;
      _done = true;
      widget.onCode(raw);
    },
  );
}
