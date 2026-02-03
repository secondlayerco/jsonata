# Changelog

## 0.3.2

- Fixed LICENSE file format for proper OSI license recognition
- Fixed static analysis warnings and applied code formatting

## 0.3.1

- **Performance optimizations** - Significant performance improvements for common query patterns:
  - Fast-path for simple name-only path expressions (`a.b.c`)
  - Fast-path for array index access (positive and negative indices)
  - Fast-path for paths with simple numeric index filters (`a.b[0].c[0]`)
  - Fast-path for simple equality filter predicates (`arr[field = 'value']`)
  - Fast-path for array projection in path expressions (`arr.fieldName`)
  - Optimized `normalizeResult` to avoid deep traversal of raw JSON
  - Optimized path evaluation for simple left-side patterns
- **Bug fix** - Fixed array constructor flattening in path expressions (`arr.[field].next`)

## 0.3.0

- **Parent operator** (`%`) - Reference parent objects in path expressions
- **Sort operator** (`^(...)`) - Sort arrays by specified keys with ascending/descending support
- **Focus operator** (`@$var`) - Bind current item to a variable while keeping navigation context at parent level
- **Index bind operator** (`#$var`) - Bind iteration index to a variable
- Fixed contiguous focus steps handling per JSONata specification
- Fixed `$keys` to unwrap single-element arrays
- 726 tests passing (672 suite + 54 unit)

## 0.2.0

- **Date/time functions**:
  - `$now([picture [, timezone]])` - Returns current timestamp in ISO 8601 format or formatted with picture string
  - `$millis()` - Returns current timestamp as milliseconds since Unix epoch
  - `$fromMillis(number [, picture [, timezone]])` - Convert milliseconds to formatted string
  - `$toMillis(timestamp [, picture])` - Parse timestamp string to milliseconds
  - Full XPath/XQuery picture string support for date/time formatting and parsing
  - All component specifiers: Y, M, D, d, F, W, w, X, x, H, h, P, m, s, f, Z, z
  - Presentation modifiers: numeric, name, ordinal, roman, words
- **Regular expression functions**:
  - `$match(string, regex [, limit])` - Find regex matches with match objects
  - `$replace(string, regex, replacement)` - Replace with regex, capture groups, or lambda functions
  - `$contains(string, regex)` - Test if string matches regex
  - `$split(string, regex [, limit])` - Split string by regex pattern
  - Partial application support with `?` placeholder
- **Transform operator** (`~>`) - Function chaining with left-associativity
- **Bug fixes**:
  - Fixed `~>` operator to be left-associative (so `a ~> b ~> c` = `(a ~> b) ~> c`)
- **Error handling improvements**:
  - D3132: Unknown component specifier in date/time picture
  - D3133: Unsupported name format for component
  - D3136: Underspecified date/time (gaps or unsupported formats)
- 661 tests passing (607 suite + 54 unit)

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

