import 'package:cashdeck/core/network/json_reader.dart';

JsonMap brl(int cents) => {'cents': cents, 'currency': 'BRL'};

JsonMap overviewJson({JsonMap? cards}) => {
  'period': '1m',
  'range': {'from': '2026-10-01', 'to': '2026-10-08'},
  'previousRange': {'from': '2026-09-01', 'to': '2026-09-30'},
  'spend': {
    'total': brl(5000),
    'previous': brl(1000),
    'changePercent': 400,
    'series': [
      {'day': '2026-10-01', 'cumulative': brl(0)},
    ],
    'previousSeries': [
      {'day': '2026-09-01', 'cumulative': brl(100)},
    ],
    'topMerchants': [
      {'name': 'Loja', 'total': brl(3000), 'count': 1},
    ],
  },
  'categories': {
    'total': brl(5000),
    'items': [
      {
        'categoryId': null,
        'key': null,
        'name': null,
        'icon': null,
        'total': brl(3000),
        'sharePercent': 60,
        'changePercent': null,
      },
    ],
  },
  'flow': {'income': brl(9000), 'expenses': brl(5000), 'result': brl(4000)},
  'cards': cards,
  'billsDue': {'days': 7, 'total': brl(1500), 'count': 1},
};

JsonMap fullCards() => {
  'bill': brl(25000),
  'dueOn': '2026-10-27',
  'count': 1,
  'limit': brl(100000),
  'used': brl(25000),
  'usedPercent': 25,
};

JsonMap change(String id, int delta) => {
  'categoryId': id,
  'key': id,
  'name': id,
  'icon': null,
  'total': brl(1000),
  'average': brl(500),
  'delta': brl(delta),
};

JsonMap monthlyJson({bool current = true}) => {
  'month': '2026-10',
  'months': [
    {
      'month': '2026-10',
      'income': brl(100),
      'expenses': brl(40),
      'result': brl(60),
    },
  ],
  'savings': {
    'percent': 60,
    'averagePercent': null,
    'trend': [
      {'month': '2026-10', 'percent': 60},
    ],
  },
  'changes': {
    'rose': [change('food', 500)],
    'fell': [change('fun', -500)],
  },
  'fixedCost': {
    'subscriptions': brl(10),
    'installments': brl(20),
    'bills': brl(30),
    'total': brl(60),
    'income': brl(100),
    'sharePercent': 60,
  },
  'leftThisMonth': current
      ? {
          'balance': brl(100),
          'billsDue': brl(10),
          'cardBill': brl(20),
          'left': brl(70),
        }
      : null,
  'companyToPersonal': current
      ? {'transfers': brl(500), 'taxes': brl(50)}
      : null,
  'insights': [
    {
      'type': 'CATEGORY_ABOVE_AVERAGE',
      'tone': 'NEGATIVE',
      'categoryId': 'food',
      'name': 'Food',
      'percent': 40,
      'amount': brl(500),
    },
    {
      'type': 'INSTALLMENTS_COMMITTED',
      'tone': 'NEUTRAL',
      'month': '2026-11',
      'amount': brl(300),
    },
    {
      'type': 'SAVINGS_RATE',
      'tone': 'POSITIVE',
      'percent': 60,
      'averagePercent': 40,
    },
    {
      'type': 'SUBSCRIPTION_PRICE_UP',
      'tone': 'NEGATIVE',
      'name': 'Stream',
      'amount': brl(350),
      'previousAmount': brl(300),
    },
    {'type': 'FUTURE_KIND', 'tone': 'NEUTRAL'},
  ],
};

JsonMap installmentsJson() => {
  'months': [
    {'month': '2026-11', 'total': brl(5000)},
  ],
  'plans': [
    {
      'key': 'card|2026-09-05|4|5000',
      'accountId': 'card',
      'card': 'Card',
      'cardSuffix': '1234',
      'entityKind': 'PF',
      'name': 'Sofa',
      'categoryId': null,
      'number': 2,
      'count': 4,
      'amount': brl(5000),
      'paid': brl(10000),
      'remaining': brl(10000),
      'total': brl(20000),
      'purchaseOn': '2026-09-05',
      'lastBilledOn': '2026-10-05',
      'finalMonth': '2026-12',
      'transactionIds': ['sofa'],
    },
  ],
};

JsonMap subscriptionJson({String? id, JsonMap? previous}) => {
  'id': id,
  'key': 'streaming',
  'entityKind': 'PF',
  'name': 'Streaming',
  'amount': brl(3500),
  'previousAmount': previous,
  'priceChanged': previous != null,
  'dayOfMonth': 7,
  'lastChargeOn': '2026-10-07',
  'thisMonth': 'PAID',
  'accountId': 'checking',
  'categoryId': null,
  'transactionIds': ['stream-10'],
  'nextChargeOn': '2026-11-07',
  'charges': [
    {
      'transactionId': 'stream-10',
      'bookedOn': '2026-10-07',
      'amount': brl(3500),
    },
  ],
};

JsonMap subscriptionsJson() => {
  'monthly': brl(3500),
  'yearly': brl(42000),
  'previousMonth': brl(3000),
  'changePercent': 17,
  'items': [subscriptionJson(id: 'r1', previous: brl(3000))],
  'suggestions': [subscriptionJson()],
};

JsonMap cardBillsJson() => {
  'cards': [
    {
      'accountId': 'card',
      'name': 'Cartão Exemplo',
      'suffix': '4821',
      'entityKind': 'PF',
      'bills': [
        {
          'closesOn': null,
          'dueOn': '2026-11-14',
          'total': brl(12_000),
          'minimum': null,
          'state': 'OPEN',
          'range': {'from': '2026-10-08', 'to': '2026-11-07'},
        },
        {
          'closesOn': '2026-10-07',
          'dueOn': '2026-10-14',
          'total': brl(30_000),
          'minimum': brl(3_000),
          'state': 'CLOSED',
          'range': {'from': '2026-09-08', 'to': '2026-10-07'},
        },
      ],
    },
  ],
};

JsonMap cardTimelineJson() => {
  'accountId': 'card',
  'name': 'Cartão Exemplo',
  'suffix': null,
  'entityKind': 'PF',
  'current': 1,
  'bills': [
    {
      'closesOn': '2026-09-09',
      'dueOn': '2026-09-15',
      'total': brl(30_000),
      'minimum': brl(3_000),
      'state': 'PAST',
      'payment': 'UNCONFIRMED',
      'range': {'from': '2026-08-10', 'to': '2026-09-09'},
      'installments': <JsonMap>[],
    },
    {
      'closesOn': null,
      'dueOn': '2026-10-15',
      'total': brl(12_000),
      'minimum': null,
      'state': 'OPEN',
      'payment': null,
      'range': {'from': '2026-09-10', 'to': '2026-10-09'},
      'installments': <JsonMap>[],
    },
    {
      'closesOn': '2026-11-09',
      'dueOn': '2026-11-15',
      'total': brl(5_000),
      'minimum': null,
      'state': 'FORECAST',
      'payment': null,
      'range': {'from': '2026-10-10', 'to': '2026-11-09'},
      'installments': [
        {
          'key': 'plan',
          'name': 'Loja Exemplo',
          'categoryId': null,
          'number': 4,
          'count': 6,
          'amount': brl(5_000),
        },
      ],
    },
  ],
};
