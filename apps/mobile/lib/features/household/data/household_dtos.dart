import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/household/domain/household.dart';

Household householdFromJson(JsonMap json) => Household([
  for (final member in readMapList(json, 'members'))
    HouseholdMember(
      name: readString(member, 'name'),
      taxId: readString(member, 'taxId'),
    ),
]);

JsonMap householdToJson(Household household) => {
  'members': [
    for (final member in household.members)
      {'name': member.name, 'taxId': member.taxId},
  ],
};
