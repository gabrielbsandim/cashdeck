import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/chat/presentation/chat_controller.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The conversations with the assistant; a new one reads the entity the
/// switcher shows.
class ChatScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const newThreadKey = Key('chat-new-thread');

  static Key threadKey(String id) => Key('chat-thread-$id');

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  var _starting = false;

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    final result = await ref
        .read(chatThreadsControllerProvider.notifier)
        .start(ref.read(entityScopeProvider));
    if (!mounted) return;
    setState(() => _starting = false);
    switch (result) {
      case Ok(:final value):
        context.go(AppRoutes.chatThread(value.id));
      case Err(:final failure):
        await showOutcomeToast(context, failure, success: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final threads = ref.watch(chatThreadsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.chatTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: ChatScreen.newThreadKey,
        onPressed: _starting ? null : _start,
        icon: const Icon(Symbols.add_comment_rounded),
        label: Text(l10n.chatNewThread),
      ),
      body: Column(
        children: [
          const EntitySwitcher(),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: switch (threads) {
              AsyncData(:final value) when value.isEmpty => CdEmptyState(
                icon: Symbols.forum_rounded,
                title: l10n.chatEmptyTitle,
                message: l10n.chatEmptyMessage,
              ),
              AsyncData(:final value) => ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  for (final thread in value) _ThreadRow(thread: thread),
                ],
              ),
              AsyncError(:final error) => CdErrorState(
                failure: failureOf(error),
                onRetry: () => ref.invalidate(chatThreadsControllerProvider),
              ),
              _ => const CdSkeleton(),
            },
          ),
        ],
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const new({required this.thread});

  final ChatThread thread;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final day = CalendarDate.brazilToday(thread.updatedAt);
    return CdListRow(
      key: ChatScreen.threadKey(thread.id),
      leading: EntityScopeBadge(scope: thread.scope),
      title: thread.title ?? l10n.chatUntitledThread,
      subtitle: l10n.chatThreadSubtitle(
        entityScopeLabel(l10n, thread.scope),
        day.dayMonth,
        brazilTime(thread.updatedAt),
      ),
      chevron: true,
      onTap: () => context.go(AppRoutes.chatThread(thread.id)),
    );
  }
}
