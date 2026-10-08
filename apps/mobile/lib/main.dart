import 'package:cashdeck/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

void main() {
  Intl.defaultLocale = 'pt_BR';
  runApp(const ProviderScope(child: CashdeckApp()));
}
