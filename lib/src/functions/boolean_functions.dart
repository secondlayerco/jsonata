import '../evaluator/environment.dart';
import '../utils/undefined.dart';

/// Boolean functions for JSONata.
class BooleanFunctions {
  /// Registers all boolean functions with the environment.
  static void register(Environment env) {
    env.registerFunction(r'$boolean', _boolean);
    env.registerFunction(r'$not', _not);
    env.registerFunction(r'$exists', _exists);
  }

  static dynamic _boolean(List<dynamic> args, dynamic input, Environment env) {
    final value = args.isNotEmpty ? args[0] : input;
    return _isTruthy(value);
  }

  static dynamic _not(List<dynamic> args, dynamic input, Environment env) {
    final value = args.isNotEmpty ? args[0] : input;
    // $not(undefined) returns undefined
    if (isUndefined(value)) return undefined;
    return !_isTruthy(value);
  }

  static dynamic _exists(List<dynamic> args, dynamic input, Environment env) {
    final value = args.isNotEmpty ? args[0] : input;
    return !isUndefined(value);
  }

  static bool _isTruthy(dynamic value) {
    if (value == null || isUndefined(value)) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }
}

