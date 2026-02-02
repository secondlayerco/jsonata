import '../errors/jsonata_exception.dart';

/// Token types for JSONata lexical analysis.
enum TokenType {
  // Literals
  number,
  string,
  name,
  variable,
  regex,

  // Keywords
  trueKeyword,
  falseKeyword,
  nullKeyword,
  andKeyword,
  orKeyword,
  inKeyword,
  functionKeyword,

  // Operators
  dot, // .
  comma, // ,
  colon, // :
  semicolon, // ;
  questionMark, // ?
  leftParen, // (
  rightParen, // )
  leftBracket, // [
  rightBracket, // ]
  leftBrace, // {
  rightBrace, // }
  plus, // +
  minus, // -
  star, // *
  slash, // /
  percent, // %
  pipe, // |
  ampersand, // &
  caret, // ^
  tilde, // ~
  at, // @
  hash, // #
  equals, // =
  notEquals, // !=
  lessThan, // <
  greaterThan, // >
  lessEquals, // <=
  greaterEquals, // >=
  assign, // :=
  chain, // ~>
  range, // ..
  descendent, // **
  power, // **
  defaultOp, // ?:
  coalesce, // ??

  // Special
  eof,
  error,
}

/// A token produced by the tokenizer.
class Token {
  /// The type of this token.
  final TokenType type;

  /// The raw text of this token.
  final String value;

  /// The position in the source where this token starts.
  final int position;

  const Token(this.type, this.value, this.position);

  @override
  String toString() => 'Token($type, "$value", $position)';
}

/// Tokenizer for JSONata expressions.
///
/// Converts a JSONata expression string into a stream of tokens.
class Tokenizer {
  final String _source;
  int _position = 0;

  /// Creates a tokenizer for the given source expression.
  Tokenizer(this._source);

  /// Returns the current position in the source.
  int get position => _position;

  /// Returns true if we've reached the end of the source.
  bool get isAtEnd => _position >= _source.length;

  /// Peeks at the current character without consuming it.
  String? _peek([int offset = 0]) {
    final pos = _position + offset;
    if (pos >= _source.length) return null;
    return _source[pos];
  }

  /// Consumes and returns the current character.
  String _advance() {
    return _source[_position++];
  }

  /// Skips whitespace and comments.
  void _skipWhitespaceAndComments() {
    while (!isAtEnd) {
      final c = _peek();
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        _advance();
      } else if (c == '/' && _peek(1) == '*') {
        // Block comment
        _advance(); // /
        _advance(); // *
        while (!isAtEnd) {
          if (_peek() == '*' && _peek(1) == '/') {
            _advance(); // *
            _advance(); // /
            break;
          }
          _advance();
        }
      } else {
        break;
      }
    }
  }

  /// Returns the next token.
  Token nextToken() {
    _skipWhitespaceAndComments();

    if (isAtEnd) {
      return Token(TokenType.eof, '', _position);
    }

    final start = _position;
    final c = _advance();

    // Single character tokens
    switch (c) {
      case '.':
        if (_peek() == '.') {
          _advance();
          return Token(TokenType.range, '..', start);
        }
        return Token(TokenType.dot, '.', start);
      case ',':
        return Token(TokenType.comma, ',', start);
      case ';':
        return Token(TokenType.semicolon, ';', start);
      case '(':
        return Token(TokenType.leftParen, '(', start);
      case ')':
        return Token(TokenType.rightParen, ')', start);
      case '[':
        return Token(TokenType.leftBracket, '[', start);
      case ']':
        return Token(TokenType.rightBracket, ']', start);
      case '{':
        return Token(TokenType.leftBrace, '{', start);
      case '}':
        return Token(TokenType.rightBrace, '}', start);
    }

    // Continue in _nextTokenPart2
    return _nextTokenPart2(c, start);
  }

  Token _nextTokenPart2(String c, int start) {
    switch (c) {
      case '+':
        return Token(TokenType.plus, '+', start);
      case '-':
        return Token(TokenType.minus, '-', start);
      case '*':
        if (_peek() == '*') {
          _advance();
          return Token(TokenType.descendent, '**', start);
        }
        return Token(TokenType.star, '*', start);
      case '/':
        return Token(TokenType.slash, '/', start);
      case '%':
        return Token(TokenType.percent, '%', start);
      case '|':
        return Token(TokenType.pipe, '|', start);
      case '&':
        return Token(TokenType.ampersand, '&', start);
      case '^':
        return Token(TokenType.caret, '^', start);
      case '~':
        if (_peek() == '>') {
          _advance();
          return Token(TokenType.chain, '~>', start);
        }
        return Token(TokenType.tilde, '~', start);
      case '@':
        return Token(TokenType.at, '@', start);
      case '#':
        return Token(TokenType.hash, '#', start);
      case '=':
        return Token(TokenType.equals, '=', start);
      case '!':
        if (_peek() == '=') {
          _advance();
          return Token(TokenType.notEquals, '!=', start);
        }
        throw JsonataException.unexpectedToken('!', start);
      case '<':
        if (_peek() == '=') {
          _advance();
          return Token(TokenType.lessEquals, '<=', start);
        }
        return Token(TokenType.lessThan, '<', start);
      case '>':
        if (_peek() == '=') {
          _advance();
          return Token(TokenType.greaterEquals, '>=', start);
        }
        return Token(TokenType.greaterThan, '>', start);
      case ':':
        if (_peek() == '=') {
          _advance();
          return Token(TokenType.assign, ':=', start);
        }
        return Token(TokenType.colon, ':', start);
      case '?':
        if (_peek() == ':') {
          _advance();
          return Token(TokenType.defaultOp, '?:', start);
        }
        if (_peek() == '?') {
          _advance();
          return Token(TokenType.coalesce, '??', start);
        }
        return Token(TokenType.questionMark, '?', start);
    }

    // String literals
    if (c == '"' || c == "'") {
      return _scanString(c, start);
    }

    // Backtick-quoted names
    if (c == '`') {
      return _scanBacktickName(start);
    }

    // Numbers
    if (_isDigit(c)) {
      return _scanNumber(c, start);
    }

    // Names and keywords
    if (_isNameStart(c)) {
      return _scanName(c, start);
    }

    // Variables
    if (c == r'$') {
      return _scanVariable(start);
    }

    throw JsonataException.unexpectedToken(c, start);
  }

  Token _scanString(String quote, int start) {
    final buffer = StringBuffer();

    while (!isAtEnd) {
      final c = _advance();

      if (c == quote) {
        return Token(TokenType.string, buffer.toString(), start);
      }

      if (c == '\\') {
        if (isAtEnd) {
          throw JsonataException.unterminatedString(start);
        }
        final escaped = _advance();
        switch (escaped) {
          case 'n':
            buffer.write('\n');
          case 'r':
            buffer.write('\r');
          case 't':
            buffer.write('\t');
          case 'b':
            buffer.write('\b');
          case 'f':
            buffer.write('\f');
          case '\\':
            buffer.write('\\');
          case '/':
            buffer.write('/');
          case '"':
            buffer.write('"');
          case "'":
            buffer.write("'");
          case 'u':
            // Unicode escape
            if (_position + 4 > _source.length) {
              throw JsonataException.unterminatedString(start);
            }
            final hex = _source.substring(_position, _position + 4);
            final codePoint = int.tryParse(hex, radix: 16);
            if (codePoint == null) {
              throw JsonataException(
                'S0104',
                'Invalid unicode escape sequence',
                position: _position,
              );
            }
            buffer.write(String.fromCharCode(codePoint));
            _position += 4;
          default:
            // Invalid escape sequence
            throw JsonataException(
              'S0103',
              'Unsupported escape sequence: \\$escaped',
              position: _position - 1,
            );
        }
      } else {
        buffer.write(c);
      }
    }

    throw JsonataException.unterminatedString(start);
  }

  Token _scanBacktickName(int start) {
    final buffer = StringBuffer();

    while (!isAtEnd) {
      final c = _advance();
      if (c == '`') {
        return Token(TokenType.name, buffer.toString(), start);
      }
      buffer.write(c);
    }

    throw JsonataException(
      'S0105',
      'Quoted name not terminated',
      position: start,
    );
  }

  Token _scanNumber(String first, int start) {
    final buffer = StringBuffer(first);

    // Integer part
    while (!isAtEnd && _isDigit(_peek()!)) {
      buffer.write(_advance());
    }

    // Decimal part
    if (_peek() == '.' && _peek(1) != '.') {
      buffer.write(_advance()); // .
      while (!isAtEnd && _isDigit(_peek()!)) {
        buffer.write(_advance());
      }
    }

    // Exponent part
    if (_peek() == 'e' || _peek() == 'E') {
      buffer.write(_advance());
      if (_peek() == '+' || _peek() == '-') {
        buffer.write(_advance());
      }
      while (!isAtEnd && _isDigit(_peek()!)) {
        buffer.write(_advance());
      }
    }

    final numStr = buffer.toString();
    // Validate the number is not infinity (overflow)
    final parsed = double.tryParse(numStr);
    if (parsed == null || parsed.isInfinite || parsed.isNaN) {
      throw JsonataException(
        'S0102',
        'Number out of range: $numStr',
        position: start,
      );
    }

    return Token(TokenType.number, numStr, start);
  }

  Token _scanName(String first, int start) {
    final buffer = StringBuffer(first);

    while (!isAtEnd && _isNameChar(_peek()!)) {
      buffer.write(_advance());
    }

    final name = buffer.toString();

    // Check for keywords
    switch (name) {
      case 'true':
        return Token(TokenType.trueKeyword, name, start);
      case 'false':
        return Token(TokenType.falseKeyword, name, start);
      case 'null':
        return Token(TokenType.nullKeyword, name, start);
      case 'and':
        return Token(TokenType.andKeyword, name, start);
      case 'or':
        return Token(TokenType.orKeyword, name, start);
      case 'in':
        return Token(TokenType.inKeyword, name, start);
      case 'function':
      case 'λ': // Greek lowercase lambda (U+03BB) as alias for function
        return Token(TokenType.functionKeyword, name, start);
    }

    return Token(TokenType.name, name, start);
  }

  Token _scanVariable(int start) {
    final buffer = StringBuffer();

    // Check for special $$ variable (context root)
    if (!isAtEnd && _peek() == r'$') {
      buffer.write(_advance());
      // Token value is "$$" for root context reference
      return Token(TokenType.variable, r'$$', start);
    }

    while (!isAtEnd && _isNameChar(_peek()!)) {
      buffer.write(_advance());
    }

    return Token(TokenType.variable, buffer.toString(), start);
  }

  /// Scans a regex literal. Called when we know we're expecting a regex.
  Token scanRegex(int start) {
    final patternBuffer = StringBuffer();
    var escaped = false;
    var inCharClass = false;

    while (!isAtEnd) {
      final c = _advance();

      if (escaped) {
        patternBuffer.write('\\');
        patternBuffer.write(c);
        escaped = false;
        continue;
      }

      if (c == '\\') {
        escaped = true;
        continue;
      }

      if (c == '[') {
        inCharClass = true;
        patternBuffer.write(c);
        continue;
      }

      if (c == ']' && inCharClass) {
        inCharClass = false;
        patternBuffer.write(c);
        continue;
      }

      if (c == '/' && !inCharClass) {
        // End of pattern, scan flags
        final flagsBuffer = StringBuffer();
        while (!isAtEnd && _isRegexFlag(_peek()!)) {
          flagsBuffer.write(_advance());
        }
        final pattern = patternBuffer.toString();
        final flags = flagsBuffer.toString();
        return Token(TokenType.regex, '$pattern/$flags', start);
      }

      patternBuffer.write(c);
    }

    throw JsonataException.unterminatedRegex(start);
  }

  bool _isDigit(String c) {
    return c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  }

  bool _isNameStart(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) || // A-Z
        (code >= 97 && code <= 122) || // a-z
        c == '_' ||
        code > 127; // Unicode
  }

  bool _isNameChar(String c) {
    return _isNameStart(c) || _isDigit(c);
  }

  bool _isRegexFlag(String c) {
    return c == 'i' || c == 'm' || c == 's' || c == 'g';
  }
}
