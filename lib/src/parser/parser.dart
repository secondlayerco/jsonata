import '../errors/jsonata_exception.dart';
import 'ast.dart';
import 'tokenizer.dart';

/// Parser for JSONata expressions using Pratt parsing (top-down operator precedence).
///
/// Converts a stream of tokens into an Abstract Syntax Tree (AST).
class Parser {
  final Tokenizer _tokenizer;
  Token _current;

  /// Operator precedence table (higher = binds tighter)
  static const Map<String, int> _precedence = {
    // Binding operators
    ':=': 10,
    // Logical operators
    '??': 20,
    '?:': 20,
    '?': 20,
    '|': 20,
    '..': 20,
    'or': 25,
    'and': 30,
    // Comparison operators
    '=': 40,
    '!=': 40,
    '<': 40,
    '>': 40,
    '<=': 40,
    '>=': 40,
    'in': 40,
    '~>': 40,
    // Arithmetic operators
    '&': 50,
    '+': 50,
    '-': 50,
    '*': 60,
    '/': 60,
    '%': 60,
    '**': 60,
    // Access operators
    '{': 70,
    '.': 75,
    '[': 80,
    '(': 80,
    '@': 80,
    '#': 80,
  };

  /// Creates a parser for the given expression.
  Parser(String expression)
      : _tokenizer = Tokenizer(expression),
        _current = const Token(TokenType.eof, '', 0) {
    _advance();
  }

  /// Advances to the next token.
  void _advance() {
    _current = _tokenizer.nextToken();
  }

  /// Returns true if the current token matches the given type.
  bool _check(TokenType type) => _current.type == type;

  /// Consumes the current token if it matches the given type.
  bool _match(TokenType type) {
    if (_check(type)) {
      _advance();
      return true;
    }
    return false;
  }

  /// Expects the current token to be of the given type.
  void _expect(TokenType type, String expected) {
    if (!_check(type)) {
      throw JsonataException.expectedToken(
        expected,
        _current.value.isEmpty ? _current.type.name : _current.value,
        _current.position,
      );
    }
    _advance();
  }

  /// Gets the precedence of the current token.
  int _getPrecedence() {
    final op = _getOperator();
    return _precedence[op] ?? 0;
  }

  /// Gets the operator string for the current token.
  String? _getOperator() {
    return switch (_current.type) {
      TokenType.dot => '.',
      TokenType.leftBracket => '[',
      TokenType.leftParen => '(',
      TokenType.leftBrace => '{',
      TokenType.plus => '+',
      TokenType.minus => '-',
      TokenType.star => '*',
      TokenType.slash => '/',
      TokenType.percent => '%',
      TokenType.ampersand => '&',
      TokenType.equals => '=',
      TokenType.notEquals => '!=',
      TokenType.lessThan => '<',
      TokenType.greaterThan => '>',
      TokenType.lessEquals => '<=',
      TokenType.greaterEquals => '>=',
      TokenType.andKeyword => 'and',
      TokenType.orKeyword => 'or',
      TokenType.inKeyword => 'in',
      TokenType.assign => ':=',
      TokenType.chain => '~>',
      TokenType.range => '..',
      TokenType.descendent => '**',
      TokenType.questionMark => '?',
      TokenType.defaultOp => '?:',
      TokenType.coalesce => '??',
      TokenType.pipe => '|',
      TokenType.caret => '^',
      TokenType.at => '@',
      TokenType.hash => '#',
      _ => null,
    };
  }

  /// Parses the expression and returns the AST.
  AstNode parse() {
    if (_check(TokenType.eof)) {
      // Empty expression
      throw JsonataException(
        'S0500',
        'Empty expression',
        position: 0,
      );
    }

    final expr = _parseExpression(0);

    if (!_check(TokenType.eof)) {
      throw JsonataException.unexpectedToken(_current.value, _current.position);
    }

    return _processAst(expr);
  }

  /// Parses an expression with the given minimum precedence.
  AstNode _parseExpression(int minPrecedence) {
    var left = _parsePrefix();

    while (_getPrecedence() > minPrecedence) {
      left = _parseInfix(left);
    }

    return left;
  }

  /// Parses a prefix expression (literals, unary operators, etc.).
  AstNode _parsePrefix() {
    final token = _current;
    final position = token.position;

    return switch (token.type) {
      TokenType.number => _parseNumber(),
      TokenType.string => _parseString(),
      TokenType.trueKeyword => _parseBoolean(true),
      TokenType.falseKeyword => _parseBoolean(false),
      TokenType.nullKeyword => _parseNull(),
      TokenType.name => _parseName(),
      // Handle 'and', 'or', 'in' as field names when in prefix position
      TokenType.andKeyword ||
      TokenType.orKeyword ||
      TokenType.inKeyword =>
        _parseKeywordAsName(),
      TokenType.variable => _parseVariable(),
      TokenType.leftParen => _parseParenthesized(),
      TokenType.leftBracket => _parseArrayConstructor(),
      TokenType.leftBrace => _parseObjectConstructor(),
      TokenType.minus => _parseUnaryMinus(),
      TokenType.star => _parseWildcard(),
      TokenType.descendent => _parseDescendant(),
      TokenType.percent => _parseParent(),
      TokenType.functionKeyword => _parseLambda(),
      TokenType.pipe => _parseTransform(),
      TokenType.slash => _parseRegex(),
      _ => throw JsonataException.unexpectedToken(token.value, position),
    };
  }

  AstNode _parseNumber() {
    final token = _current;
    _advance();
    final value = num.parse(token.value);
    return NumberNode(token.position, value);
  }

  AstNode _parseString() {
    final token = _current;
    _advance();
    return StringNode(token.position, token.value);
  }

  AstNode _parseBoolean(bool value) {
    final position = _current.position;
    _advance();
    return BooleanNode(position, value);
  }

  AstNode _parseNull() {
    final position = _current.position;
    _advance();
    return NullNode(position);
  }

  AstNode _parseName() {
    final token = _current;
    _advance();
    return NameNode(token.position, token.value);
  }

  /// Parses keywords like 'and', 'or', 'in' as field names when in prefix position.
  AstNode _parseKeywordAsName() {
    final token = _current;
    _advance();
    return NameNode(token.position, token.value);
  }

  AstNode _parseVariable() {
    final token = _current;
    _advance();
    if (token.value.isEmpty) {
      // Just $ - context reference
      return ContextNode(token.position);
    }
    return VariableNode(token.position, token.value);
  }

  AstNode _parseParenthesized() {
    final position = _current.position;
    _advance(); // (

    if (_check(TokenType.rightParen)) {
      _advance();
      // Empty parentheses - returns undefined (empty block)
      return BlockNode(position, []);
    }

    // Check for lambda shorthand: (params) => body
    // For now, parse as block expression
    final expressions = <AstNode>[];
    expressions.add(_parseExpression(0));

    while (_match(TokenType.semicolon)) {
      if (_check(TokenType.rightParen)) break;
      expressions.add(_parseExpression(0));
    }

    _expect(TokenType.rightParen, ')');

    // Always wrap in BlockNode to create proper scope for variable bindings
    // Even single expressions in parens get their own scope in JSONata
    return BlockNode(position, expressions);
  }

  AstNode _parseArrayConstructor() {
    final position = _current.position;
    _advance(); // [

    final elements = <AstNode>[];

    if (!_check(TokenType.rightBracket)) {
      elements.add(_parseExpression(0));

      while (_match(TokenType.comma)) {
        if (_check(TokenType.rightBracket)) break;
        elements.add(_parseExpression(0));
      }
    }

    _expect(TokenType.rightBracket, ']');
    return ArrayNode(position, elements);
  }

  AstNode _parseObjectConstructor() {
    final position = _current.position;
    _advance(); // {

    final pairs = <ObjectPair>[];

    if (!_check(TokenType.rightBrace)) {
      pairs.add(_parseObjectPair());

      while (_match(TokenType.comma)) {
        if (_check(TokenType.rightBrace)) break;
        pairs.add(_parseObjectPair());
      }
    }

    _expect(TokenType.rightBrace, '}');
    return ObjectNode(position, pairs);
  }

  ObjectPair _parseObjectPair() {
    final key = _parseExpression(0);
    _expect(TokenType.colon, ':');
    final value = _parseExpression(0);
    return ObjectPair(key, value);
  }

  AstNode _parseUnaryMinus() {
    final position = _current.position;
    _advance(); // -
    final operand = _parseExpression(70); // High precedence for unary
    return UnaryNode(position, '-', operand);
  }

  AstNode _parseWildcard() {
    final position = _current.position;
    _advance(); // *
    return WildcardNode(position);
  }

  AstNode _parseDescendant() {
    final position = _current.position;
    _advance(); // **
    return DescendantNode(position);
  }

  AstNode _parseParent() {
    final position = _current.position;
    _advance(); // %
    return ParentNode(position);
  }

  AstNode _parseLambda() {
    final position = _current.position;
    _advance(); // function

    _expect(TokenType.leftParen, '(');

    final parameters = <String>[];
    if (!_check(TokenType.rightParen)) {
      if (!_check(TokenType.variable)) {
        throw JsonataException(
          'S0401',
          'Expected parameter name',
          position: _current.position,
        );
      }
      parameters.add(_current.value);
      _advance();

      while (_match(TokenType.comma)) {
        if (!_check(TokenType.variable)) {
          throw JsonataException(
            'S0401',
            'Expected parameter name',
            position: _current.position,
          );
        }
        parameters.add(_current.value);
        _advance();
      }
    }

    _expect(TokenType.rightParen, ')');
    _expect(TokenType.leftBrace, '{');

    final body = _parseExpression(0);

    _expect(TokenType.rightBrace, '}');

    return LambdaNode(position, parameters, body);
  }

  AstNode _parseTransform() {
    final position = _current.position;
    _advance(); // |

    final expr = _parseExpression(0);

    _expect(TokenType.pipe, '|');

    final update = _parseExpression(0);

    AstNode? delete;
    if (_match(TokenType.comma)) {
      delete = _parseExpression(0);
    }

    _expect(TokenType.pipe, '|');

    return TransformNode(position, expr, update, delete: delete);
  }

  AstNode _parseRegex() {
    final position = _current.position;
    // The tokenizer already consumed the opening /
    // We need to scan the regex pattern
    final token = _tokenizer.scanRegex(position);
    _advance(); // Move past the regex token

    final parts = token.value.split('/');
    final pattern = parts[0];
    final flags = parts.length > 1 ? parts[1] : '';

    return RegexNode(position, pattern, flags);
  }

  /// Parses an infix expression (binary operators, function calls, etc.).
  AstNode _parseInfix(AstNode left) {
    final token = _current;
    final position = token.position;
    final op = _getOperator();

    return switch (token.type) {
      TokenType.dot => _parsePath(left),
      TokenType.leftBracket => _parseIndex(left),
      TokenType.leftParen => _parseFunctionCall(left),
      TokenType.leftBrace => _parseObjectGrouping(left),
      TokenType.questionMark => _parseConditional(left),
      TokenType.assign => _parseAssignment(left),
      TokenType.range => _parseRange(left),
      TokenType.caret => _parseSort(left),
      TokenType.at => _parseFocus(left),
      TokenType.hash => _parseIndexBind(left),
      _ => _parseBinaryOperator(left, op!, position),
    };
  }

  AstNode _parsePath(AstNode left) {
    final position = _current.position;
    _advance(); // .

    final right = _parseExpression(_precedence['.']!);
    return PathNode(position, left, right);
  }

  AstNode _parseIndex(AstNode left) {
    final position = _current.position;
    _advance(); // [

    // Check for empty brackets [] (keep-array operator)
    if (_check(TokenType.rightBracket)) {
      _advance(); // ]
      return KeepArrayNode(position, left);
    }

    final index = _parseExpression(0);
    _expect(TokenType.rightBracket, ']');

    // Check if this is a filter or an index
    // In JSONata, [expr] after a path is either:
    // - A predicate/filter if the result is boolean
    // - An index if the result is numeric
    // We'll determine this at evaluation time
    return FilterNode(position, left, index);
  }

  AstNode _parseFunctionCall(AstNode left) {
    final position = _current.position;
    _advance(); // (

    final arguments = <AstNode>[];

    if (!_check(TokenType.rightParen)) {
      arguments.add(_parseArgument());

      while (_match(TokenType.comma)) {
        if (_check(TokenType.rightParen)) break;
        arguments.add(_parseArgument());
      }
    }

    _expect(TokenType.rightParen, ')');
    return FunctionCallNode(position, left, arguments);
  }

  AstNode _parseArgument() {
    // Check for partial application placeholder
    if (_check(TokenType.questionMark)) {
      final position = _current.position;
      _advance();
      return PlaceholderNode(position);
    }
    return _parseExpression(0);
  }

  AstNode _parseObjectGrouping(AstNode left) {
    // This is object grouping: expr{key: value}
    // Used for grouping/aggregation
    final position = _current.position;
    _advance(); // {

    final pairs = <ObjectPair>[];

    if (!_check(TokenType.rightBrace)) {
      pairs.add(_parseObjectPair());

      while (_match(TokenType.comma)) {
        if (_check(TokenType.rightBrace)) break;
        pairs.add(_parseObjectPair());
      }
    }

    _expect(TokenType.rightBrace, '}');

    // Create a binary node representing grouping operation
    return BinaryNode(position, '{', left, ObjectNode(position, pairs));
  }

  AstNode _parseConditional(AstNode condition) {
    final position = _current.position;
    _advance(); // ?

    final thenExpr = _parseExpression(0);

    AstNode? elseExpr;
    if (_match(TokenType.colon)) {
      elseExpr = _parseExpression(0);
    }

    return ConditionalNode(position, condition, thenExpr, elseExpr);
  }

  AstNode _parseAssignment(AstNode left) {
    final position = _current.position;
    _advance(); // :=

    // Left must be a variable reference
    if (left is! VariableNode) {
      throw JsonataException(
        'S0402',
        'Left side of := must be a variable name',
        position: position,
      );
    }

    // Use precedence - 1 to allow chained assignments (right-associative)
    final value = _parseExpression(_precedence[':=']! - 1);
    return AssignmentNode(position, left.name, value);
  }

  AstNode _parseRange(AstNode left) {
    final position = _current.position;
    _advance(); // ..

    final right = _parseExpression(_precedence['..']!);
    return RangeNode(position, left, right);
  }

  AstNode _parseSort(AstNode left) {
    final position = _current.position;
    _advance(); // ^

    _expect(TokenType.leftParen, '(');

    final terms = <SortTerm>[];
    terms.add(_parseSortTerm());

    while (_match(TokenType.comma)) {
      terms.add(_parseSortTerm());
    }

    _expect(TokenType.rightParen, ')');

    return SortNode(position, left, terms);
  }

  SortTerm _parseSortTerm() {
    var descending = false;

    if (_match(TokenType.lessThan)) {
      descending = false;
    } else if (_match(TokenType.greaterThan)) {
      descending = true;
    }

    final expr = _parseExpression(0);
    return SortTerm(expr, descending: descending);
  }

  AstNode _parseFocus(AstNode left) {
    final position = _current.position;
    _advance(); // @

    // Expect a variable name
    if (!_check(TokenType.variable)) {
      throw JsonataException(
        'S0403',
        'Expected variable name after @',
        position: _current.position,
      );
    }

    final variable = _current.value;
    _advance();

    return FocusNode(position, left, variable);
  }

  AstNode _parseIndexBind(AstNode left) {
    final position = _current.position;
    _advance(); // #

    // Expect a variable name
    if (!_check(TokenType.variable)) {
      throw JsonataException(
        'S0404',
        'Expected variable name after #',
        position: _current.position,
      );
    }

    final variable = _current.value;
    _advance();

    return IndexBindNode(position, left, variable);
  }

  AstNode _parseBinaryOperator(AstNode left, String op, int position) {
    _advance(); // consume operator

    // Handle right-associativity for some operators
    // Note: ~> (chain operator) is left-associative so a ~> b ~> c = (a ~> b) ~> c
    final rightAssociative = op == ':=';
    final prec = _precedence[op]!;
    final nextPrec = rightAssociative ? prec - 1 : prec;

    final right = _parseExpression(nextPrec);
    return BinaryNode(position, op, left, right);
  }

  /// Post-processes the AST after parsing.
  ///
  /// This handles:
  /// - Setting up parent references for path navigation
  /// - Identifying tail calls for optimization
  /// - Other semantic analysis
  AstNode _processAst(AstNode node) {
    // For now, just return the node as-is
    // More sophisticated processing can be added later
    return node;
  }
}
