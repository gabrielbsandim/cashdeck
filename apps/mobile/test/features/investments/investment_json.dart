Map<String, dynamic> money(int cents, [String currency = 'BRL']) => {
  'cents': cents,
  'currency': currency,
};

Map<String, dynamic> positionJson({String id = 'cdb', bool full = true}) => {
  'id': id,
  'entityKind': 'PF',
  'institutionId': 'aurora',
  'institution': 'Banco Aurora',
  'logo': full
      ? {'imageUrl': 'https://logo.example/a.svg', 'color': null}
      : null,
  'name': 'CDB Banco Aurora',
  'kind': full ? 'FIXED_INCOME' : 'OTHER',
  'subtype': full ? 'CDB' : null,
  'issuer': full ? 'Banco Aurora S.A.' : null,
  'status': full ? 'ACTIVE' : 'PENDING',
  'balance': money(105_000),
  'invested': full ? money(100_000) : null,
  'profit': full ? money(5_000) : null,
  'profitPercent': full ? 5 : null,
  'quantity': full ? 1.5 : null,
  'rate': full ? {'percent': 102, 'index': 'CDI', 'fixedAnnual': null} : null,
  'lastMonthRate': full ? 0.9 : null,
  'lastTwelveMonthsRate': null,
  'dueOn': full ? '2028-04-04' : null,
  'valuedOn': full ? '2026-10-07' : null,
};

Map<String, dynamic> investmentsJson({bool full = true}) => {
  'total': money(105_000),
  'invested': money(100_000),
  'profit': money(5_000),
  'syncedAt': full ? '2026-10-08T12:00:00.000Z' : null,
  'institutions': [
    {
      'institutionId': 'aurora',
      'institution': 'Banco Aurora',
      'logo': full
          ? {'imageUrl': 'https://logo.example/a.svg', 'color': '#FF0000'}
          : null,
      'total': money(105_000),
      'count': 1,
    },
  ],
  'kinds': [
    {'kind': 'FIXED_INCOME', 'total': money(105_000), 'count': 1},
  ],
  'positions': [positionJson(full: full)],
};
