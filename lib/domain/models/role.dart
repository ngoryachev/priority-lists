/// The hat the user is wearing right now.
///
/// A pure marker: nothing in the tree, the filter or the activity log reads it.
/// It exists so the user can state, to themselves, which part of their life the
/// current session belongs to.
///
/// Labels and descriptions are English renderings of the roles as the user
/// wrote them (Отец, Партнёр, Профессионал / Tech Lead, Создатель, Хозяин своей
/// жизни, Я сам); the rest of the UI is English, so these follow it.
enum Role {
  father(
    'father',
    'Father',
    'Relationships with children, parenting, time together.',
  ),
  partner(
    'partner',
    'Partner',
    'Romantic relationship, intimacy, emotional connection.',
  ),
  professional(
    'professional',
    'Professional / Tech Lead',
    'Work, team, technical decisions, career.',
  ),
  creator(
    'creator',
    'Creator',
    'Own projects, AI, experiments, entrepreneurship.',
  ),
  lifeOwner(
    'life_owner',
    'Life Owner',
    'Finances, household, documents, life organization, personal autonomy.',
  ),
  myself(
    'myself',
    'Myself',
    'Health, sport, sleep, growth, interests, rest.',
  );

  const Role(this.id, this.label, this.description);

  /// Stable storage key. Decoupled from [Enum.name] on purpose: the enum can be
  /// renamed without rewriting rows that are already in the database.
  final String id;

  final String label;

  /// Longer wording, shown as the chip's tooltip.
  final String description;

  /// Decodes a stored [id]. Returns null for a missing or unknown one, so a row
  /// written by a newer build (or a hand-edited one) reads as "no role" instead
  /// of crashing an older client.
  static Role? fromId(String? id) {
    if (id == null) return null;
    for (final role in Role.values) {
      if (role.id == id) return role;
    }
    return null;
  }
}
