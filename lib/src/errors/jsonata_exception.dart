/// Exception thrown when JSONata encounters an error during parsing or evaluation.
///
/// Error codes follow the JSONata specification:
/// - S0xxx: Syntax errors during parsing
/// - T0xxx: Type errors during evaluation
/// - D0xxx: Dynamic/runtime errors during evaluation
class JsonataException implements Exception {
  /// The error code (e.g., "S0101", "T2001", "D3001")
  final String code;

  /// Human-readable error message
  final String message;

  /// Character position in the expression where the error occurred (if applicable)
  final int? position;

  /// The token that caused the error (if applicable)
  final String? token;

  /// The value that caused the error (if applicable)
  final dynamic value;

  /// Creates a new JSONata exception.
  const JsonataException(
    this.code,
    this.message, {
    this.position,
    this.token,
    this.value,
  });

  @override
  String toString() {
    final buffer = StringBuffer('JsonataException: $code - $message');
    if (position != null) {
      buffer.write(' at position $position');
    }
    if (token != null) {
      buffer.write(' (token: "$token")');
    }
    return buffer.toString();
  }

  /// Creates a syntax error for an unterminated string.
  factory JsonataException.unterminatedString(int position) {
    return JsonataException(
      'S0101',
      'String literal not terminated',
      position: position,
    );
  }

  /// Creates a syntax error for an unexpected token.
  factory JsonataException.unexpectedToken(String token, int position) {
    return JsonataException(
      'S0201',
      'Unexpected token: $token',
      position: position,
      token: token,
    );
  }

  /// Creates a syntax error for an expected token that was not found.
  factory JsonataException.expectedToken(
    String expected,
    String found,
    int position,
  ) {
    return JsonataException(
      'S0202',
      "Expected '$expected', found '$found'",
      position: position,
      token: found,
    );
  }

  /// Creates a syntax error for an invalid number.
  factory JsonataException.invalidNumber(String token, int position) {
    return JsonataException(
      'S0102',
      'Invalid number: $token',
      position: position,
      token: token,
    );
  }

  /// Creates a syntax error for an unterminated regex.
  factory JsonataException.unterminatedRegex(int position) {
    return JsonataException(
      'S0302',
      'Regular expression not terminated',
      position: position,
    );
  }

  /// Creates a syntax error for an invalid regex.
  factory JsonataException.invalidRegex(String pattern, int position) {
    return JsonataException(
      'S0301',
      'Invalid regular expression: $pattern',
      position: position,
      token: pattern,
    );
  }

  /// Creates a type error for an operation that cannot be applied.
  factory JsonataException.cannotApplyOperator(
    String operator,
    dynamic left,
    dynamic right,
  ) {
    return JsonataException(
      'T2001',
      'Cannot apply operator "$operator" to operands',
      token: operator,
      value: [left, right],
    );
  }

  /// Creates a type error for wrong argument type.
  factory JsonataException.wrongArgumentType(
    String functionName,
    int argIndex,
    String expected,
    dynamic actual,
  ) {
    return JsonataException(
      'T0410',
      'Argument ${argIndex + 1} of function "$functionName" must be $expected',
      token: functionName,
      value: actual,
    );
  }

  /// Creates a runtime error for undefined variable.
  factory JsonataException.undefinedVariable(String name, int position) {
    return JsonataException(
      'D2014',
      'Variable "$name" is not defined',
      position: position,
      token: name,
    );
  }

  /// Creates a runtime error for function not found.
  factory JsonataException.functionNotFound(String name, int position) {
    return JsonataException(
      'D3001',
      'Function "$name" is not defined',
      position: position,
      token: name,
    );
  }

  /// Creates a runtime error for division by zero.
  factory JsonataException.divisionByZero() {
    return const JsonataException(
      'D2001',
      'Division by zero',
    );
  }

  /// Creates a runtime error for stack overflow (infinite recursion).
  factory JsonataException.stackOverflow() {
    return const JsonataException(
      'D2002',
      'Stack overflow - possible infinite recursion',
    );
  }
}

