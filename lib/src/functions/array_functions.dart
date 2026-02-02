import '../evaluator/environment.dart';
import '../utils/undefined.dart';

/// Array manipulation functions for JSONata.
class ArrayFunctions {
  /// Registers all array functions with the environment.
  static void register(Environment env) {
    env.registerFunction(r'$count', _count);
    env.registerFunction(r'$append', _append);
    env.registerFunction(r'$sort', _sort);
    env.registerFunction(r'$reverse', _reverse);
    env.registerFunction(r'$shuffle', _shuffle);
    env.registerFunction(r'$distinct', _distinct);
    env.registerFunction(r'$zip', _zip);
    env.registerFunction(r'$flatten', _flatten);
  }

  static dynamic _count(List<dynamic> args, dynamic input, Environment env) {
    final value = args.isNotEmpty ? args[0] : input;
    if (isUndefined(value)) return 0;
    if (value is List) return value.length;
    return 1;
  }

  static dynamic _append(List<dynamic> args, dynamic input, Environment env) {
    if (args.length < 2) return undefined;

    final arr1 = args[0];
    final arr2 = args[1];

    final list1 = arr1 is List ? arr1 : (isUndefined(arr1) ? <dynamic>[] : [arr1]);
    final list2 = arr2 is List ? arr2 : (isUndefined(arr2) ? <dynamic>[] : [arr2]);

    return [...list1, ...list2];
  }

  static dynamic _sort(List<dynamic> args, dynamic input, Environment env) {
    final arr = args.isNotEmpty ? args[0] : input;
    if (arr is! List) return isUndefined(arr) ? undefined : [arr];

    final sorted = List<dynamic>.from(arr);

    if (args.length > 1) {
      // Custom comparator function - to be implemented
      sorted.sort();
    } else {
      sorted.sort((a, b) {
        if (a is num && b is num) return a.compareTo(b);
        if (a is String && b is String) return a.compareTo(b);
        return 0;
      });
    }

    return sorted;
  }

  static dynamic _reverse(List<dynamic> args, dynamic input, Environment env) {
    final arr = args.isNotEmpty ? args[0] : input;
    if (arr is! List) return isUndefined(arr) ? undefined : [arr];
    return arr.reversed.toList();
  }

  static dynamic _shuffle(List<dynamic> args, dynamic input, Environment env) {
    final arr = args.isNotEmpty ? args[0] : input;
    if (arr is! List) return isUndefined(arr) ? undefined : [arr];
    final shuffled = List<dynamic>.from(arr);
    shuffled.shuffle();
    return shuffled;
  }

  static dynamic _distinct(List<dynamic> args, dynamic input, Environment env) {
    final arr = args.isNotEmpty ? args[0] : input;
    if (arr is! List) return isUndefined(arr) ? undefined : [arr];

    final seen = <dynamic>{};
    final result = <dynamic>[];

    for (final item in arr) {
      // Use a simple equality check for primitives
      if (!seen.contains(item)) {
        seen.add(item);
        result.add(item);
      }
    }

    return result;
  }

  static dynamic _zip(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;

    // Gather all arrays
    final arrays = <List<dynamic>>[];
    for (final arg in args) {
      if (arg is List) {
        arrays.add(arg);
      } else if (!isUndefined(arg)) {
        arrays.add([arg]);
      }
    }

    if (arrays.isEmpty) return undefined;

    final minLength = arrays.map((a) => a.length).reduce((a, b) => a < b ? a : b);
    final result = <List<dynamic>>[];

    for (var i = 0; i < minLength; i++) {
      result.add(arrays.map((arr) => arr[i]).toList());
    }

    return result;
  }

  static dynamic _flatten(List<dynamic> args, dynamic input, Environment env) {
    final arr = args.isNotEmpty ? args[0] : input;
    if (arr is! List) return isUndefined(arr) ? undefined : arr;

    final result = <dynamic>[];

    void flattenRecursive(List<dynamic> items) {
      for (final item in items) {
        if (item is List) {
          flattenRecursive(item);
        } else {
          result.add(item);
        }
      }
    }

    flattenRecursive(arr);
    return result;
  }
}

