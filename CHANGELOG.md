# Changelog

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

