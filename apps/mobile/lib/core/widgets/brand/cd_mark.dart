import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// Two cards in a deck, the back one at 45%, a coin on the front card.
/// Three rounded rectangles and a circle, so it survives 24 dp and a single
/// color notification icon.
class CdMark extends StatelessWidget {
  const new({this.size = 48, this.mono = false, super.key});

  final double size;

  /// A transparent tile with the cards in onSurface.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: 'Cashdeck',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: CdMarkPainter(
            tile: mono ? null : palette.primary,
            card: mono ? palette.onSurface : palette.onPrimary,
          ),
        ),
      ),
    );
  }
}

class CdMarkPainter extends CustomPainter {
  const new({required this.tile, required this.card});

  final Color? tile;
  final Color card;

  RRect _card(Size size, double left, double top) {
    final width = size.width * 0.54;
    final height = size.height * 0.36;
    return RRect.fromRectXY(
      Rect.fromLTWH(size.width * left, size.height * top, width, height),
      width * 0.16,
      height * 0.24,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final tile = this.tile;
    canvas.saveLayer(Offset.zero & size, Paint());
    if (tile != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.width * 0.28),
        ),
        Paint()..color = tile,
      );
    }
    final front = _card(size, 0.18, 0.38);
    canvas
      ..drawRRect(
        _card(size, 0.28, 0.20),
        Paint()..color = card.withValues(alpha: 0.45),
      )
      ..drawRRect(front, Paint()..color = card);
    final coin = Rect.fromLTWH(
      front.left + front.width * 0.14,
      front.bottom - front.height * 0.20 - front.height * 0.27,
      front.width * 0.18,
      front.height * 0.27,
    );
    final coinPaint = tile == null
        ? (Paint()..blendMode = BlendMode.clear)
        : (Paint()..color = tile);
    canvas
      ..drawOval(coin, coinPaint)
      ..restore();
  }

  @override
  bool shouldRepaint(CdMarkPainter oldDelegate) =>
      oldDelegate.tile != tile || oldDelegate.card != card;
}

/// Cash in 600, deck in 400, tracked tight.
class CdWordmark extends StatelessWidget {
  const new({this.fontSize = 32, super.key});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: fontSize,
      letterSpacing: -0.03 * fontSize,
      color: context.palette.onSurface,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Cash',
            style: style.copyWith(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: 'deck',
            style: style.copyWith(fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }
}
