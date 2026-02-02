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
}
```

## Differences from JavaScript JSONata

This is a clean-room Dart implementation, not a transpilation. Key differences:

| Aspect | JavaScript | Dart |
|--------|------------|------|
| **Undefined** | Returns `undefined` | Returns `null` (internally uses sentinel) |
| **Exceptions** | Throws with `code`, `message` | Throws `JsonataException` with same codes |
| **Custom functions** | `expr.registerFunction(name, fn, signature)` | `expr.registerFunction(name, fn)` (no signature validation) |
| **Async** | Supports `async` expressions | Synchronous only |

### Not Yet Implemented

- Regular expression functions (`$match`, `$replace` with regex)
- Date/time functions (`$now`, `$toMillis`, etc.)
- Parent operator (`%`)
- Sort operator (`^`)
- Transform operator (`~>`)
- Focus operator (`@`)

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

