import 'package:jsonata_dart/jsonata_dart.dart';

void main() {
  final data = {
    'Account': {
      'Name': 'Firefly',
      'Order': [
        {'Product': 'Hat', 'Price': 9.99, 'Quantity': 2},
        {'Product': 'Shoes', 'Price': 49.99, 'Quantity': 1},
        {'Product': 'Shirt', 'Price': 24.99, 'Quantity': 3},
      ]
    }
  };

  // Simple path expression
  print(Jsonata('Account.Name').evaluate(data));
  // Output: Firefly

  // Array traversal
  print(Jsonata('Account.Order.Product').evaluate(data));
  // Output: [Hat, Shoes, Shirt]

  // Filtering with predicates
  print(Jsonata(r'Account.Order[Price > 20].Product').evaluate(data));
  // Output: [Shoes, Shirt]

  // Aggregation functions
  print(Jsonata(r'$sum(Account.Order.Price)').evaluate(data));
  // Output: 84.97

  // Computed expressions
  print(Jsonata(r'$sum(Account.Order.(Price * Quantity))').evaluate(data));
  // Output: 144.94

  // Object construction
  print(Jsonata(r'{"total": $sum(Account.Order.Price), "count": $count(Account.Order)}').evaluate(data));
  // Output: {total: 84.97, count: 3}

  // Object grouping (aggregate by key)
  print(Jsonata(r'Account.Order{Product: Price}').evaluate(data));
  // Output: {Hat: 9.99, Shoes: 49.99, Shirt: 24.99}

  // Lambda and higher-order functions
  print(Jsonata(r'$map(Account.Order, function($o) { $o.Product & ": $" & $string($o.Price) })').evaluate(data));
  // Output: [Hat: $9.99, Shoes: $49.99, Shirt: $24.99]

  // Custom function
  final expr = Jsonata(r'$discount(Account.Order.Price, 0.1)');
  expr.registerFunction(r'$discount', (args, input, env) {
    final prices = args[0] as List;
    final rate = args[1] as num;
    return prices.map((p) => (p as num) * (1 - rate)).toList();
  });
  print(expr.evaluate(data));
  // Output: [8.991, 44.991, 22.491]
}

