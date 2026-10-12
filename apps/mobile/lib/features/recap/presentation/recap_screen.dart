import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/insights/cd_comparison_pill.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/features/recap/domain/monthly_recap.dart';
import 'package:cashdeck/features/recap/presentation/recap_controller.dart';
import 'package:cashdeck/features/recap/presentation/recap_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Leaves the recap: back where it was opened from, or to Análises when it
/// was the first screen, as from a push.
void _close(BuildContext context) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  context.go(AppRoutes.insights);
}

/// The month that closed as a story: one page per figure, tap right to go
/// on, left to go back, hold to pause, swipe down to close. Each page moves
/// on by itself after [pageDuration], unless the device asks for reduced
/// motion.
class RecapScreen extends ConsumerWidget {
  const new({
    required this.month,
    this.entity = EntityKind.personal,
    super.key,
  });

  static const closeKey = Key('recap-close');
  static const storyKey = Key('recap-story');
  static const pageDuration = Duration(milliseconds: 6500);
  static Key pageKey(RecapPage page) => Key('recap-page-${page.name}');
  static Key barKey(int index) => Key('recap-bar-$index');

  final String month;
  final EntityKind entity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final request = (month: month, entity: entity, locale: recapLocaleOf(l10n));
    return Scaffold(
      body: SafeArea(
        child: switch (ref.watch(monthlyRecapProvider(request))) {
          AsyncData(:final value) => _Story(recap: value, entity: entity),
          AsyncError(:final error) => Column(
            children: [
              const Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _CloseButton(),
              ),
              Expanded(
                child: CdErrorState(
                  failure: failureOf(error),
                  onRetry: () => ref.invalidate(monthlyRecapProvider(request)),
                ),
              ),
            ],
          ),
          _ => const CdSkeleton(),
        },
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: RecapScreen.closeKey,
      tooltip: AppLocalizations.of(context).recapClose,
      icon: const Icon(Symbols.close_rounded),
      onPressed: () => _close(context),
    );
  }
}

class _Story extends StatefulWidget {
  const new({required this.recap, required this.entity});

  final MonthlyRecap recap;
  final EntityKind entity;

  @override
  State<_Story> createState() => _StoryState();
}

class _StoryState extends State<_Story> with SingleTickerProviderStateMixin {
  static const _dismissDistance = 120.0;
  static const _dismissVelocity = 700.0;

  late final AnimationController _timer = AnimationController(
    vsync: this,
    duration: RecapScreen.pageDuration,
  )..addStatusListener(_timerEnded);

  var _index = 0;
  var _dragged = 0.0;
  var _held = false;

  List<RecapPage> get _pages => widget.recap.pages;

  bool get _still => AppMotion.reduced(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _play();
  }

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  /// Runs the bar of the current page from where it is, unless the story is
  /// held or the device asks for reduced motion.
  void _play() {
    if (_still || _held) {
      _timer.stop();
      return;
    }
    _timer.forward();
  }

  void _show(int index) {
    setState(() => _index = index);
    _timer.value = 0;
    _play();
  }

  // The last page stays once its bar is full, so the closing words are read.
  void _timerEnded(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_index == _pages.length - 1) return;
    _show(_index + 1);
  }

  void _next() {
    if (_index == _pages.length - 1) {
      _close(context);
      return;
    }
    _show(_index + 1);
  }

  void _previous() {
    if (_index == 0) return;
    _show(_index - 1);
  }

  void _tapped(TapUpDetails details, double width) {
    if (details.localPosition.dx < width / 3) {
      _previous();
      return;
    }
    _next();
  }

  void _hold(bool held) {
    _held = held;
    _play();
  }

  void _dragEnded(DragEndDetails details) {
    final down =
        _dragged > _dismissDistance ||
        (details.primaryVelocity ?? 0) > _dismissVelocity;
    _dragged = 0;
    if (down) _close(context);
  }

  double _fillOf(int index) {
    if (index < _index) return 1;
    if (index > _index) return 0;
    return _still ? 1 : _timer.value;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final page = _pages[_index];
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        key: RecapScreen.storyKey,
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) => _tapped(details, constraints.maxWidth),
        onLongPressStart: (_) => _hold(true),
        onLongPressEnd: (_) => _hold(false),
        onVerticalDragUpdate: (details) => _dragged += details.delta.dy,
        onVerticalDragEnd: _dragEnded,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.sm,
            AppSpacing.screenGutter,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: l10n.recapPageLabel(_index + 1, _pages.length),
                child: AnimatedBuilder(
                  animation: _timer,
                  builder: (context, _) => Row(
                    children: [
                      for (var index = 0; index < _pages.length; index++) ...[
                        if (index > 0) const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: _ProgressBar(
                            key: RecapScreen.barKey(index),
                            fill: _fillOf(index),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      recapTitleOf(
                        l10n,
                        widget.recap.month,
                        entity: widget.entity,
                      ),
                      style: AppTextStyles.labelLg.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const _CloseButton(),
                ],
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: KeyedSubtree(
                    key: RecapScreen.pageKey(page),
                    child: _PageBody(recap: widget.recap, page: page),
                  ),
                ),
              ),
              Text(
                l10n.recapHint,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One page of the story: full once seen, filling while it plays.
class _ProgressBar extends StatelessWidget {
  const new({required this.fill, super.key});

  final double fill;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: SizedBox(
        height: 3,
        child: ColoredBox(
          color: palette.outlineVariant,
          child: FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: fill,
            child: ColoredBox(color: palette.primary),
          ),
        ),
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  const new({required this.recap, required this.page});

  final MonthlyRecap recap;
  final RecapPage page;

  @override
  Widget build(BuildContext context) {
    final body = switch (page) {
      RecapPage.flow => _FlowPage(recap: recap),
      RecapPage.topCategory => _TopCategoryPage(category: recap.topCategory!),
      RecapPage.changes => _ChangesPage(recap: recap),
      RecapPage.savings => _SavingsPage(recap: recap),
      RecapPage.netWorth => _NetWorthPage(netWorth: recap.netWorth!),
      RecapPage.story => _StoryPage(recap: recap),
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: body,
    );
  }
}

class _PageTitle extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Text(
        text,
        style: AppTextStyles.headlineMd.copyWith(
          color: context.palette.onSurface,
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const new({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.labelLg.copyWith(
              color: context.palette.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

class _FlowPage extends StatelessWidget {
  const new({required this.recap});

  final MonthlyRecap recap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final flow = recap.flow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageTitle(l10n.recapFlowTitle(capitalMonth(l10n, recap.month))),
        _Figure(
          label: l10n.recapIncome,
          child: CdAmount(
            flow.income,
            size: CdAmountSize.xl,
            kind: CdAmountKind.income,
            textAlign: TextAlign.start,
          ),
        ),
        _Figure(
          label: l10n.recapExpenses,
          child: CdAmount(
            flow.expenses,
            size: CdAmountSize.xl,
            kind: CdAmountKind.expense,
            textAlign: TextAlign.start,
          ),
        ),
        _Figure(
          label: flow.net.isNegative ? l10n.recapNetShort : l10n.recapNetKept,
          child: CdAmount(
            flow.net.abs,
            size: CdAmountSize.xl,
            textAlign: TextAlign.start,
          ),
        ),
      ],
    );
  }
}

class _TopCategoryPage extends StatelessWidget {
  const new({required this.category});

  final RecapCategory category;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageTitle(l10n.recapTopTitle),
        CdIconTile(recapCategoryIcon(category)),
        const SizedBox(height: AppSpacing.md),
        Text(
          recapCategoryName(l10n, category),
          style: AppTextStyles.titleLg.copyWith(color: palette.onSurface),
        ),
        const SizedBox(height: AppSpacing.sm),
        CdAmount(
          category.total,
          size: CdAmountSize.xl,
          textAlign: TextAlign.start,
        ),
        if (category.sharePercent case final share?) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.recapTopShare(share),
            style: AppTextStyles.bodyLg.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ChangeRow extends ConsumerWidget {
  const new({required this.name, required this.amount});

  final String name;
  final Money amount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: AppTextStyles.bodyLg.copyWith(color: palette.onSurface),
            ),
          ),
          Text(
            signedAmount(amount, hide: ref.watch(hideAmountsProvider)),
            style: AppTextStyles.amountRow.copyWith(color: palette.onSurface),
          ),
        ],
      ),
    );
  }
}

class _ChangeGroup extends StatelessWidget {
  const new({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppTextStyles.titleSm.copyWith(
              color: context.palette.onSurfaceVariant,
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}

class _ChangesPage extends ConsumerWidget {
  const new({required this.recap});

  final MonthlyRecap recap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    final change = recap.expensesChange;
    final percent = change.percent;
    List<Widget> categories(List<RecapCategory> items) => [
      for (final item in items)
        _ChangeRow(
          name: recapCategoryName(l10n, item),
          amount: item.change?.amount ?? item.total,
        ),
    ];
    List<Widget> subscriptions(List<RecapSubscription> items, int sign) => [
      for (final item in items)
        _ChangeRow(
          name: item.name,
          amount: Money(item.amount.cents.abs() * sign),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageTitle(l10n.recapChangesTitle),
        CdComparisonPill(
          direction: change.amount.cents.sign,
          value: percent == null
              ? MoneyFormat.format(change.amount.abs, hide: hide)
              : '${percent.abs()}%',
          label: l10n.recapExpensesVsPrevious(
            monthName(l10n, recap.month.add(-1)),
          ),
        ),
        _ChangeGroup(title: l10n.recapRose, rows: categories(recap.rose)),
        _ChangeGroup(title: l10n.recapFell, rows: categories(recap.fell)),
        _ChangeGroup(
          title: l10n.recapStarted,
          rows: subscriptions(recap.started, 1),
        ),
        _ChangeGroup(
          title: l10n.recapStopped,
          rows: subscriptions(recap.stopped, -1),
        ),
      ],
    );
  }
}

class _SavingsPage extends StatelessWidget {
  const new({required this.recap});

  final MonthlyRecap recap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final percent = recap.savingsPercent!;
    final previous = recap.previousSavingsPercent;
    final secondary = AppTextStyles.bodyLg.copyWith(
      color: palette.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageTitle(l10n.recapSavingsTitle),
        Text(
          '$percent%',
          style: AppTextStyles.amountXl.copyWith(color: palette.onSurface),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          percent < 0 ? l10n.recapSavingsShort : l10n.recapSavingsKept,
          style: secondary,
        ),
        if (previous != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.recapSavingsPrevious(
              monthName(l10n, recap.month.add(-1)),
              previous,
            ),
            style: secondary,
          ),
        ],
      ],
    );
  }
}

class _NetWorthPage extends ConsumerWidget {
  const new({required this.netWorth});

  final RecapNetWorth netWorth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final change = netWorth.change.amount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageTitle(l10n.recapNetWorthTitle),
        CdAmount(
          netWorth.total,
          size: CdAmountSize.xl,
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: AppSpacing.md),
        CdComparisonPill(
          direction: change.cents.sign,
          goodWhen: GoodWhen.up,
          value: signedAmount(change, hide: ref.watch(hideAmountsProvider)),
          label: l10n.recapNetWorthChange,
        ),
      ],
    );
  }
}

class _StoryPage extends StatelessWidget {
  const new({required this.recap});

  final MonthlyRecap recap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageTitle(l10n.recapStoryTitle),
        CdPrivateText(
          (hide) => hide ? maskAmounts(recap.story) : recap.story,
          style: AppTextStyles.titleMd.copyWith(color: palette.onSurface),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Icon(
              switch (recap.storySource) {
                RecapStorySource.ai => Symbols.auto_awesome_rounded,
                RecapStorySource.template => Symbols.notes_rounded,
              },
              size: 16,
              color: palette.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                switch (recap.storySource) {
                  RecapStorySource.ai => l10n.recapStoryAi,
                  RecapStorySource.template => l10n.recapStoryTemplate,
                },
                style: AppTextStyles.bodyMd.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
