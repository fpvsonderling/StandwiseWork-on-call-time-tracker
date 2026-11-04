/// First/last name rules (spec §4.2).
library;

const int maxNameLength = 50;

/// Letters (any script), spaces, hyphens and apostrophes. Combining marks are
/// allowed so decomposed forms like "Łukasz" typed on some keyboards pass.
final RegExp _namePattern = RegExp(r"^[\p{L}\p{M}' ’-]+$", unicode: true);

enum NameError { empty, tooLong, invalidCharacters }

/// Trims and collapses inner whitespace.
String normalizeName(String input) =>
    input.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Returns `null` if [input] (after normalizing) is a valid first or last name.
NameError? validateName(String input) {
  final v = normalizeName(input);
  if (v.isEmpty) return NameError.empty;
  if (v.runes.length > maxNameLength) return NameError.tooLong;
  if (!_namePattern.hasMatch(v)) return NameError.invalidCharacters;
  // Must contain at least one letter, not only punctuation.
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(v)) {
    return NameError.invalidCharacters;
  }
  return null;
}

/// Splits a Google display name on the last space to prefill the
/// "Your name" form: "Anna Maria Kowalska" → ("Anna Maria", "Kowalska").
({String first, String last}) splitDisplayName(String? displayName) {
  final v = normalizeName(displayName ?? '');
  if (v.isEmpty) return (first: '', last: '');
  final i = v.lastIndexOf(' ');
  if (i < 0) return (first: v, last: '');
  return (first: v.substring(0, i), last: v.substring(i + 1));
}

/// "First Last" as shown in reports, CSV and Team (never the Google name).
String fullName(String first, String last) => normalizeName('$first $last');
