import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/pix_contacts/application/pix_contacts_use_cases.dart';
import 'package:cashdeck/features/pix_contacts/data/api_pix_contacts_repository.dart';
import 'package:cashdeck/features/pix_contacts/data/fake_pix_contacts_repository.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final pixContactsRepositoryProvider = Provider<PixContactsRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakePixContactsRepository(ref.watch(clockProvider)),
    Backend.api => ApiPixContactsRepository(ref.watch(dioProvider)),
  };
});

final listPixContactsProvider = Provider<ListPixContacts>(
  (ref) => ListPixContacts(ref.watch(pixContactsRepositoryProvider)),
);

final savePixContactProvider = Provider<SavePixContact>(
  (ref) => SavePixContact(ref.watch(pixContactsRepositoryProvider)),
);

final deletePixContactProvider = Provider<DeletePixContact>(
  (ref) => DeletePixContact(ref.watch(pixContactsRepositoryProvider)),
);

final previewPixTransferProvider = Provider<PreviewPixTransfer>(
  (ref) => PreviewPixTransfer(ref.watch(pixContactsRepositoryProvider)),
);

final sendPixTransferProvider = Provider<SendPixTransfer>(
  (ref) => SendPixTransfer(ref.watch(pixContactsRepositoryProvider)),
);
