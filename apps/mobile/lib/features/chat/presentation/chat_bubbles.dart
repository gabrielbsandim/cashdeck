import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/chat/domain/mentions.dart';
import 'package:cashdeck/features/chat/presentation/chat_action_card.dart';
import 'package:cashdeck/features/chat/presentation/chat_controller.dart';
import 'package:cashdeck/features/chat/presentation/chat_labels.dart';
import 'package:cashdeck/features/chat/presentation/chat_markdown.dart';
import 'package:cashdeck/features/chat/presentation/conversation_screen.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

const _maxBubbleWidth = 0.84;

/// The corner next to the sender, smaller so the bubble points at its side.
const double _tail = AppSpacing.xs;

BorderRadius _bubbleShape({required bool mine}) => BorderRadius.only(
  topLeft: const Radius.circular(AppRadius.lg),
  topRight: const Radius.circular(AppRadius.lg),
  bottomLeft: Radius.circular(mine ? AppRadius.lg : _tail),
  bottomRight: Radius.circular(mine ? _tail : AppRadius.lg),
);

/// One side of the conversation: the user's on the right, the assistant's on
/// the left, as wide as 84% of the screen.
class _Side extends StatelessWidget {
  const new({required this.mine, required this.children, super.key});

  final bool mine;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * _maxBubbleWidth,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ),
  );
}

/// The colored body of a message; long press opens its options.
class _BubbleBody extends StatelessWidget {
  const new({required this.mine, required this.child, this.onLongPress});

  final bool mine;
  final Widget child;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shape = _bubbleShape(mine: mine);
    return Material(
      color: mine ? palette.primaryContainer : palette.surfaceContainerHigh,
      borderRadius: shape,
      child: InkWell(
        borderRadius: shape,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md + AppSpacing.xs,
            vertical: AppSpacing.md,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A user's text with every @handle in the primary color.
class MentionText extends StatelessWidget {
  const new({required this.text, required this.style, super.key});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final mention = style.copyWith(
      color: context.palette.primary,
      fontWeight: FontWeight.w600,
    );
    return Text.rich(
      TextSpan(
        children: [
          for (final (part, isMention) in splitMentions(text))
            TextSpan(text: part, style: isMention ? mention : style),
        ],
      ),
    );
  }
}

class _FileChips extends StatelessWidget {
  const new({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.xs,
    runSpacing: AppSpacing.xs,
    alignment: WrapAlignment.end,
    children: [
      for (final name in names)
        Chip(
          avatar: const Icon(Symbols.attach_file_rounded, size: 18),
          label: Text(name),
          visualDensity: VisualDensity.compact,
        ),
    ],
  );
}

/// A stored message, its files, why an answer stopped short and the actions
/// it proposes.
class MessageBubble extends StatelessWidget {
  const new({
    required this.conversation,
    required this.message,
    required this.resolving,
    required this.onOptions,
    this.onRetry,
    super.key,
  });

  final ConversationKey conversation;
  final ChatMessage message;
  final Set<String> resolving;
  final VoidCallback onOptions;

  /// Set on the last answer when it stopped short.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final mine = message.isMine;
    final notice = message.notice;
    final text = message.text.trim();
    final retry = onRetry;
    final ink = mine ? palette.onPrimaryContainer : palette.onSurface;
    final style = AppTextStyles.bodyLg.copyWith(color: ink);
    return _Side(
      key: ConversationScreen.messageKey(message.id),
      mine: mine,
      children: [
        if (text.isNotEmpty)
          _BubbleBody(
            mine: mine,
            onLongPress: onOptions,
            child: mine
                ? MentionText(text: text, style: style)
                : ChatMarkdown(text: text, style: style),
          ),
        if (message.attachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: _FileChips(
              names: [for (final file in message.attachments) file.fileName],
            ),
          ),
        if (notice != null)
          _Notice(text: chatNoticeText(l10n, notice), onLongPress: onOptions),
        if (retry != null)
          CdButton.text(
            key: ConversationScreen.retryAnswerKey(message.id),
            icon: Symbols.refresh_rounded,
            label: l10n.chatRetry,
            dense: true,
            onPressed: retry,
          ),
        for (final action in message.actions)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: ChatActionCard(
              conversation: conversation,
              action: action,
              busy: resolving.contains(action.id),
            ),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const new({required this.text, required this.onLongPress});

  final String text;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: onLongPress,
    child: Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.info_rounded, size: 16, color: context.money.failed),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              text,
              style: AppTextStyles.bodyMd.copyWith(
                color: context.palette.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A message the server has not stored yet: faded while it goes, and with
/// the ways out when it failed.
class OutgoingBubble extends StatelessWidget {
  const new({
    required this.outgoing,
    required this.onRetry,
    required this.onEdit,
    required this.onDiscard,
    super.key,
  });

  final OutgoingMessage outgoing;
  final VoidCallback onRetry;
  final VoidCallback onEdit;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = AppTextStyles.bodyLg.copyWith(
      color: palette.onPrimaryContainer,
    );
    return _Side(
      key: ConversationScreen.outgoingKey,
      mine: true,
      children: [
        AnimatedOpacity(
          opacity: outgoing.failed ? 1 : 0.72,
          duration: AppMotion.of(context, AppMotion.medium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (outgoing.text.isNotEmpty)
                _BubbleBody(
                  mine: true,
                  child: MentionText(text: outgoing.text, style: style),
                ),
              if (outgoing.fileNames.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: _FileChips(names: outgoing.fileNames),
                ),
            ],
          ),
        ),
        if (outgoing.failed)
          _FailedLine(
            outgoing: outgoing,
            onRetry: onRetry,
            onEdit: onEdit,
            onDiscard: onDiscard,
          )
        else
          const _SendingLine(),
      ],
    );
  }
}

class _SendingLine extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = context.palette.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.schedule_rounded, size: 14, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            l10n.chatSending,
            style: AppTextStyles.labelMd.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _FailedLine extends StatelessWidget {
  const new({
    required this.outgoing,
    required this.onRetry,
    required this.onEdit,
    required this.onDiscard,
  });

  final OutgoingMessage outgoing;
  final VoidCallback onRetry;
  final VoidCallback onEdit;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final failed = context.money.failed;
    final reason = outgoing.failure?.userMessage(l10n);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.error_rounded, size: 16, color: failed),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  reason == null
                      ? l10n.chatNotSent
                      : '${l10n.chatNotSent}. $reason',
                  textAlign: TextAlign.end,
                  style: AppTextStyles.labelMd.copyWith(color: failed),
                ),
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              CdButton.text(
                key: ConversationScreen.discardKey,
                label: l10n.chatDiscard,
                dense: true,
                onPressed: onDiscard,
              ),
              CdButton.text(
                key: ConversationScreen.editFailedKey,
                label: l10n.chatEdit,
                dense: true,
                onPressed: onEdit,
              ),
              CdButton.text(
                key: ConversationScreen.retrySendKey,
                icon: Symbols.refresh_rounded,
                label: l10n.chatRetry,
                dense: true,
                onPressed: onRetry,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Three dots that rise in turn while the answer is written; still when the
/// device asks for reduced motion.
class TypingBubble extends StatefulWidget {
  const new({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _wave.stop();
      return;
    }
    if (!_wave.isAnimating) _wave.repeat();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return Semantics(
      key: ConversationScreen.thinkingKey,
      label: l10n.chatTyping,
      liveRegion: true,
      child: _Side(
        mine: false,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surfaceContainerHigh,
              borderRadius: _bubbleShape(mine: false),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md + AppSpacing.xs,
              ),
              child: AnimatedBuilder(
                animation: _wave,
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var dot = 0; dot < 3; dot++)
                      _Dot(phase: _phase(dot), color: palette.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 0 at rest, 1 at the top of the dot's rise; each dot starts a beat later.
  double _phase(int dot) {
    final t = (_wave.value - dot * 0.18) % 1;
    if (t > 0.5) return 0;
    return Curves.easeInOut.transform(1 - (t * 4 - 1).abs());
  }
}

class _Dot extends StatelessWidget {
  const new({required this.phase, required this.color});

  final double phase;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: Transform.translate(
      offset: Offset(0, -4 * phase),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.45 + 0.55 * phase),
          shape: BoxShape.circle,
        ),
      ),
    ),
  );
}
