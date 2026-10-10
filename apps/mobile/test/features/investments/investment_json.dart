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

Map<String, dynamic> performanceJson({bool full = true}) => {
  'period': full ? 'MONTH' : 'YEAR',
  'from': '2026-09-08',
  'to': '2026-10-08',
  'start': money(100_000),
  'end': money(105_000),
  'contributions': money(full ? 2_000 : 0),
  'withdrawals': money(full ? 500 : 0),
  'yield': money(3_500),
  'yieldPercent': full ? 3.47 : null,
  'cdiPercent': full ? 0.82 : null,
  'estimated': full,
  'series': [
    {'day': '2026-09-08', 'value': money(100_000)},
    {'day': '2026-10-08', 'value': money(105_000)},
  ],
  if (full)
    'positions': [
      {
        'id': 'cdb',
        'start': money(100_000),
        'end': money(105_000),
        'yield': money(3_500),
        'yieldPercent': 3.47,
      },
    ],
};

Map<String, dynamic> movementJson({String id = 'mv-1', bool full = true}) => {
  'id': id,
  'kind': full ? 'BUY' : 'TAX',
  'occurredOn': '2026-03-04',
  'amount': money(100_000),
  'quantity': full ? 10000 : null,
  'unitPrice': full ? 1.0 : null,
};

Map<String, dynamic> detailJson() => {
  'position': positionJson(),
  'performance': performanceJson(),
  'movements': [movementJson(), movementJson(id: 'mv-2', full: false)],
};
