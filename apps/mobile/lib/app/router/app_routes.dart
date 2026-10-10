abstract final class AppRoutes {
  static const home = '/home';
  static const transactions = '/transactions';
  static const bills = '/bills';
  static const insights = '/insights';
  static const chat = '/chat';
  static const settings = '/settings';

  static const signIn = '/sign-in';
  static const unlock = '/unlock';
  static const sharedFile = '/shared-file';
  static const balances = '$home/balances';
  static const alerts = '/alerts';
  static const alertSettings = '$alerts/settings';
  static const pasteCode = '/paste-code';
  static const installments = '/installments';
  static const subscriptions = '/subscriptions';
  static const cards = '/cards';

  static const entityProfiles = '$settings/profiles';
  static const captureSources = '$settings/capture';
  static const scanBill = '$settings/capture/scan';
  static const rails = '$settings/rails';
  static const connectItemId = '$settings/open-finance/item-id';
  static const cardImport = '$settings/card-import';
  static const invoiceIssuer = '$settings/invoice-issuer';
  static const payroll = '$settings/payroll';
  static const accountantExport = '$settings/accountant-export';

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

  static String subscription(String key) =>
      '$subscriptions/${Uri.encodeComponent(key)}';

  static String rail(String railId) => '$rails/${Uri.encodeComponent(railId)}';
}
