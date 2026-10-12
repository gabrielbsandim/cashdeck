import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:equatable/equatable.dart';

enum ChatRole { user, assistant }

/// Why an answer stopped short; the app explains it in its own words.
enum ChatNotice { roundLimit, timeBudget, empty, error }

/// The tools with side effects, which wait for the user before they run.
enum ChatTool {
  createBillFromAttachment,
  payBill,
  createCategoryRule,
  draftInvoice,
  sendPix;

  /// Confirming these sends money out, so the device check comes first.
  bool get movesMoney => switch (this) {
    ChatTool.payBill || ChatTool.sendPix => true,
    ChatTool.createBillFromAttachment ||
    ChatTool.createCategoryRule ||
    ChatTool.draftInvoice => false,
  };
}

enum ChatActionStatus { pending, confirmed, cancelled, failed, expired }

final class ChatThread extends Equatable {
  const new({
    required this.id,
    required this.scope,
    required this.createdAt,
    required this.updatedAt,
    this.title,
  });

  final String id;

  /// The entity the assistant reads; the server never lets the model pick.
  final EntityScope scope;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  List<Object?> get props => [id, scope, title, createdAt, updatedAt];
}

final class ChatAttachment extends Equatable {
  const new({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.size,
  });

  final String id;
  final String fileName;
  final String mimeType;
  final int size;

  @override
  List<Object?> get props => [id, fileName, mimeType, size];
}

/// What a proposed action would do, for the confirmation card.
final class ChatActionDetails extends Equatable {
  const new({
    this.payee,
    this.amount,
    this.dueDate,
    this.fileName,
    this.pattern,
    this.category,
    this.payer,
    this.pixKey,
    this.pixKeyType,
    this.contactHandle,
    this.newContact,
  });

  final String? payee;
  final Money? amount;
  final CalendarDate? dueDate;
  final String? fileName;
  final String? pattern;
  final String? category;
  final String? payer;
  final String? pixKey;
  final PixKeyType? pixKeyType;
  final String? contactHandle;

  /// True when confirming saves the recipient as a new contact.
  final bool? newContact;

  @override
  List<Object?> get props => [
    payee,
    amount,
    dueDate,
    fileName,
    pattern,
    category,
    payer,
    pixKey,
    pixKeyType,
    contactHandle,
    newContact,
  ];
}

final class ChatActionResult extends Equatable {
  const new({
    this.billId,
    this.invoiceId,
    this.ruleId,
    this.updated,
    this.contactId,
  });

  final String? billId;
  final String? invoiceId;
  final String? ruleId;
  final String? contactId;

  /// How many transactions a new rule re-labeled.
  final int? updated;

  @override
  List<Object?> get props => [billId, invoiceId, ruleId, updated, contactId];
}

final class ChatAction extends Equatable {
  const new({
    required this.id,
    required this.threadId,
    required this.tool,
    required this.status,
    required this.details,
    required this.createdAt,
    this.entity,
    this.needsEntity = false,
    this.result,
    this.error,
  });

  final String id;
  final String threadId;
  final ChatTool tool;
  final ChatActionStatus status;
  final EntityKind? entity;

  /// A consolidated thread asks the user which entity the action is for.
  final bool needsEntity;
  final ChatActionDetails details;
  final ChatActionResult? result;
  final String? error;
  final DateTime createdAt;

  bool get isPending => status == ChatActionStatus.pending;

  @override
  List<Object?> get props => [
    id,
    threadId,
    tool,
    status,
    entity,
    needsEntity,
    details,
    result,
    error,
    createdAt,
  ];
}

final class ChatMessage extends Equatable {
  const new({
    required this.id,
    required this.threadId,
    required this.role,
    required this.text,
    required this.createdAt,
    this.notice,
    this.attachments = const [],
    this.actions = const [],
  });

  final String id;
  final String threadId;
  final ChatRole role;
  final String text;
  final ChatNotice? notice;
  final List<ChatAttachment> attachments;
  final List<ChatAction> actions;
  final DateTime createdAt;

  bool get isMine => role == ChatRole.user;

  /// An answer that stopped short, which a new try may fix.
  bool get canRetry => role == ChatRole.assistant && notice != null;

  /// This message with [action] in place of the one with its id.
  ChatMessage withAction(ChatAction action) => ChatMessage(
    id: id,
    threadId: threadId,
    role: role,
    text: text,
    createdAt: createdAt,
    notice: notice,
    attachments: attachments,
    actions: [
      for (final current in actions)
        if (current.id == action.id) action else current,
    ],
  );

  @override
  List<Object?> get props => [
    id,
    threadId,
    role,
    text,
    notice,
    attachments,
    actions,
    createdAt,
  ];
}

enum DraftProblem { empty, tooLong, tooManyFiles, tooLarge, unsupportedFile }

/// What the composer holds before it is sent.
final class ChatDraft extends Equatable {
  const new({this.text = '', this.files = const []});

  static const maxText = 4000;
  static const maxFiles = 3;
  static const int maxBytes = 3 * 1024 * 1024;
  static const List<String> supportedTypes = [
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/heic',
    'audio/mpeg',
    'audio/mp4',
    'audio/aac',
    'audio/wav',
    'audio/ogg',
  ];

  final String text;
  final List<LocalFile> files;

  /// The first rule the draft breaks, or null when it can be sent.
  DraftProblem? get problem {
    final trimmed = text.trim();
    final bytes = files.fold(0, (total, file) => total + file.bytes.length);
    if (trimmed.isEmpty && files.isEmpty) return DraftProblem.empty;
    if (trimmed.length > maxText) return DraftProblem.tooLong;
    if (files.length > maxFiles) return DraftProblem.tooManyFiles;
    if (bytes > maxBytes) return DraftProblem.tooLarge;
    final unsupported = files.any(
      (file) => !supportedTypes.contains(file.contentType),
    );
    return unsupported ? DraftProblem.unsupportedFile : null;
  }

  @override
  List<Object?> get props => [text, files];
}

abstract interface class ChatRepository {
  /// Most recently updated first.
  Future<Result<List<ChatThread>>> threads();

  Future<Result<ChatThread>> startThread(EntityScope scope);

  /// Oldest first.
  Future<Result<List<ChatMessage>>> messages(String threadId);

  /// The stored user message, then the assistant's answer. Sending again
  /// with the same [clientId] returns that pair instead of a second answer.
  Future<Result<List<ChatMessage>>> send(
    String threadId,
    ChatDraft draft, {
    String? clientId,
  });

  /// Drops every message after [messageId], a user message, and answers it
  /// again; [text] replaces what it said. The edited message, then the answer.
  Future<Result<List<ChatMessage>>> regenerate(
    String threadId,
    String messageId, {
    String? text,
  });

  Future<Result<ChatAction>> confirm(String actionId, {EntityKind? entity});

  Future<Result<ChatAction>> cancel(String actionId);
}

enum Delivery { sending, failed }

/// A message on its way, shown before the server stores it. [editOf] is the
/// message it rewrites, when it is an edit or a retry of an answer.
final class OutgoingMessage extends Equatable {
  const new({
    required this.clientId,
    required this.text,
    required this.createdAt,
    this.files = const [],
    this.attachments = const [],
    this.delivery = Delivery.sending,
    this.failure,
    this.editOf,
  });

  final String clientId;
  final String text;
  final List<LocalFile> files;

  /// The files an edited message already carries on the server.
  final List<ChatAttachment> attachments;
  final Delivery delivery;
  final AppFailure? failure;
  final String? editOf;
  final DateTime createdAt;

  bool get failed => delivery == Delivery.failed;

  List<String> get fileNames => [
    for (final file in files) file.name,
    for (final attachment in attachments) attachment.fileName,
  ];

  OutgoingMessage sending() => _with(Delivery.sending, null);

  OutgoingMessage failedWith(AppFailure failure) =>
      _with(Delivery.failed, failure);

  OutgoingMessage _with(Delivery delivery, AppFailure? failure) =>
      OutgoingMessage(
        clientId: clientId,
        text: text,
        createdAt: createdAt,
        files: files,
        attachments: attachments,
        delivery: delivery,
        failure: failure,
        editOf: editOf,
      );

  @override
  List<Object?> get props => [
    clientId,
    text,
    files,
    attachments,
    delivery,
    failure,
    editOf,
    createdAt,
  ];
}
