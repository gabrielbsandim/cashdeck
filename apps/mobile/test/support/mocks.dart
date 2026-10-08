import 'package:cashdeck/features/automation/domain/automation.dart';
import 'package:cashdeck/features/bills/domain/bills_repository.dart';
import 'package:cashdeck/features/home/domain/home_repository.dart';
import 'package:mocktail/mocktail.dart';

final class MockBillsRepository extends Mock implements BillsRepository;

final class MockHomeRepository extends Mock implements HomeRepository;

final class MockAutomationRepository extends Mock
    implements AutomationRepository;
