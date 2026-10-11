import 'package:cashdeck/features/chat/presentation/chat_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/pump_app.dart';

const _answer = r'''
## Resumo do **mês**
Entraram R$ 6.500,00 e saíram *R$ 4.120,00*.
Sobrou __pouco__.

- moradia
* mercado com _desconto_
1. pagar a luz
2) pagar a água

Um 2*3*4 e snake_case_name ficam como estão.''';

void main() {
  test('reads headings, lists, paragraphs and emphasis', () {
    final blocks = parseMarkdown(_answer);

    expect(blocks.map((block) => block.kind), [
      MarkdownBlockKind.heading,
      MarkdownBlockKind.paragraph,
      MarkdownBlockKind.bullet,
      MarkdownBlockKind.bullet,
      MarkdownBlockKind.numbered,
      MarkdownBlockKind.numbered,
      MarkdownBlockKind.paragraph,
    ]);
    expect(blocks[0].runs, const [
      InlineRun('Resumo do mês', InlineStyle.bold),
    ]);
    expect(blocks[1].runs, const [
      InlineRun(r'Entraram R$ 6.500,00 e saíram '),
      InlineRun(r'R$ 4.120,00', InlineStyle.italic),
      InlineRun('.\nSobrou '),
      InlineRun('pouco', InlineStyle.bold),
      InlineRun('.'),
    ]);
    expect(
      blocks[3].runs.last,
      const InlineRun('desconto', InlineStyle.italic),
    );
    expect(blocks[4].marker, '1.');
    expect(blocks[5].marker, '2.');
    expect(blocks[6].runs, const [
      InlineRun('Um 2*3*4 e snake_case_name ficam como estão.'),
    ]);
    expect(blocks.first.props, hasLength(3));
    expect(blocks.first.runs.first.props, hasLength(2));
  });

  testWidgets('renders each block with its marker', (tester) async {
    await tester.pumpApp(
      const ChatMarkdown(text: _answer, style: TextStyle(fontSize: 14)),
    );

    expect(find.text('Resumo do mês'), findsOneWidget);
    expect(find.text('•'), findsNWidgets(2));
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.textContaining('pagar a água'), findsOneWidget);
  });
}
