# jsonata_dart

A pure Dart implementation of [JSONata](https://jsonata.org) - the JSON query and transformation language.

[![pub package](https://img.shields.io/pub/v/jsonata_dart.svg)](https://pub.dev/packages/jsonata_dart)

## Usage

```dart
import 'package:jsonata_dart/jsonata_dart.dart';

void main() {
  final data = {
    'Account': {
      'Name': 'Firefly',
      'Order': [
        {'Product': 'Hat', 'Price': 9.99},
        {'Product': 'Shoes', 'Price': 49.99},
      ]
    }
  };

  // Path expressions
  print(Jsonata('Account.Name').evaluate(data)); // "Firefly"

  // Aggregations
  print(Jsonata(r'$sum(Account.Order.Price)').evaluate(data)); // 59.98

  // Transformations
  print(Jsonata('Account.Order.Product').evaluate(data)); // ["Hat", "Shoes"]

  // Custom functions
  final expr = Jsonata(r'$double(value)');
  expr.registerFunction(r'$double', (args, input, env) => (args[0] as num) * 2);
  print(expr.evaluate({'value': 21})); // 42

  // Variable binding
  final expr2 = Jsonata(r'price * $tax');
  expr2.bind(r'$tax', 1.1);
  print(expr2.evaluate({'price': 100})); // 110.0

  // Regular expressions
  print(Jsonata(r'$match("hello world", /\w+/)').evaluate({}));
  // {"match": "hello", "index": 0, "groups": []}

  // Date/time functions
  print(Jsonata(r'$now()').evaluate({})); // Current ISO 8601 timestamp
  print(Jsonata(r'$fromMillis(1527152400000, "[D] [MNn] [Y]")').evaluate({})); // "24 May 2018"
  print(Jsonata(r'$toMillis("2018-05-24", "[Y]-[M01]-[D01]")').evaluate({})); // 1527120000000

  // Transform operator (function chaining)
  print(Jsonata(r'"hello" ~> $uppercase ~> $length').evaluate({})); // 5

  // Parent operator (access parent context)
  print(Jsonata(r'Account.Order.Product{`Product Name`: %.OrderID}').evaluate(data));
  // Groups products by name with their parent order ID

  // Sort operator
  print(Jsonata(r'Account.Order.Price^($)').evaluate(data)); // [9.99, 49.99]

  // Focus operator (bind current item to variable)
  print(Jsonata(r'Account.Order@$o.Product.{ "product": Product, "orderId": $o.OrderID }').evaluate(data));

  // Index bind operator (bind iteration index)
  print(Jsonata(r'Account.Order#$i.{ "index": $i, "product": Product }').evaluate(data));
}
```

## Features

### Implemented

- **Path expressions** - Navigate JSON structures with dot notation
- **Predicates and filters** - Filter arrays with `[condition]`
- **Wildcards** - `*` and `**` for matching
- **String functions** - `$string`, `$length`, `$substring`, `$substringBefore`, `$substringAfter`, `$uppercase`, `$lowercase`, `$trim`, `$pad`, `$contains`, `$split`, `$join`, `$replace`, `$match`, `$base64encode`, `$base64decode`
- **Numeric functions** - `$number`, `$abs`, `$floor`, `$ceil`, `$round`, `$power`, `$sqrt`, `$random`, `$formatNumber`, `$formatBase`, `$formatInteger`, `$parseInteger`
- **Aggregation functions** - `$sum`, `$max`, `$min`, `$average`, `$count`
- **Boolean functions** - `$boolean`, `$not`, `$exists`
- **Array functions** - `$append`, `$count`, `$sort`, `$reverse`, `$shuffle`, `$distinct`, `$zip`
- **Object functions** - `$keys`, `$values`, `$spread`, `$merge`, `$each`, `$sift`, `$type`, `$lookup`
- **Higher-order functions** - `$map`, `$filter`, `$reduce`, `$sift`, `$each`, `$single`
- **Regular expression functions** - `$match`, `$replace` with regex, `$contains` with regex, `$split` with regex
- **Date/time functions** - `$now`, `$millis`, `$fromMillis`, `$toMillis` with full XPath/XQuery picture string support
- **Transform operator** - `~>` for function chaining
- **Conditional expressions** - Ternary `? :` operator
- **Lambda expressions** - `function($x) { $x * 2 }`
- **Variable binding** - `$variable := value`
- **Partial application** - Using `?` placeholder
- **Custom functions** - Register your own functions
- **Parent operator** - `%` for accessing parent context in path expressions
- **Sort operator** - `^(expr)` for sorting arrays
- **Focus operator** - `@$var` for binding current item to a variable
- **Index bind operator** - `#$var` for binding iteration index to a variable

### Not Yet Implemented

- Async expressions

## Differences from JavaScript JSONata

This is a clean-room Dart implementation, not a transpilation. Key differences:

| Aspect | JavaScript | Dart |
|--------|------------|------|
| **Undefined** | Returns `undefined` | Returns `null` (internally uses sentinel) |
| **Exceptions** | Throws with `code`, `message` | Throws `JsonataException` with same codes |
| **Custom functions** | `expr.registerFunction(name, fn, signature)` | `expr.registerFunction(name, fn)` (no signature validation) |
| **Async** | Supports `async` expressions | Synchronous only |

## API

### `Jsonata(String expression)`

Compiles a JSONata expression.

### `evaluate(dynamic data)`

Evaluates the expression against JSON data. Returns the result or `null` if undefined.

### `registerFunction(String name, Function fn)`

Registers a custom function. The function receives `(List<dynamic> args, dynamic input, Environment env)`.

### `bind(String name, dynamic value)`

Binds a variable for use in the expression.

### `ast`

Returns the parsed AST for inspection.

## Error Handling

```dart
try {
  Jsonata('invalid[').evaluate({});
} on JsonataException catch (e) {
  print('${e.code}: ${e.message}'); // S0302: Expected ']'
}
```

Error codes follow the [JSONata specification](https://docs.jsonata.org/errors).

## License

MIT - see [LICENSE](LICENSE)

