import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/app/shell/tabs_shell.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/security/app_lock.dart';
import 'package:cashdeck/core/security/safe_mode.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/features/accountant_export/presentation/accountant_export_screen.dart';
import 'package:cashdeck/features/alerts/presentation/alert_settings_screen.dart';
import 'package:cashdeck/features/alerts/presentation/alerts_screen.dart';
import 'package:cashdeck/features/assets/presentation/assets_screen.dart';
import 'package:cashdeck/features/auth/presentation/device_sessions_screen.dart';
import 'package:cashdeck/features/auth/presentation/server_sign_in_screen.dart';
import 'package:cashdeck/features/auth/presentation/unlock_screen.dart';
import 'package:cashdeck/features/bills/presentation/bill_detail_screen.dart';
import 'package:cashdeck/features/bills/presentation/bills_screen.dart';
import 'package:cashdeck/features/budgets/presentation/budget_routes.dart';
import 'package:cashdeck/features/capture/presentation/capture_sources_screen.dart';
import 'package:cashdeck/features/capture/presentation/paste_code_screen.dart';
import 'package:cashdeck/features/capture/presentation/scan_bill_screen.dart';
import 'package:cashdeck/features/capture/presentation/shared_file_screen.dart';
import 'package:cashdeck/features/card_import/presentation/manual_card_bill_import_screen.dart';
import 'package:cashdeck/features/card_notifications/presentation/card_notifications_screen.dart';
import 'package:cashdeck/features/category_review/presentation/category_review_screen.dart';
import 'package:cashdeck/features/category_review/presentation/category_rules_screen.dart';
import 'package:cashdeck/features/chat/presentation/chat_screen.dart';
import 'package:cashdeck/features/chat/presentation/conversation_screen.dart';
import 'package:cashdeck/features/entities/presentation/entity_profiles_screen.dart';
import 'package:cashdeck/features/goals/presentation/goal_routes.dart';
import 'package:cashdeck/features/home/presentation/balances_screen.dart';
import 'package:cashdeck/features/home/presentation/home_screen.dart';
import 'package:cashdeck/features/household/presentation/household_screen.dart';
import 'package:cashdeck/features/insights/presentation/card_timeline_screen.dart';
import 'package:cashdeck/features/insights/presentation/cards_screen.dart';
import 'package:cashdeck/features/insights/presentation/insights_screen.dart';
import 'package:cashdeck/features/insights/presentation/installments_screen.dart';
import 'package:cashdeck/features/insights/presentation/subscription_detail_screen.dart';
import 'package:cashdeck/features/insights/presentation/subscriptions_screen.dart';
import 'package:cashdeck/features/investments/presentation/investment_detail_screen.dart';
import 'package:cashdeck/features/investments/presentation/investments_screen.dart';
import 'package:cashdeck/features/invoices/presentation/invoice_issuer_setup_screen.dart';
import 'package:cashdeck/features/loans/presentation/loans_screen.dart';
import 'package:cashdeck/features/open_finance/presentation/connect_by_item_id_screen.dart';
import 'package:cashdeck/features/outlook/presentation/net_worth_screen.dart';
import 'package:cashdeck/features/payroll/presentation/payroll_input_screen.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contacts_screen.dart';
import 'package:cashdeck/features/plan/presentation/plan_routes.dart';
import 'package:cashdeck/features/rails/domain/payment_rail.dart';
import 'package:cashdeck/features/rails/presentation/payment_rails_screen.dart';
import 'package:cashdeck/features/rails/presentation/rail_detail_screen.dart';
import 'package:cashdeck/features/recap/presentation/recap_routes.dart';
import 'package:cashdeck/features/receipts/presentation/receipt_viewer_screen.dart';
import 'package:cashdeck/features/settings/presentation/safe_zone/safe_zone_screen.dart';
import 'package:cashdeck/features/settings/presentation/sections/company_settings_screen.dart';
import 'package:cashdeck/features/settings/presentation/sections/connections_settings_screen.dart';
import 'package:cashdeck/features/settings/presentation/sections/payments_settings_screen.dart';
import 'package:cashdeck/features/settings/presentation/sections/security_settings_screen.dart';
import 'package:cashdeck/features/settings/presentation/settings_screen.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_detail_screen.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_screen.dart';
import 'package:cashdeck/features/transactions/presentation/transfer_detail_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

StatefulShellBranch _tab(
  String path,
  Widget screen, [
  List<RouteBase> routes = const [],
]) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (_, _) => screen, routes: routes)],
);

GoRoute _page(String path, Widget screen) =>
    GoRoute(path: path, builder: (_, _) => screen);

/// The part of [full] below the tab root [root], as a child route path.
String _below(String full, String root) => full.substring(root.length + 1);

GoRoute _child(String full, String parent, Widget screen) =>
    _page(_below(full, parent), screen);

/// One group of Ajustes: its own screen, with the screens it links to below.
GoRoute _section(String full, Widget screen, List<RouteBase> routes) => GoRoute(
  path: _below(full, AppRoutes.settings),
  builder: (_, _) => screen,
  routes: routes,
);

/// The security group stays open away from a safe zone: it is where the
/// zones and the lock live.
const Set<String> _openWhileLimited = {
  AppRoutes.settingsSecurity,
  AppRoutes.safeZone,
};

/// Screens that show what the amount mask cannot cover, such as the chat's
/// answers and receipts, or that change connections and payments.
bool closedWhileLimited(String path) {
  if (_openWhileLimited.contains(path)) return false;
  return path.startsWith(AppRoutes.chat) ||
      path.startsWith('${AppRoutes.settings}/') ||
      path.endsWith('/receipt') ||
      path == AppRoutes.sharedFile ||
      path == AppRoutes.pasteCode;
}

/// Where [path] must go instead: sign-in without a session, the lock screen
/// while locked, home from either once they no longer apply, and home from a
/// closed screen while the safe mode limits the app.
String? gateRedirect(
  String path, {
  required bool signedIn,
  required bool locked,
  bool limited = false,
}) {
  final gate = switch ((signedIn, locked)) {
    (false, _) => AppRoutes.signIn,
    (true, true) => AppRoutes.unlock,
    (true, false) => null,
  };
  if (gate != null) return path == gate ? null : gate;
  final atGate = path == AppRoutes.signIn || path == AppRoutes.unlock;
  if (atGate) return AppRoutes.home;
  return limited && closedWhileLimited(path) ? AppRoutes.home : null;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final gateChanged = ValueNotifier<int>(0);
  ref
    ..listen(serverSessionProvider, (_, _) => gateChanged.value++)
    ..listen(appLockProvider, (_, _) => gateChanged.value++)
    ..listen(safeModeLimitedProvider, (_, _) => gateChanged.value++)
    ..onDispose(gateChanged.dispose);
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: gateChanged,
    redirect: (_, state) => gateRedirect(
      state.uri.path,
      signedIn: ref.read(serverSessionProvider) != null,
      locked: ref.read(appLockProvider),
      limited: ref.read(safeModeLimitedProvider),
    ),
    routes: [
      _page(AppRoutes.signIn, const ServerSignInScreen()),
      _page(AppRoutes.unlock, const UnlockScreen()),
      GoRoute(
        path: AppRoutes.alerts,
        builder: (_, _) => const AlertsScreen(),
        routes: [
          _page(
            _below(AppRoutes.alertSettings, AppRoutes.alerts),
            const AlertSettingsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.sharedFile,
        redirect: (_, state) =>
            state.extra is LocalFile ? null : AppRoutes.home,
        builder: (_, state) =>
            SharedFileScreen(file: state.extra! as LocalFile),
      ),
      GoRoute(
        path: AppRoutes.pasteCode,
        builder: (_, state) => PasteCodeScreen(
          sharedText: switch (state.extra) {
            final String text => text,
            _ => null,
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.chat,
        builder: (_, _) => const ChatScreen(),
        routes: [
          GoRoute(
            path: _below(AppRoutes.chatNew, AppRoutes.chat),
            builder: (_, _) => const ConversationScreen(),
          ),
          GoRoute(
            path: ':threadId',
            builder: (_, state) =>
                ConversationScreen(threadId: state.pathParameters['threadId']),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
        routes: [
          _child(
            AppRoutes.entityProfiles,
            AppRoutes.settings,
            const EntityProfilesScreen(),
          ),
          _child(
            AppRoutes.household,
            AppRoutes.settings,
            const HouseholdScreen(),
          ),
          _section(
            AppRoutes.settingsConnections,
            const ConnectionsSettingsScreen(),
            [
              _child(
                AppRoutes.connectItemId,
                AppRoutes.settingsConnections,
                const ConnectByItemIdScreen(),
              ),
              GoRoute(
                path: _below(
                  AppRoutes.captureSources,
                  AppRoutes.settingsConnections,
                ),
                builder: (_, _) => const CaptureSourcesScreen(),
                routes: [
                  _child(
                    AppRoutes.scanBill,
                    AppRoutes.captureSources,
                    const ScanBillScreen(),
                  ),
                ],
              ),
              _child(
                AppRoutes.cardImport,
                AppRoutes.settingsConnections,
                const ManualCardBillImportScreen(),
              ),
              _child(
                AppRoutes.cardNotifications,
                AppRoutes.settingsConnections,
                const CardNotificationsScreen(),
              ),
            ],
          ),
          _section(AppRoutes.settingsPayments, const PaymentsSettingsScreen(), [
            GoRoute(
              path: _below(AppRoutes.rails, AppRoutes.settingsPayments),
              builder: (_, _) => const PaymentRailsScreen(),
              routes: [
                GoRoute(
                  path: ':railId',
                  builder: (_, state) => RailDetailScreen(
                    railId: state.pathParameters['railId']!,
                    rail: switch (state.extra) {
                      final PaymentRail rail => rail,
                      _ => null,
                    },
                  ),
                ),
              ],
            ),
            _child(
              AppRoutes.pixContacts,
              AppRoutes.settingsPayments,
              const PixContactsScreen(),
            ),
          ]),
          _section(AppRoutes.settingsCompany, const CompanySettingsScreen(), [
            _child(
              AppRoutes.invoiceIssuer,
              AppRoutes.settingsCompany,
              const InvoiceIssuerSetupScreen(),
            ),
            _child(
              AppRoutes.payroll,
              AppRoutes.settingsCompany,
              const PayrollInputScreen(),
            ),
            _child(
              AppRoutes.accountantExport,
              AppRoutes.settingsCompany,
              const AccountantExportScreen(),
            ),
          ]),
          _child(
            AppRoutes.categoryRules,
            AppRoutes.settings,
            const CategoryRulesScreen(),
          ),
          _section(AppRoutes.settingsSecurity, const SecuritySettingsScreen(), [
            _child(
              AppRoutes.safeZone,
              AppRoutes.settingsSecurity,
              const SafeZoneScreen(),
            ),
            _child(
              AppRoutes.deviceSessions,
              AppRoutes.settingsSecurity,
              const DeviceSessionsScreen(),
            ),
          ]),
        ],
      ),
      _page(AppRoutes.installments, const InstallmentsScreen()),
      _page(AppRoutes.categoryReview, const CategoryReviewScreen()),
      _page(AppRoutes.loans, const LoansScreen()),
      _page(AppRoutes.assets, const AssetsScreen()),
      ...goalRoutes,
      ...planRoutes,
      ...budgetRoutes,
      ...recapRoutes,
      GoRoute(
        path: AppRoutes.investments,
        builder: (_, _) => const InvestmentsScreen(),
        routes: [
          GoRoute(
            path: ':positionId',
            builder: (_, state) => InvestmentDetailScreen(
              positionId: state.pathParameters['positionId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.subscriptions,
        builder: (_, _) => const SubscriptionsScreen(),
        routes: [
          GoRoute(
            path: ':key',
            builder: (_, state) => SubscriptionDetailScreen(
              subscriptionKey: state.pathParameters['key']!,
              fromSuggestion: state.uri.queryParameters['from'] == 'suggestion',
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.cards,
        builder: (_, _) => const CardsScreen(),
        routes: [
          GoRoute(
            path: ':accountId',
            builder: (_, state) => CardTimelineScreen(
              accountId: state.pathParameters['accountId']!,
            ),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, state, shell) =>
            TabsShell(navigationShell: shell, location: state.uri.path),
        branches: [
          _tab(AppRoutes.home, const HomeScreen(), [
            _page(
              _below(AppRoutes.balances, AppRoutes.home),
              const BalancesScreen(),
            ),
            _page(
              _below(AppRoutes.netWorth, AppRoutes.home),
              const NetWorthScreen(),
            ),
          ]),
          _tab(AppRoutes.transactions, const TransactionsScreen(), [
            GoRoute(
              path: 'transfer/:transferId',
              builder: (_, state) => TransferDetailScreen(
                transferId: state.pathParameters['transferId']!,
              ),
            ),
            GoRoute(
              path: ':transactionId',
              builder: (_, state) => TransactionDetailScreen(
                transactionId: state.pathParameters['transactionId']!,
                initial: switch (state.extra) {
                  final Transaction transaction => transaction,
                  _ => null,
                },
              ),
            ),
          ]),
          _tab(AppRoutes.bills, const BillsScreen(), [
            GoRoute(
              path: ':billId',
              builder: (_, state) =>
                  BillDetailScreen(billId: state.pathParameters['billId']!),
              routes: [
                GoRoute(
                  path: 'receipt',
                  builder: (_, state) => ReceiptViewerScreen(
                    billId: state.pathParameters['billId']!,
                  ),
                ),
              ],
            ),
          ]),
          _tab(AppRoutes.insights, const InsightsScreen()),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
