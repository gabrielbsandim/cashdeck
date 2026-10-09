import 'package:cashdeck/features/automation/domain/automation.dart';
import 'package:cashdeck/features/bills/domain/bills_repository.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/home/domain/home_repository.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:mocktail/mocktail.dart';

final class MockBillsRepository extends Mock implements BillsRepository;

final class MockHomeRepository extends Mock implements HomeRepository;

final class MockAutomationRepository extends Mock
    implements AutomationRepository;

final class MockTransactionsRepository extends Mock
    implements TransactionsRepository;

final class MockCategoriesRepository extends Mock
    implements CategoriesRepository;

final class MockChatRepository extends Mock implements ChatRepository;
