import 'dart:math' as math;

import '../errors/jsonata_exception.dart';
import '../evaluator/environment.dart';
import '../utils/undefined.dart';

/// Numeric functions for JSONata.
class NumericFunctions {
  /// Registers all numeric functions with the environment.
  static void register(Environment env) {
    env.registerFunction(r'$number', _number);
    env.registerFunction(r'$abs', _abs);
    env.registerFunction(r'$floor', _floor);
    env.registerFunction(r'$ceil', _ceil);
    env.registerFunction(r'$round', _round);
    env.registerFunction(r'$power', _power);
    env.registerFunction(r'$sqrt', _sqrt);
    env.registerFunction(r'$random', _random);
    env.registerFunction(r'$sum', _sum);
    env.registerFunction(r'$max', _max);
    env.registerFunction(r'$min', _min);
    env.registerFunction(r'$average', _average);
    env.registerFunction(r'$formatNumber', _formatNumber);
    env.registerFunction(r'$formatBase', _formatBase);
    env.registerFunction(r'$formatInteger', _formatInteger);
    env.registerFunction(r'$parseInteger', _parseInteger);
  }

  static final _rand = math.Random();

  static dynamic _number(List<dynamic> args, dynamic input, Environment env) {
    final value = args.isNotEmpty ? args[0] : input;
    if (isUndefined(value)) return undefined;
    if (value is num) return value;
    if (value is String) {
      final parsed = num.tryParse(value);
      if (parsed == null) {
        throw JsonataException(
          'D3030',
          'Unable to cast value to a number: $value',
          position: -1,
        );
      }
      return parsed;
    }
    if (value is bool) return value ? 1 : 0;
    return undefined;
  }

  static dynamic _abs(List<dynamic> args, dynamic input, Environment env) {
    final value = args.isNotEmpty ? args[0] : input;
    if (isUndefined(value) || value is! num) return undefined;
    return value.abs();
  }

  static dynamic _floor(List<dynamic> args, dynamic input, Environment env) {
    final value = args.isNotEmpty ? args[0] : input;
    if (isUndefined(value) || value is! num) return undefined;
    return value.floor();
  }

  static dynamic _ceil(List<dynamic> args, dynamic input, Environment env) {
    final value = args.isNotEmpty ? args[0] : input;
    if (isUndefined(value) || value is! num) return undefined;
    return value.ceil();
  }

  static dynamic _round(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    final value = args[0];
    if (isUndefined(value) || value is! num) return undefined;

    final precision = args.length > 1 ? (args[1] as num).toInt() : 0;
    final multiplier = math.pow(10, precision);
    return (value * multiplier).round() / multiplier;
  }

  static dynamic _power(List<dynamic> args, dynamic input, Environment env) {
    if (args.length < 2) return undefined;
    final base = args[0];
    final exponent = args[1];
    if (base is! num || exponent is! num) return undefined;
    return math.pow(base, exponent);
  }

  static dynamic _sqrt(List<dynamic> args, dynamic input, Environment env) {
    final value = args.isNotEmpty ? args[0] : input;
    if (isUndefined(value) || value is! num) return undefined;
    if (value < 0) return undefined;
    return math.sqrt(value);
  }

  static dynamic _random(List<dynamic> args, dynamic input, Environment env) {
    return _rand.nextDouble();
  }

  static dynamic _sum(List<dynamic> args, dynamic input, Environment env) {
    final arr = args.isNotEmpty ? args[0] : input;
    if (arr is! List) return isUndefined(arr) ? undefined : arr;

    num total = 0;
    for (final item in arr) {
      if (item is num) {
        total += item;
      }
    }
    return total;
  }

  static dynamic _max(List<dynamic> args, dynamic input, Environment env) {
    final arr = args.isNotEmpty ? args[0] : input;
    if (arr is! List || arr.isEmpty) return undefined;

    num? maxVal;
    for (final item in arr) {
      if (item is num) {
        if (maxVal == null || item > maxVal) {
          maxVal = item;
        }
      }
    }
    return maxVal ?? undefined;
  }

  static dynamic _min(List<dynamic> args, dynamic input, Environment env) {
    final arr = args.isNotEmpty ? args[0] : input;
    if (arr is! List || arr.isEmpty) return undefined;

    num? minVal;
    for (final item in arr) {
      if (item is num) {
        if (minVal == null || item < minVal) {
          minVal = item;
        }
      }
    }
    return minVal ?? undefined;
  }

  static dynamic _average(List<dynamic> args, dynamic input, Environment env) {
    final arr = args.isNotEmpty ? args[0] : input;
    if (isUndefined(arr)) return undefined;
    // Single number - return as-is
    if (arr is num) return arr;
    if (arr is! List || arr.isEmpty) return undefined;

    num total = 0;
    var count = 0;
    for (final item in arr) {
      if (item is num) {
        total += item;
        count++;
      }
    }
    if (count == 0) return undefined;
    return total / count;
  }

  static dynamic _formatNumber(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    final value = args[0];
    if (value is! num) return undefined;
    // Basic implementation - full XPath picture format to be implemented
    return value.toString();
  }

  static dynamic _formatBase(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    final value = args[0];
    if (value is! num) return undefined;

    final radix = args.length > 1 ? (args[1] as num).toInt() : 10;
    if (radix < 2 || radix > 36) return undefined;

    return value.toInt().toRadixString(radix);
  }

  static dynamic _formatInteger(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    final value = args[0];
    if (value is! num) return undefined;
    // Basic implementation
    return value.toInt().toString();
  }

  static dynamic _parseInteger(List<dynamic> args, dynamic input, Environment env) {
    if (args.isEmpty) return undefined;
    final str = args[0];
    if (str is! String) return undefined;

    final radix = args.length > 1 ? (args[1] as num).toInt() : 10;
    return int.tryParse(str, radix: radix) ?? undefined;
  }
}

