import 'package:cashdeck/features/chat/domain/mentions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds the @token the cursor is typing', () {
    expect(
      mentionAt('Pix para @mar', 13),
      const MentionQuery(start: 9, query: 'mar'),
    );
    expect(mentionAt('@', 1), const MentionQuery(start: 0, query: ''));
    expect(mentionAt('para @joão', 10)?.query, 'joão');
    expect(mentionAt('Pix para @mar', 9), isNull);
    expect(mentionAt('email@exemplo', 13), isNull);
    expect(mentionAt('sem arroba', 10), isNull);
    expect(mentionAt('', 0), isNull);
    expect(mentionAt('abc', 9), isNull);
    expect(mentionAt('@${'a' * 31}', 32), isNull);
    expect(const MentionQuery(start: 0, query: 'a').props, hasLength(2));
  });

  test('completes the mention and moves the cursor past it', () {
    const text = r'Pix para @mar de R$ 50';
    final mention = mentionAt(text, 13)!;

    final (next, cursor) = insertMention(text, mention, 13, 'marina');

    expect(next, r'Pix para @marina de R$ 50');
    expect(cursor, 'Pix para @marina '.length);
    expect(insertMention('@', mentionAt('@', 1)!, 1, 'ana'), ('@ana ', 5));
  });

  test('cuts a text into plain runs and mentions', () {
    expect(splitMentions('Pix para @marina e @joao.f hoje'), [
      ('Pix para ', false),
      ('@marina', true),
      (' e ', false),
      ('@joao.f', true),
      (' hoje', false),
    ]);
    expect(splitMentions('@ana'), [('@ana', true)]);
    expect(splitMentions('ana@exemplo.com'), [('ana@exemplo.com', false)]);
  });
}
