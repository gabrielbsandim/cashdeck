abstract final class AppRoutes {
  static const home = '/home';
  static const transactions = '/transactions';
  static const bills = '/bills';
  static const chat = '/chat';
  static const more = '/more';

  static const signUp = '/sign-up';
  static const unlock = '/unlock';

  static const captureSources = '$more/capture';
  static const rails = '$more/rails';
  static const connectItemId = '$more/open-finance/item-id';
  static const cardImport = '$more/card-import';
  static const invoiceIssuer = '$more/invoice-issuer';
  static const payroll = '$more/payroll';
  static const accountantExport = '$more/accountant-export';

  /// The tab roots, the only places the bottom navigation shows.
  static const List<String> tabs = [home, transactions, bills, chat, more];

  static String bill(String billId) => '$bills/${Uri.encodeComponent(billId)}';

  static String billReceipt(String billId) => '${bill(billId)}/receipt';

  static String transfer(String transferId) =>
      '$transactions/transfer/${Uri.encodeComponent(transferId)}';

  static String rail(String railId) => '$rails/${Uri.encodeComponent(railId)}';
}
