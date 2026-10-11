import 'package:equatable/equatable.dart';

/// The @token the cursor is typing: [start] is where the @ sits and [query]
/// what follows it up to the cursor.
final class MentionQuery extends Equatable {
  const new({required this.start, required this.query});

  final int start;
  final String query;

  @override
  List<Object?> get props => [start, query];
}

final _tokenChar = RegExp(r'[\p{L}\p{N}._]', unicode: true);
final _space = RegExp(r'\s');

const _maxQuery = 30;

/// The mention being typed at [cursor] in [text], or null when the cursor is
/// not right after an @ token that starts a word.
MentionQuery? mentionAt(String text, int cursor) {
  if (cursor < 1 || cursor > text.length) return null;
  var index = cursor - 1;
  while (index >= 0 && _tokenChar.hasMatch(text[index])) {
    index--;
  }
  if (index < 0 || text[index] != '@') return null;
  final startsWord = index == 0 || _space.hasMatch(text[index - 1]);
  final query = text.substring(index + 1, cursor);
  if (!startsWord || query.length > _maxQuery) return null;
  return MentionQuery(start: index, query: query);
}

/// [text] with [mention] replaced by @[handle] and a space, and where the
/// cursor goes next.
(String, int) insertMention(
  String text,
  MentionQuery mention,
  int cursor,
  String handle,
) {
  final inserted = '@$handle ';
  final rest = text.substring(cursor).replaceFirst(RegExp(r'^\s'), '');
  final next = text.substring(0, mention.start) + inserted + rest;
  return (next, mention.start + inserted.length);
}

final _mention = RegExp(r'(?<=^|\s)@[a-z0-9][a-z0-9._]{1,29}');

/// [text] cut into plain runs and @handle runs, in order; true marks a
/// mention.
List<(String, bool)> splitMentions(String text) {
  final parts = <(String, bool)>[];
  var at = 0;
  for (final match in _mention.allMatches(text)) {
    if (match.start > at) parts.add((text.substring(at, match.start), false));
    parts.add((match.group(0)!, true));
    at = match.end;
  }
  if (at < text.length) parts.add((text.substring(at), false));
  return parts;
}
