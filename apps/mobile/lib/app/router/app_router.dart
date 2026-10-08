import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/app/shell/tabs_shell.dart';
import 'package:cashdeck/features/accountant_export/presentation/accountant_export_screen.dart';
import 'package:cashdeck/features/auth/presentation/server_sign_up_screen.dart';
import 'package:cashdeck/features/auth/presentation/unlock_screen.dart';
import 'package:cashdeck/features/bills/presentation/bill_detail_screen.dart';
import 'package:cashdeck/features/bills/presentation/bills_screen.dart';
import 'package:cashdeck/features/capture/presentation/capture_sources_screen.dart';
import 'package:cashdeck/features/card_import/presentation/manual_card_bill_import_screen.dart';
import 'package:cashdeck/features/chat/presentation/chat_screen.dart';
import 'package:cashdeck/features/home/presentation/home_screen.dart';
import 'package:cashdeck/features/invoices/presentation/invoice_issuer_setup_screen.dart';
import 'package:cashdeck/features/open_finance/presentation/connect_by_item_id_screen.dart';
import 'package:cashdeck/features/payroll/presentation/payroll_input_screen.dart';
import 'package:cashdeck/features/rails/domain/payment_rail.dart';
import 'package:cashdeck/features/rails/presentation/payment_rails_screen.dart';
import 'package:cashdeck/features/rails/presentation/rail_detail_screen.dart';
import 'package:cashdeck/features/receipts/presentation/receipt_viewer_screen.dart';
import 'package:cashdeck/features/settings/presentation/more_screen.dart';
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

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      _page(AppRoutes.signUp, const ServerSignUpScreen()),
      _page(AppRoutes.unlock, const UnlockScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, state, shell) =>
            TabsShell(navigationShell: shell, location: state.uri.path),
        branches: [
          _tab(AppRoutes.home, const HomeScreen()),
          _tab(AppRoutes.transactions, const TransactionsScreen(), [
            GoRoute(
              path: 'transfer/:transferId',
              builder: (_, state) => TransferDetailScreen(
                transferId: state.pathParameters['transferId']!,
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
          _tab(AppRoutes.chat, const ChatScreen()),
          _tab(AppRoutes.more, const MoreScreen(), [
            _page(
              _below(AppRoutes.captureSources, AppRoutes.more),
              const CaptureSourcesScreen(),
            ),
            GoRoute(
              path: _below(AppRoutes.rails, AppRoutes.more),
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
            _page(
              _below(AppRoutes.connectItemId, AppRoutes.more),
              const ConnectByItemIdScreen(),
            ),
            _page(
              _below(AppRoutes.cardImport, AppRoutes.more),
              const ManualCardBillImportScreen(),
            ),
            _page(
              _below(AppRoutes.invoiceIssuer, AppRoutes.more),
              const InvoiceIssuerSetupScreen(),
            ),
            _page(
              _below(AppRoutes.payroll, AppRoutes.more),
              const PayrollInputScreen(),
            ),
            _page(
              _below(AppRoutes.accountantExport, AppRoutes.more),
              const AccountantExportScreen(),
            ),
          ]),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
