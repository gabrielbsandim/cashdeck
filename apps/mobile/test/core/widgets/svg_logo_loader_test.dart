import 'package:cashdeck/core/widgets/insights/svg_logo_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copies class rules onto the elements and drops the style sheet', () {
    final svg = [
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">',
      '<defs><style>.a{fill:none;}.b, .c {fill:#cc092f; stroke:#000}',
      'rect{opacity:.5}</style></defs>',
      '<rect class="a" width="10" height="10"/>',
      '<path class="b  c" style="opacity:1" d="M0 0h1"/>',
      '<path class="unknown" d="M0 0h2"/>',
      '</svg>',
    ].join(' ');

    final inlined = inlineClassStyles(svg);

    expect(inlined, isNot(contains('<style')));
    expect(inlined, isNot(contains('class=')));
    expect(
      inlined,
      contains('<rect width="10" height="10" style="fill:none"/>'),
    );
    expect(
      inlined,
      contains(
        'style="fill:#cc092f;stroke:#000;fill:#cc092f;stroke:#000;opacity:1"',
      ),
    );
    expect(inlined, contains('<path d="M0 0h2"/>'));
  });

  test('leaves an SVG without a style sheet or one that does not parse', () {
    const plain = '<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>';
    const broken = '<svg><style>.a{fill:red}</style><rect class="a">';

    expect(inlineClassStyles(plain), plain);
    expect(inlineClassStyles(broken), broken);
  });
}
