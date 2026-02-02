import 'dart:async';

import 'errors/jsonata_exception.dart';
import 'evaluator/environment.dart';
import 'evaluator/evaluator.dart';
import 'parser/ast.dart';
import 'parser/parser.dart';
import 'utils/undefined.dart';
import 'functions/string_functions.dart';
import 'functions/numeric_functions.dart';
import 'functions/array_functions.dart';
import 'functions/object_functions.dart';
import 'functions/boolean_functions.dart';
import 'functions/type_functions.dart';
import 'functions/hof_functions.dart';
import 'functions/datetime_functions.dart';

/// Main entry point for JSONata expression evaluation.
///
/// Example usage:
/// ```dart
/// final jsonata = Jsonata('Account.Order.Product.Price');
/// final result = jsonata.evaluate({'Account': {'Order': [{'Product': {'Price': 10}}]}});
/// ```
class Jsonata {
  final String _expression;
  final AstNode _ast;
  final Environment _environment;
  final Evaluator _evaluator = Evaluator();

  /// Creates a JSONata expression evaluator.
  ///
  /// Throws [JsonataException] if the expression is invalid.
  Jsonata(String expression)
      : _expression = expression,
        _ast = Parser(expression).parse(),
        _environment = Environment() {
    _environment.setEvaluator(_evaluator);
    _registerBuiltInFunctions();
  }

  /// Returns the original expression string.
  String get expression => _expression;

  /// Returns the parsed AST (for debugging/introspection).
  AstNode get ast => _ast;

  /// Evaluates the expression against the given input data.
  ///
  /// Returns the result of the evaluation, or `null` if the result
  /// is undefined in JSONata terms.
  ///
  /// Throws [JsonataException] if evaluation fails.
  dynamic evaluate(dynamic input) {
    // Reset the evaluation timestamp for $now() and $millis()
    DateTimeFunctions.resetTimestamp();
    _environment.input = input;
    final result = _evaluator.evaluate(_ast, input, _environment);
    return normalizeResult(result);
  }

  /// Evaluates the expression asynchronously.
  ///
  /// This is useful when custom async functions are registered.
  Future<dynamic> evaluateAsync(dynamic input) async {
    // For now, just wrap synchronous evaluation
    // Async support will be added when needed for async functions
    return evaluate(input);
  }

  /// Registers a custom function.
  ///
  /// The function will be available in expressions by the given name.
  ///
  /// Example:
  /// ```dart
  /// jsonata.registerFunction('double', (args, input, env) {
  ///   final num = args[0] as num;
  ///   return num * 2;
  /// });
  /// ```
  void registerFunction(String name, JsonataFunction function) {
    _environment.registerFunction(name, function);
  }

  /// Binds a variable to be available in expressions.
  ///
  /// Example:
  /// ```dart
  /// jsonata.bind('threshold', 100);
  /// // Now $threshold can be used in expressions
  /// ```
  void bind(String name, dynamic value) {
    _environment.bind(name, value);
  }

  void _registerBuiltInFunctions() {
    // String functions
    StringFunctions.register(_environment);

    // Numeric functions
    NumericFunctions.register(_environment);

    // Array functions
    ArrayFunctions.register(_environment);

    // Object functions
    ObjectFunctions.register(_environment);

    // Boolean functions
    BooleanFunctions.register(_environment);

    // Type functions
    TypeFunctions.register(_environment);

    // Higher-order functions
    HofFunctions.register(_environment);

    // Date/Time functions
    DateTimeFunctions.register(_environment);
  }
}

