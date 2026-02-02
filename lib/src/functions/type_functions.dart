import '../evaluator/environment.dart';
import '../utils/undefined.dart';

/// Type checking and conversion functions for JSONata.
class TypeFunctions {
  /// Registers all type functions with the environment.
  static void register(Environment env) {
    env.registerFunction(r'$type', _type);
    env.registerFunction(r'$assert', _assert);
    env.registerFunction(r'$error', _error);
  }

  static dynamic _type(List<dynamic> args, dynamic input, Environment env) {
    final value = args.isNotEmpty ? args[0] : input;

    if (isUndefined(value)) return 'undefined';
    if (value == null) return 'null';
    if (value is bool) return 'boolean';
    if (value is num) return 'number';
    if (value is String) return 'string';
    if (value is List) return 'array';
    if (value is Map) return 'object';
    if (value is Function) return 'function';

    return 'unknown';
  }

  static dynamic _assert(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;

    final condition = args[0];
    final message = args.length > 1 ? args[1]?.toString() : 'Assertion failed';

    if (!_isTruthy(condition)) {
      throw Exception(message);
    }

    return true;
  }

  static dynamic _error(List<dynamic> args, dynamic input, Environment env) {
    final message = args.isNotEmpty ? args[0]?.toString() : 'Error';
    throw Exception(message);
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

