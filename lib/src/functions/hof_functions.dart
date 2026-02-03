import '../errors/jsonata_exception.dart';
import '../evaluator/environment.dart';
import '../evaluator/evaluator.dart';
import '../utils/undefined.dart';

/// Higher-order functions for JSONata ($map, $filter, $reduce, $single, $sift).
class HofFunctions {
  /// Registers all higher-order functions with the environment.
  static void register(Environment env) {
    env.registerFunction(r'$map', _map);
    env.registerFunction(r'$filter', _filter);
    env.registerFunction(r'$reduce', _reduce);
    env.registerFunction(r'$single', _single);
  }

  /// Helper to invoke a function (LambdaClosure, NativeFunctionReference, or PartialApplication).
  static dynamic _invokeFunc(
      dynamic func, Evaluator evaluator, List<dynamic> args, dynamic input) {
    if (func is LambdaClosure) {
      return func.invoke(evaluator, args, input);
    }
    if (func is NativeFunctionReference) {
      return func.invoke(evaluator, args, input);
    }
    if (func is PartialApplication) {
      return func.invoke(evaluator, args, input);
    }
    return undefined;
  }

  /// Returns true if func is a callable function.
  static bool _isCallable(dynamic func) {
    return func is LambdaClosure ||
        func is NativeFunctionReference ||
        func is PartialApplication;
  }

  /// $map(array, function) - applies function to each element
  static dynamic _map(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;

    final arr = args[0];
    if (isUndefined(arr)) return undefined;

    // Check if first argument is actually an array (not a function)
    // T0410: Argument 1 of function $map must be an array
    if (_isCallable(arr)) {
      throw JsonataException(
        'T0410',
        'Argument 1 of function \$map must be an array',
        position: -1,
      );
    }

    final func = args.length > 1 ? args[1] : null;
    if (func == null || !_isCallable(func)) {
      return undefined;
    }

    final evaluator = env.evaluator;
    if (evaluator == null) return undefined;

    final list = arr is List ? arr : [arr];
    final result = <dynamic>[];

    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      // Lambda can receive (value, index, array)
      final mapped = _invokeFunc(func, evaluator, [item, i, list], input);
      if (!isUndefined(mapped)) {
        result.add(mapped);
      }
    }

    return result.isEmpty
        ? undefined
        : (result.length == 1 ? result.first : result);
  }

  /// $filter(array, function) - filters elements by predicate
  static dynamic _filter(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;

    final arr = args[0];
    if (isUndefined(arr)) return undefined;

    final func = args.length > 1 ? args[1] : null;
    if (func == null || !_isCallable(func)) {
      return undefined;
    }

    final evaluator = env.evaluator;
    if (evaluator == null) return undefined;

    final list = arr is List ? arr : [arr];
    final result = <dynamic>[];

    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      // Lambda can receive (value, index, array)
      final keep = _invokeFunc(func, evaluator, [item, i, list], input);
      if (_isTruthy(keep)) {
        result.add(item);
      }
    }

    return result.isEmpty
        ? undefined
        : (result.length == 1 ? result.first : result);
  }

  /// $reduce(array, function, init?) - reduces array to single value
  static dynamic _reduce(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;

    final arr = args[0];
    if (isUndefined(arr)) return undefined;

    final func = args.length > 1 ? args[1] : null;
    if (func == null || !_isCallable(func)) {
      return undefined;
    }

    // D3050: The second argument of $reduce must be a function with at least 2 parameters
    if (func is LambdaClosure && func.node.parameters.length < 2) {
      throw JsonataException(
        'D3050',
        'The second argument of \$reduce must be a function with at least 2 parameters',
        position: -1,
      );
    }

    final evaluator = env.evaluator;
    if (evaluator == null) return undefined;

    // Convert single value to list
    final list = arr is List ? arr : [arr];
    if (list.isEmpty) return undefined;

    // Initial value is optional third argument
    dynamic accumulator;
    int startIndex;

    if (args.length > 2 && !isUndefined(args[2])) {
      accumulator = args[2];
      startIndex = 0;
    } else {
      accumulator = list.first;
      startIndex = 1;
    }

    for (var i = startIndex; i < list.length; i++) {
      final item = list[i];
      // Lambda receives (accumulator, value, index, array)
      accumulator = _invokeFunc(func, evaluator, [accumulator, item], input);
    }

    return accumulator;
  }

  /// $single(array, function?) - returns single matching item or undefined
  static dynamic _single(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;

    final arr = args[0];
    if (isUndefined(arr)) return undefined;

    final list = arr is List ? arr : [arr];

    if (args.length == 1 || isUndefined(args[1])) {
      // No predicate - return single item if array has exactly one
      return list.length == 1 ? list.first : undefined;
    }

    final func = args[1];
    if (!_isCallable(func)) return undefined;

    final evaluator = env.evaluator;
    if (evaluator == null) return undefined;

    dynamic match;
    int matchCount = 0;

    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      final keep = _invokeFunc(func, evaluator, [item, i, list], input);
      if (_isTruthy(keep)) {
        match = item;
        matchCount++;
        if (matchCount > 1) return undefined;
      }
    }

    return matchCount == 1 ? match : undefined;
  }

  static bool _isTruthy(dynamic value) {
    if (isUndefined(value) || value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }
}
