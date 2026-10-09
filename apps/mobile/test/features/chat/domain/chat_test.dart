import 'dart:typed_data';

import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';

LocalFile _file(String name, [int size = 10]) =>
    LocalFile(name: name, bytes: Uint8List(size));

void main() {
  test('a draft names the first rule it breaks', () {
    expect(const ChatDraft().problem, DraftProblem.empty);
    expect(const ChatDraft(text: '   ').problem, DraftProblem.empty);
    expect(const ChatDraft(text: 'Oi').problem, isNull);
    expect(
      ChatDraft(text: 'a' * (ChatDraft.maxText + 1)).problem,
      DraftProblem.tooLong,
    );
    expect(
      ChatDraft(
        files: [_file('a.pdf'), _file('b.pdf'), _file('c.pdf'), _file('d.pdf')],
      ).problem,
      DraftProblem.tooManyFiles,
    );
    expect(
      ChatDraft(files: [_file('a.pdf', ChatDraft.maxBytes + 1)]).problem,
      DraftProblem.tooLarge,
    );
    expect(
      ChatDraft(files: [_file('a.zip')]).problem,
      DraftProblem.unsupportedFile,
    );
    expect(ChatDraft(files: [_file('voz.m4a')]).problem, isNull);
    expect(const ChatDraft(text: 'x').props, hasLength(2));
  });

  test('a message swaps one action and keeps the rest', () {
    final pending = testAction();
    final other = testAction(id: 'action-2');
    final message = testMessage(
      actions: [pending, other],
      attachments: const [
        ChatAttachment(
          id: 'att',
          fileName: 'boleto.pdf',
          mimeType: 'application/pdf',
          size: 10,
        ),
      ],
      notice: ChatNotice.empty,
    );
    final confirmed = testAction(status: ChatActionStatus.confirmed);

    final updated = message.withAction(confirmed);

    expect(updated.actions, [confirmed, other]);
    expect(updated.attachments, message.attachments);
    expect(updated.notice, ChatNotice.empty);
    expect(pending.isPending, isTrue);
    expect(confirmed.isPending, isFalse);
    expect(message.props, hasLength(8));
    expect(message.attachments.first.props, hasLength(4));
  });

  test('value classes compare by value', () {
    expect(testThread().props, hasLength(5));
    expect(testAction().props, hasLength(10));
    expect(testAction().details.props, hasLength(7));
    expect(const ChatActionResult(billId: 'b', updated: 2).props, hasLength(4));
  });
}
