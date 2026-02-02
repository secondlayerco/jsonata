# Changelog

## 0.1.0

- Initial release
- Core JSONata language features:
  - Path expressions (`a.b.c`, `a[0]`, `a.b[c > 0]`)
  - Wildcards (`*`, `**`)
  - Array/object constructors
  - Arithmetic, comparison, and boolean operators
  - Conditional expressions (`a ? b : c`)
  - Variable binding (`$x := value`)
  - Lambda expressions (`function($x) { $x * 2 }`)
  - Object grouping operator (`items{category: $sum(price)}`)
  - Range operator (`[1..10]`)
- Built-in functions:
  - String: `$string`, `$length`, `$substring`, `$uppercase`, `$lowercase`, `$trim`, `$pad`, `$split`, `$join`, `$contains`, `$replace`
  - Numeric: `$number`, `$abs`, `$floor`, `$ceil`, `$round`, `$power`, `$sqrt`, `$random`, `$sum`, `$max`, `$min`, `$average`, `$formatNumber`, `$formatBase`, `$formatInteger`, `$parseInteger`
  - Array: `$count`, `$append`, `$sort`, `$reverse`, `$shuffle`, `$distinct`, `$zip`, `$flatten`
  - Object: `$keys`, `$values`, `$spread`, `$merge`, `$lookup`, `$each`
  - Boolean: `$boolean`, `$not`, `$exists`
  - Type: `$type`
  - Higher-order: `$map`, `$filter`, `$reduce`, `$single`
- Custom function registration
- Variable binding
- JSONata-compatible error codes

