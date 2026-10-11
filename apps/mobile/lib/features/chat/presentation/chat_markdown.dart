import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

enum MarkdownBlockKind { paragraph, heading, bullet, numbered }

enum InlineStyle { plain, bold, italic }

final class InlineRun extends Equatable {
  const new(this.text, [this.style = InlineStyle.plain]);

  final String text;
  final InlineStyle style;

  @override
  List<Object?> get props => [text, style];
}

final class MarkdownBlock extends Equatable {
  const new(this.kind, this.runs, {this.marker = ''});

  final MarkdownBlockKind kind;
  final List<InlineRun> runs;

  /// "1." for a numbered item; empty otherwise.
  final String marker;

  @override
  List<Object?> get props => [kind, runs, marker];
}

final _bullet = RegExp(r'^\s*[-*•]\s+(.*)$');
final _numbered = RegExp(r'^\s*(\d{1,3})[.)]\s+(.*)$');
final _heading = RegExp(r'^\s*#{1,6}\s+(.*)$');
final _inline = RegExp(
  r'\*\*(.+?)\*\*|__(.+?)__|(?<![\w*])\*(?!\s)([^*]+?)(?<!\s)\*(?![\w*])'
  r'|(?<![\w_])_(?!\s)([^_]+?)(?<!\s)_(?![\w_])',
);

/// The few markdown pieces the assistant uses: headings, lists, bold and
/// italic. Anything else stays as written.
List<MarkdownBlock> parseMarkdown(String text) {
  final blocks = <MarkdownBlock>[];
  final paragraph = <String>[];
  void flush() {
    if (paragraph.isEmpty) return;
    blocks.add(
      MarkdownBlock(
        MarkdownBlockKind.paragraph,
        parseInline(paragraph.join('\n')),
      ),
    );
    paragraph.clear();
  }

  for (final line in text.trim().split('\n')) {
    final block = _lineBlock(line);
    if (block != null) {
      flush();
      blocks.add(block);
      continue;
    }
    if (line.trim().isEmpty) {
      flush();
      continue;
    }
    paragraph.add(line.trimRight());
  }
  flush();
  return blocks;
}

MarkdownBlock? _lineBlock(String line) {
  final heading = _heading.firstMatch(line);
  if (heading != null) {
    return MarkdownBlock(MarkdownBlockKind.heading, [
      InlineRun(_stripMarks(heading.group(1)!), InlineStyle.bold),
    ]);
  }
  final bullet = _bullet.firstMatch(line);
  if (bullet != null) {
    return MarkdownBlock(
      MarkdownBlockKind.bullet,
      parseInline(bullet.group(1)!),
    );
  }
  final numbered = _numbered.firstMatch(line);
  if (numbered == null) return null;
  return MarkdownBlock(
    MarkdownBlockKind.numbered,
    parseInline(numbered.group(2)!),
    marker: '${numbered.group(1)}.',
  );
}

String _stripMarks(String text) =>
    parseInline(text).map((run) => run.text).join();

List<InlineRun> parseInline(String text) {
  final runs = <InlineRun>[];
  var at = 0;
  for (final match in _inline.allMatches(text)) {
    if (match.start > at) runs.add(InlineRun(text.substring(at, match.start)));
    final bold = match.group(1) ?? match.group(2);
    final italic = match.group(3) ?? match.group(4);
    runs.add(
      bold == null
          ? InlineRun(italic!, InlineStyle.italic)
          : InlineRun(bold, InlineStyle.bold),
    );
    at = match.end;
  }
  if (at < text.length) runs.add(InlineRun(text.substring(at)));
  return runs;
}

/// Renders [text] with [parseMarkdown] in [style].
class ChatMarkdown extends StatelessWidget {
  const new({required this.text, required this.style, super.key});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final blocks = parseMarkdown(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, block) in blocks.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : _gapBefore(block)),
            child: _block(block),
          ),
      ],
    );
  }

  double _gapBefore(MarkdownBlock block) => switch (block.kind) {
    MarkdownBlockKind.bullet || MarkdownBlockKind.numbered => AppSpacing.xs,
    MarkdownBlockKind.heading || MarkdownBlockKind.paragraph => AppSpacing.sm,
  };

  Widget _block(MarkdownBlock block) {
    final body = Text.rich(TextSpan(children: _spans(block.runs)));
    return switch (block.kind) {
      MarkdownBlockKind.paragraph || MarkdownBlockKind.heading => body,
      MarkdownBlockKind.bullet => _item('•', body),
      MarkdownBlockKind.numbered => _item(block.marker, body),
    };
  }

  Widget _item(String marker, Widget body) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: AppSpacing.xl,
        child: Text(marker, style: style),
      ),
      Expanded(child: body),
    ],
  );

  List<InlineSpan> _spans(List<InlineRun> runs) => [
    for (final run in runs)
      TextSpan(
        text: run.text,
        style: switch (run.style) {
          InlineStyle.plain => style,
          InlineStyle.bold => style.copyWith(fontWeight: FontWeight.w600),
          InlineStyle.italic => style.copyWith(fontStyle: FontStyle.italic),
        },
      ),
  ];
}
