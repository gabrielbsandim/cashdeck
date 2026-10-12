import 'dart:typed_data';

import 'package:cashdeck/core/error/app_failure.dart';
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

  test('only paying a bill and sending a Pix move money', () {
    expect(
      {
        for (final tool in ChatTool.values)
          if (tool.movesMoney) tool,
      },
      {ChatTool.payBill, ChatTool.sendPix},
    );
  });

  test('value classes compare by value', () {
    expect(testThread().props, hasLength(5));
    expect(testAction().props, hasLength(10));
    expect(testAction().details.props, hasLength(11));
    expect(const ChatActionResult(billId: 'b', updated: 2).props, hasLength(5));
  });

  test('only an answer that stopped short can be retried', () {
    expect(testMessage(notice: ChatNotice.error).canRetry, isTrue);
    expect(testMessage().canRetry, isFalse);
    expect(
      testMessage(role: ChatRole.user, notice: ChatNotice.error).canRetry,
      isFalse,
    );
    expect(testMessage(role: ChatRole.user).isMine, isTrue);
  });

  test('an outgoing message fails, goes again and names its files', () {
    final outgoing = OutgoingMessage(
      clientId: 'c1',
      text: 'Oi',
      createdAt: testNow,
      files: [_file('a.pdf')],
      attachments: const [
        ChatAttachment(
          id: 'att',
          fileName: 'b.pdf',
          mimeType: 'application/pdf',
          size: 1,
        ),
      ],
      editOf: 'msg-1',
    );

    final failed = outgoing.failedWith(const NetworkFailure());
    final again = failed.sending();

    expect(outgoing.failed, isFalse);
    expect(failed.failed, isTrue);
    expect(failed.failure, const NetworkFailure());
    expect(again, outgoing);
    expect(again.editOf, 'msg-1');
    expect(outgoing.fileNames, ['a.pdf', 'b.pdf']);
    expect(outgoing.props, hasLength(8));
  });
}
