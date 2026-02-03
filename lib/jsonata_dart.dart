/// A pure Dart implementation of JSONata - JSON query and transformation language.
///
/// JSONata is a lightweight query and transformation language for JSON data.
/// It provides a simple, expressive syntax for querying, filtering, and
/// transforming JSON structures.
///
/// ## Basic Usage
///
/// ```dart
/// import 'package:jsonata_dart/jsonata_dart.dart';
///
/// void main() {
///   // Simple path expression
///   final expr = Jsonata('Account.Order.Product.Price');
///   final result = expr.evaluate({'Account': {'Order': {'Product': {'Price': 42}}}});
///   print(result); // 42
///
///   // With aggregation
///   final sumExpr = Jsonata(r'$sum(numbers)');
///   final total = sumExpr.evaluate({'numbers': [1, 2, 3, 4, 5]});
///   print(total); // 15
/// }
/// ```
///
/// ## Features
///
/// - Path expressions for navigating JSON structures
/// - Predicates and filters for selecting specific elements
/// - Built-in functions for string, numeric, array, and object manipulation
/// - Lambda expressions and higher-order functions
/// - Variable binding and custom function registration
/// - Transform expressions for modifying JSON structures
///
/// See https://jsonata.org for the full language specification.
library;

export 'src/jsonata_impl.dart' show Jsonata;
export 'src/errors/jsonata_exception.dart' show JsonataException;
export 'src/parser/ast.dart' show AstNode;
