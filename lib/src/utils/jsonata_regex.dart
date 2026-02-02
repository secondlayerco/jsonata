/// Represents a JSONata regex pattern with its flags.
/// 
/// This is used to pass regex patterns to functions like $match, $replace, etc.
class JsonataRegex {
  /// The regex pattern string.
  final String pattern;

  /// The regex flags (e.g., "i" for case-insensitive, "m" for multiline, "g" for global).
  final String flags;

  /// The compiled RegExp object.
  late final RegExp _regex;

  /// Creates a new JsonataRegex.
  JsonataRegex(this.pattern, this.flags) {
    _regex = RegExp(
      pattern,
      caseSensitive: !flags.contains('i'),
      multiLine: flags.contains('m'),
      dotAll: flags.contains('s'),
    );
  }

  /// Returns the compiled RegExp.
  RegExp get regex => _regex;

  /// Whether this is a global match (find all matches).
  bool get isGlobal => flags.contains('g');

  /// Finds all matches in the string.
  Iterable<RegExpMatch> allMatches(String str) => _regex.allMatches(str);

  /// Finds the first match in the string.
  RegExpMatch? firstMatch(String str) => _regex.firstMatch(str);

  /// Whether the string contains this pattern.
  bool hasMatch(String str) => _regex.hasMatch(str);

  @override
  String toString() => '/$pattern/$flags';
}

