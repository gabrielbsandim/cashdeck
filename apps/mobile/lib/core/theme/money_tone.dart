/// The meaning a color carries in Cashdeck, one per money or bill state.
/// [assisted] is step 3 of the payment ladder: the guaranteed path, drawn in
/// the accent and never in an error color.
enum MoneyTone {
  income,
  expense,
  transfer,
  pending,
  scheduled,
  awaitingApproval,
  paid,
  failed,
  overdue,
  assisted,
  neutral,
}

/// Who a badge or chart series belongs to.
enum EntityTone { personal, company, consolidated }
