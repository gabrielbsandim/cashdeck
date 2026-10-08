/// Who owns a record: the person (PF) or their company (PJ).
enum EntityKind { personal, company }

/// What the entity switcher shows: one entity or both together.
enum EntityScope {
  personal,
  company,
  consolidated;

  bool includes(EntityKind kind) => switch (this) {
    EntityScope.personal => kind == EntityKind.personal,
    EntityScope.company => kind == EntityKind.company,
    EntityScope.consolidated => true,
  };
}
