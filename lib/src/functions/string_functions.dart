import '../errors/jsonata_exception.dart';
import '../evaluator/environment.dart';
import '../evaluator/evaluator.dart';
import '../utils/jsonata_regex.dart';
import '../utils/undefined.dart';

/// String manipulation functions for JSONata.
class StringFunctions {
  /// Registers all string functions with the environment.
  static void register(Environment env) {
    env.registerFunction(r'$string', _string);
    env.registerFunction(r'$length', _length);
    env.registerFunction(r'$substring', _substring);
    env.registerFunction(r'$substringBefore', _substringBefore);
    env.registerFunction(r'$substringAfter', _substringAfter);
    env.registerFunction(r'$uppercase', _uppercase);
    env.registerFunction(r'$lowercase', _lowercase);
    env.registerFunction(r'$trim', _trim);
    env.registerFunction(r'$pad', _pad);
    env.registerFunction(r'$contains', _contains);
    env.registerFunction(r'$split', _split);
    env.registerFunction(r'$join', _join);
    env.registerFunction(r'$replace', _replace);
    env.registerFunction(r'$match', _match);
    env.registerFunction(r'$base64encode', _base64encode);
    env.registerFunction(r'$base64decode', _base64decode);
  }

  static dynamic _string(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return isUndefined(input) ? undefined : _stringify(input);
    final value = args[0];
    if (isUndefined(value)) return undefined;
    return _stringify(value);
  }

  static String _stringify(dynamic value) {
    if (value is String) return value;
    if (value is num) {
      if (value == value.toInt()) return value.toInt().toString();
      return value.toString();
    }
    if (value is bool) return value.toString();
    if (value == null) return 'null';
    // For objects and arrays, return JSON representation
    return value.toString();
  }

  static dynamic _length(List<dynamic> args, dynamic input, Environment env) {
    final str = args.isNotEmpty ? args[0] : input;
    if (isUndefined(str) || str == null) return undefined;
    if (str is String) return str.length;
    return undefined;
  }

  static dynamic _substring(
      List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    final str = args[0];
    if (isUndefined(str) || str is! String) return undefined;

    final start = args.length > 1 ? (args[1] as num).toInt() : 0;
    final length = args.length > 2 ? (args[2] as num).toInt() : null;

    final actualStart = start < 0 ? str.length + start : start;
    if (actualStart < 0 || actualStart >= str.length) return '';

    if (length == null) {
      return str.substring(actualStart);
    }
    final end = actualStart + length;
    return str.substring(actualStart, end.clamp(actualStart, str.length));
  }

  static dynamic _substringBefore(
      List<dynamic> args, dynamic input, Environment env) {
    if (args.length < 2) return undefined;
    final str = args[0];
    final chars = args[1];
    if (str is! String || chars is! String) return undefined;

    final index = str.indexOf(chars);
    if (index < 0) return str;
    return str.substring(0, index);
  }

  static dynamic _substringAfter(
      List<dynamic> args, dynamic input, Environment env) {
    if (args.length < 2) return undefined;
    final str = args[0];
    final chars = args[1];
    if (str is! String || chars is! String) return undefined;

    final index = str.indexOf(chars);
    if (index < 0) return str;
    return str.substring(index + chars.length);
  }

  static dynamic _uppercase(
      List<dynamic> args, dynamic input, Environment env) {
    // In context syntax like a.$uppercase(b), args[0] is context (might be object)
    // and args[1] is the actual argument. Check for valid string in order.
    dynamic str;
    if (args.isNotEmpty && args[0] is String) {
      str = args[0];
    } else if (args.length > 1 && args[1] is String) {
      str = args[1];
    } else if (input is String) {
      str = input;
    }
    if (str == null || isUndefined(str)) return undefined;
    return (str as String).toUpperCase();
  }

  static dynamic _lowercase(
      List<dynamic> args, dynamic input, Environment env) {
    // In context syntax like a.$lowercase(b), args[0] is context (might be object)
    // and args[1] is the actual argument. Check for valid string in order.
    dynamic str;
    if (args.isNotEmpty && args[0] is String) {
      str = args[0];
    } else if (args.length > 1 && args[1] is String) {
      str = args[1];
    } else if (input is String) {
      str = input;
    }
    if (str == null || isUndefined(str)) return undefined;
    return (str as String).toLowerCase();
  }

  static dynamic _trim(List<dynamic> args, dynamic input, Environment env) {
    final str = args.isNotEmpty ? args[0] : input;
    if (isUndefined(str) || str is! String) return undefined;
    return str.trim();
  }

  static dynamic _pad(List<dynamic> args, dynamic input, Environment env) {
    if (args.length < 2) return undefined;
    final str = args[0];
    final width = args[1];
    if (str is! String || width is! num) return undefined;

    final char = args.length > 2 && args[2] is String ? args[2] as String : ' ';
    final w = width.toInt();

    if (w >= 0) {
      return str.padRight(w.abs(), char);
    } else {
      return str.padLeft(w.abs(), char);
    }
  }

  static dynamic _contains(List<dynamic> args, dynamic input, Environment env) {
    if (args.length < 2) return false;
    final str = args[0];
    final pattern = args[1];
    if (str is! String) return false;

    if (pattern is String) {
      return str.contains(pattern);
    }
    if (pattern is JsonataRegex) {
      return pattern.hasMatch(str);
    }
    return false;
  }

  static dynamic _split(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    final str = args[0];
    if (str is! String) return undefined;

    final separator = args.length > 1 ? args[1] : '';
    final limit = args.length > 2 ? (args[2] as num).toInt() : null;

    List<String> parts;
    if (separator is String) {
      parts = str.split(separator);
    } else if (separator is JsonataRegex) {
      parts = str.split(separator.regex);
    } else {
      return undefined;
    }

    if (limit != null && limit > 0) {
      parts = parts.take(limit).toList();
    }
    return parts;
  }

  static dynamic _join(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    var arr = args[0];
    if (isUndefined(arr)) return undefined;

    // Convert single string to array
    if (arr is String) {
      arr = [arr];
    }
    if (arr is! List) return undefined;

    final separator =
        args.length > 1 && args[1] is String ? args[1] as String : '';
    return arr.map((e) => e?.toString() ?? '').join(separator);
  }

  static dynamic _replace(List<dynamic> args, dynamic input, Environment env) {
    if (args.length < 3) return undefined;

    // Handle both direct call: $replace(str, pattern, replacement)
    // and context call: context.$replace(str, pattern, replacement)
    // In context call, args[0] is the context object
    dynamic str;
    dynamic pattern;
    dynamic replacement;
    int limitArgIndex;

    if (args[0] is String) {
      // Direct call
      str = args[0];
      pattern = args[1];
      replacement = args[2];
      limitArgIndex = 3;
    } else if (args.length >= 4 && args[1] is String) {
      // Context call - args[0] is context, args[1] is string
      str = args[1];
      pattern = args[2];
      replacement = args[3];
      limitArgIndex = 4;
    } else {
      return undefined;
    }

    if (str is! String) return undefined;

    // Handle string pattern
    if (pattern is String) {
      if (replacement is! String) return undefined;
      final limit = args.length > limitArgIndex
          ? (args[limitArgIndex] as num).toInt()
          : -1;
      if (limit < 0) {
        return str.replaceAll(pattern, replacement);
      }
      if (limit == 0) return str;
      var result = str;
      for (var i = 0; i < limit; i++) {
        final idx = result.indexOf(pattern);
        if (idx < 0) break;
        result = result.replaceFirst(pattern, replacement);
      }
      return result;
    }

    // Handle regex pattern
    if (pattern is JsonataRegex) {
      final limit = args.length > limitArgIndex
          ? (args[limitArgIndex] as num).toInt()
          : -1;
      if (limit == 0) return str;

      final matches = pattern.allMatches(str).toList();
      if (matches.isEmpty) return str;

      // Check for potentially infinite replacements
      // If regex matches empty string and replacement references non-existent group
      if (replacement is String) {
        final hasEmptyMatch = matches.any((m) => m.start == m.end);
        if (hasEmptyMatch) {
          // Check if replacement references a non-existent capture group
          final groupRefs = RegExp(r'\$(\d+)').allMatches(replacement);
          for (final ref in groupRefs) {
            final groupNum = int.parse(ref.group(1)!);
            if (groupNum > 0 && groupNum > matches.first.groupCount) {
              throw JsonataException(
                'D1004',
                'Regular expression infinite loop detected',
                position: 0,
              );
            }
          }
        }
      }

      // Apply limit if specified
      final effectiveMatches =
          limit > 0 ? matches.take(limit).toList() : matches;

      // Handle function replacement (LambdaClosure from JSONata expressions)
      if (replacement is LambdaClosure) {
        return _replaceWithFunction(str, effectiveMatches, replacement, env);
      }

      if (replacement is! String) return undefined;
      return _replaceWithPattern(str, effectiveMatches, replacement);
    }

    return undefined;
  }

  /// Replace matches with a pattern string that may contain $0, $1, $2, etc.
  static String _replaceWithPattern(
      String str, List<RegExpMatch> matches, String replacement) {
    final result = StringBuffer();
    var lastEnd = 0;

    for (final match in matches) {
      // Add text before match
      result.write(str.substring(lastEnd, match.start));

      // Process replacement pattern
      final replaced = _processReplacement(replacement, match);
      result.write(replaced);

      lastEnd = match.end;
    }

    // Add remaining text
    result.write(str.substring(lastEnd));
    return result.toString();
  }

  /// Process a replacement string, substituting $0, $1, $2, etc.
  ///
  /// Rules:
  /// - $$ → literal $
  /// - $0 → entire match
  /// - $N → capture group N if it exists
  /// - If $N where N > groupCount, try to find longest valid prefix
  ///   e.g., $123 with 1 group → group 1 + literal "23"
  /// - If no valid group found:
  ///   - For single digit: consume $N, output empty
  ///   - For multi-digit: consume $ + first digit, output remaining digits
  static String _processReplacement(String replacement, RegExpMatch match) {
    final result = StringBuffer();
    var i = 0;

    while (i < replacement.length) {
      if (replacement[i] == r'$' && i + 1 < replacement.length) {
        final nextChar = replacement[i + 1];

        if (nextChar == r'$') {
          // $$ -> literal $
          result.write(r'$');
          i += 2;
        } else if (nextChar == '0') {
          // $0 -> entire match
          result.write(match.group(0) ?? '');
          i += 2;
        } else if (_isDigit(nextChar)) {
          // $1, $2, ..., $12, etc. - capture groups
          // Look ahead for multi-digit group numbers
          var numStr = nextChar;
          var j = i + 2;
          while (j < replacement.length && _isDigit(replacement[j])) {
            numStr += replacement[j];
            j++;
          }

          // Try to find longest valid group number (1-based)
          var found = false;
          for (var len = numStr.length; len >= 1; len--) {
            final subNum = int.parse(numStr.substring(0, len));
            if (subNum >= 1 && subNum <= match.groupCount) {
              result.write(match.group(subNum) ?? '');
              result
                  .write(numStr.substring(len)); // Remaining digits as literal
              i = j;
              found = true;
              break;
            }
          }
          if (!found) {
            // No valid group found
            if (numStr.length == 1) {
              // Single digit: consume $N, output empty
              i = j;
            } else {
              // Multi-digit: consume $ + first digit, output remaining digits
              result.write(numStr.substring(1));
              i = j;
            }
          }
        } else {
          // $x where x is not a digit - keep as is
          result.write(r'$');
          result.write(nextChar);
          i += 2;
        }
      } else {
        result.write(replacement[i]);
        i++;
      }
    }

    return result.toString();
  }

  static bool _isDigit(String c) {
    return c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  }

  /// Replace matches using a function (LambdaClosure).
  static dynamic _replaceWithFunction(String str, List<RegExpMatch> matches,
      LambdaClosure replacement, Environment env) {
    final evaluator = env.evaluator;
    if (evaluator == null) return undefined;

    final result = StringBuffer();
    var lastEnd = 0;

    for (final match in matches) {
      result.write(str.substring(lastEnd, match.start));

      // Create match object to pass to function
      final matchObj = <String, dynamic>{
        'match': match.group(0),
        'index': match.start,
        'groups': match.groupCount > 0
            ? List<String>.generate(
                match.groupCount, (i) => match.group(i + 1) ?? '')
            : <String>[],
      };

      // Call the replacement function using LambdaClosure.invoke()
      final replaced = replacement.invoke(evaluator, [matchObj], str);
      if (replaced is! String) {
        throw JsonataException(
          'D3012',
          'The replacement function must return a string',
          position: 0,
        );
      }
      result.write(replaced);
      lastEnd = match.end;
    }

    result.write(str.substring(lastEnd));
    return result.toString();
  }

  static dynamic _match(List<dynamic> args, dynamic input, Environment env) {
    if (args.length < 2) return undefined;
    final str = args[0];
    final pattern = args[1];
    if (str is! String) return undefined;

    JsonataRegex regex;
    if (pattern is JsonataRegex) {
      regex = pattern;
    } else if (pattern is String) {
      regex = JsonataRegex(pattern, 'g');
    } else {
      return undefined;
    }

    final matches = regex.allMatches(str);
    final results = <Map<String, dynamic>>[];

    for (final m in matches) {
      final matchResult = <String, dynamic>{
        'match': m.group(0),
        'index': m.start,
        'groups': m.groupCount > 0
            ? List<String>.generate(m.groupCount, (i) => m.group(i + 1) ?? '')
            : <String>[],
      };
      results.add(matchResult);

      // If not global, only return first match
      if (!regex.isGlobal) break;
    }

    if (results.isEmpty) return undefined;
    if (results.length == 1) return results[0];
    return results;
  }

  static dynamic _base64encode(
      List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    final str = args[0];
    if (str is! String) return undefined;
    // Basic implementation without importing dart:convert in this file
    // This will be properly implemented later
    return str; // Placeholder
  }

  static dynamic _base64decode(
      List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    final str = args[0];
    if (str is! String) return undefined;
    return str; // Placeholder
  }
}
