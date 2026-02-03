import '../evaluator/environment.dart';
import '../utils/undefined.dart';

/// Object manipulation functions for JSONata.
class ObjectFunctions {
  /// Registers all object functions with the environment.
  static void register(Environment env) {
    env.registerFunction(r'$keys', _keys);
    env.registerFunction(r'$values', _values);
    env.registerFunction(r'$spread', _spread);
    env.registerFunction(r'$merge', _merge);
    env.registerFunction(r'$sift', _sift);
    env.registerFunction(r'$each', _each);
    env.registerFunction(r'$lookup', _lookup);
  }

  static dynamic _keys(List<dynamic> args, dynamic input, Environment env) {
    final obj = args.isNotEmpty ? args[0] : input;
    if (isUndefined(obj) || obj is! Map) return undefined;
    final keys = obj.keys.toList();
    // JSONata unwraps single-element arrays
    if (keys.length == 1) return keys.first;
    return keys;
  }

  static dynamic _values(List<dynamic> args, dynamic input, Environment env) {
    final obj = args.isNotEmpty ? args[0] : input;
    if (isUndefined(obj) || obj is! Map) return undefined;
    return obj.values.toList();
  }

  static dynamic _spread(List<dynamic> args, dynamic input, Environment env) {
    final obj = args.isNotEmpty ? args[0] : input;
    if (isUndefined(obj) || obj is! Map) return undefined;

    return obj.entries.map((e) => {e.key: e.value}).toList();
  }

  static dynamic _merge(List<dynamic> args, dynamic input, Environment env) {
    final arr = args.isNotEmpty ? args[0] : input;

    if (arr is! List) {
      if (arr is Map) return arr;
      return undefined;
    }

    final result = <String, dynamic>{};
    for (final item in arr) {
      if (item is Map<String, dynamic>) {
        result.addAll(item);
      } else if (item is Map) {
        for (final entry in item.entries) {
          result[entry.key.toString()] = entry.value;
        }
      }
    }

    return result;
  }

  static dynamic _sift(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    final obj = args[0];
    if (obj is! Map) return undefined;

    // Filter function - simplified implementation
    final result = <String, dynamic>{};
    for (final entry in obj.entries) {
      // For now, include all non-undefined values
      if (!isUndefined(entry.value)) {
        result[entry.key.toString()] = entry.value;
      }
    }

    return result;
  }

  static dynamic _each(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    final obj = args[0];
    if (obj is! Map) return undefined;

    // Returns array of values (callback handling to be implemented)
    return obj.values.toList();
  }

  static dynamic _lookup(List<dynamic> args, dynamic input, Environment env) {
    if (args.length < 2) return undefined;
    final obj = args[0];
    final key = args[1];

    if (obj is! Map) return undefined;
    if (key is! String) return undefined;

    return obj[key] ?? undefined;
  }
}

