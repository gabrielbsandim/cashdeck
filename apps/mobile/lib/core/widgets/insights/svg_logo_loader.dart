import 'dart:typed_data';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart';

final _rule = RegExp(r'([^{}]+)\{([^{}]*)\}');
final _classSelector = RegExp(r'^\.([\w-]+)$');
final _spaces = RegExp(r'\s+');

String _declarations(Iterable<String> blocks) => blocks
    .expand((block) => block.split(';'))
    .map((declaration) => declaration.trim())
    .where((declaration) => declaration.isNotEmpty)
    .join(';');

Map<String, List<String>> _classRules(XmlDocument document) {
  final rules = <String, List<String>>{};
  for (final style in document.findAllElements('style').toList()) {
    for (final match in _rule.allMatches(style.innerText)) {
      final body = match.group(2) ?? '';
      for (final selector in (match.group(1) ?? '').split(',')) {
        final name = _classSelector.firstMatch(selector.trim())?.group(1);
        if (name == null) continue;
        rules.putIfAbsent(name, () => []).add(body);
      }
    }
    style.remove();
  }
  return rules;
}

/// flutter_svg skips `<style>`, so each class rule is copied onto the
/// elements that name it, ahead of their own `style`, which still wins.
String inlineClassStyles(String svg) {
  if (!svg.contains('<style')) return svg;
  final XmlDocument document;
  try {
    document = XmlDocument.parse(svg);
  } on XmlException {
    return svg;
  }
  final rules = _classRules(document);
  for (final element in document.descendantElements) {
    final classes = element.getAttribute('class');
    if (classes == null) continue;
    final style = _declarations([
      for (final name in classes.split(_spaces)) ...?rules[name],
      ?element.getAttribute('style'),
    ]);
    element
      ..removeAttribute('class')
      ..setAttribute('style', style.isEmpty ? null : style);
  }
  return document.toXmlString();
}

/// A connector logo over the network, with its class styles inlined.
final class SvgLogoLoader extends SvgNetworkLoader {
  const new(super.url, {super.httpClient});

  @override
  String provideSvg(Uint8List? message) =>
      inlineClassStyles(super.provideSvg(message));
}
