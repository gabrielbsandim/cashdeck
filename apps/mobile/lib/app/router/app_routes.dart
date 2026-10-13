abstract final class AppRoutes {
  static const home = '/home';
  static const transactions = '/transactions';
  static const bills = '/bills';
  static const insights = '/insights';
  static const chat = '/chat';
  static const chatNew = '$chat/new';
  static const settings = '/settings';

  static const signIn = '/sign-in';
  static const unlock = '/unlock';
  static const sharedFile = '/shared-file';
  static const balances = '$home/balances';
  static const netWorth = '$home/net-worth';
  static const alerts = '/alerts';
  static const alertSettings = '$alerts/settings';
  static const pasteCode = '/paste-code';
  static const installments = '/installments';
  static const subscriptions = '/subscriptions';
  static const cards = '/cards';
  static const investments = '/investments';
  static const categoryReview = '/category-review';
  static const goals = '/goals';
  static const plan = '/plan';
  static const loans = '/loans';
  static const assets = '/assets';
  static const budgets = '/budgets';
  static const budgetSuggestions = '$budgets/suggestions';
  static const recaps = '/recap';

  static const entityProfiles = '$settings/profiles';
  static const household = '$settings/household';
  static const settingsConnections = '$settings/connections';
  static const settingsPayments = '$settings/payments';
  static const settingsCompany = '$settings/company';
  static const settingsSecurity = '$settings/security';
  static const categoryRules = '$settings/category-rules';

  static const connectItemId = '$settingsConnections/item-id';
  static const captureSources = '$settingsConnections/capture';
  static const scanBill = '$captureSources/scan';
  static const cardImport = '$settingsConnections/card-import';
  static const cardNotifications = '$settingsConnections/card-notifications';
  static const rails = '$settingsPayments/rails';
  static const pixContacts = '$settingsPayments/pix-contacts';
  static const invoiceIssuer = '$settingsCompany/invoice-issuer';
  static const payroll = '$settingsCompany/payroll';
  static const accountantExport = '$settingsCompany/accountant-export';
  static const safeZone = '$settingsSecurity/safe-zone';
  static const deviceSessions = '$settingsSecurity/devices';

  /// The tab roots, the only places the bottom navigation shows.
  static const List<String> tabs = [home, transactions, bills, insights];

  static String bill(String billId) => '$bills/${Uri.encodeComponent(billId)}';

  static String billReceipt(String billId) => '${bill(billId)}/receipt';

  static String transfer(String transferId) =>
      '$transactions/transfer/${Uri.encodeComponent(transferId)}';

  static String transaction(String transactionId) =>
      '$transactions/${Uri.encodeComponent(transactionId)}';

  static String chatThread(String threadId) =>
      '$chat/${Uri.encodeComponent(threadId)}';

  static String cardBills(String accountId) =>
      '$cards/${Uri.encodeComponent(accountId)}';

  /// [suggestion] marks a subscription opened from its suggestion card.
  static String subscription(String key, {bool suggestion = false}) {
    final path = '$subscriptions/${Uri.encodeComponent(key)}';
    return suggestion ? '$path?from=suggestion' : path;
  }

  static String investment(String positionId) =>
      '$investments/${Uri.encodeComponent(positionId)}';

  static String goal(String goalId) => '$goals/${Uri.encodeComponent(goalId)}';

  static String budgetSuggestionsFor(String month) =>
      '$budgetSuggestions?month=${Uri.encodeQueryComponent(month)}';

  static String rail(String railId) => '$rails/${Uri.encodeComponent(railId)}';

  /// The story of a month that closed, `2026-09`; [entity] is `PF` (the
  /// default) or `PJ`, as the server names it.
  static String recap(String month, {String? entity}) {
    final path = '$recaps/${Uri.encodeComponent(month)}';
    if (entity == null || entity == 'PF') return path;
    return '$path?entity=${Uri.encodeQueryComponent(entity)}';
  }
}
