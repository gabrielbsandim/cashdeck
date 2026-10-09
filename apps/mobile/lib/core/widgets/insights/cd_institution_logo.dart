import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// A bank in a circle: its logo from the connector when there is one, its
/// monogram on the series tint otherwise, and while the logo loads.
class CdInstitutionLogo extends StatelessWidget {
  const new({
    required this.name,
    required this.colors,
    this.imageUrl,
    this.size = 40,
    super.key,
  });

  final String name;
  final SeriesColors colors;
  final String? imageUrl;
  final double size;

  static const _noise = {'banco', 'bank', 'de', 'do', 'da', 'sa', 's.a.'};

  /// Up to two letters from the first meaningful words: `Banco Aurora` is
  /// `BA`, `Nuvem Pagamentos` is `NP`.
  static String monogram(String name) {
    final words = name
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final meaningful = words
        .where((word) => !_noise.contains(word.toLowerCase()))
        .toList();
    final picked = switch ((words.length, meaningful.length)) {
      (0, _) => const <String>[],
      (1, _) => [words.first],
      (_, 1) => [words.first, meaningful.first],
      (_, 0) => words.take(2).toList(),
      _ => meaningful.take(2).toList(),
    };
    if (picked.length == 1) {
      final word = picked.first;
      return word.substring(0, word.length < 2 ? word.length : 2).toUpperCase();
    }
    return picked.map((word) => word[0]).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.container,
        shape: BoxShape.circle,
      ),
      child: Text(
        monogram(name),
        style: TextStyle(
          fontSize: (size * 0.33).roundToDouble(),
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: colors.foreground,
        ),
      ),
    );
    final url = imageUrl;
    if (url == null) return Semantics(label: name, child: fallback);
    return Semantics(
      label: name,
      child: ClipOval(
        child: Container(
          width: size,
          height: size,
          color: context.palette.surfaceContainerLowest,
          child: Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            frameBuilder: (_, child, frame, synchronous) =>
                frame == null && !synchronous ? fallback : child,
            errorBuilder: (_, _, _) => fallback,
          ),
        ),
      ),
    );
  }
}
