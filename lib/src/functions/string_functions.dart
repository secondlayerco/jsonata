import '../evaluator/environment.dart';
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

  static dynamic _substring(List<dynamic> args, dynamic input, Environment env) {
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

  static dynamic _substringBefore(List<dynamic> args, dynamic input, Environment env) {
    if (args.length < 2) return undefined;
    final str = args[0];
    final chars = args[1];
    if (str is! String || chars is! String) return undefined;

    final index = str.indexOf(chars);
    if (index < 0) return str;
    return str.substring(0, index);
  }

  static dynamic _substringAfter(List<dynamic> args, dynamic input, Environment env) {
    if (args.length < 2) return undefined;
    final str = args[0];
    final chars = args[1];
    if (str is! String || chars is! String) return undefined;

    final index = str.indexOf(chars);
    if (index < 0) return str;
    return str.substring(index + chars.length);
  }

  static dynamic _uppercase(List<dynamic> args, dynamic input, Environment env) {
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

  static dynamic _lowercase(List<dynamic> args, dynamic input, Environment env) {
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
    return false;
  }

  static dynamic _split(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    final str = args[0];
    if (str is! String) return undefined;

    final separator = args.length > 1 ? args[1] : '';
    final limit = args.length > 2 ? (args[2] as num).toInt() : null;

    if (separator is! String) return undefined;

    var parts = str.split(separator);
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
    final str = args[0];
    final pattern = args[1];
    final replacement = args[2];

    if (str is! String || replacement is! String) return undefined;

    if (pattern is String) {
      final limit = args.length > 3 ? (args[3] as num).toInt() : -1;
      if (limit < 0) {
        return str.replaceAll(pattern, replacement);
      }
      var result = str;
      for (var i = 0; i < limit; i++) {
        result = result.replaceFirst(pattern, replacement);
      }
      return result;
    }
    return undefined;
  }

  static dynamic _match(List<dynamic> args, dynamic input, Environment env) {
    // Basic regex matching - to be fully implemented
    if (args.length < 2) return undefined;
    final str = args[0];
    final pattern = args[1];
    if (str is! String || pattern is! String) return undefined;

    try {
      final regex = RegExp(pattern);
      final matches = regex.allMatches(str);
      return matches.map((m) => {
        'match': m.group(0),
        'index': m.start,
        'groups': m.groupCount > 0
            ? List.generate(m.groupCount, (i) => m.group(i + 1))
            : <String>[],
      }).toList();
    } catch (e) {
      return undefined;
    }
  }

  static dynamic _base64encode(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    final str = args[0];
    if (str is! String) return undefined;
    // Basic implementation without importing dart:convert in this file
    // This will be properly implemented later
    return str; // Placeholder
  }

  static dynamic _base64decode(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    final str = args[0];
    if (str is! String) return undefined;
    return str; // Placeholder
  }
}

