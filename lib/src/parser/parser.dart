import '../errors/jsonata_exception.dart';
import 'ast.dart';
import 'tokenizer.dart';

/// Internal class to track parent nodes during AST processing.
class _ParentInfo {
  final ParentSlot slot;
  _ParentInfo(this.slot);
}

/// Result of processing a node for ancestry.
class _ProcessResult {
  final AstNode node;
  final List<ParentSlot> seekingParent;
  final bool tuple;

  _ProcessResult(this.node, {
    this.seekingParent = const [],
    this.tuple = false,
  });
}

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
    '^': 80,
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
    // Initial parent node - slot will be assigned during _processAst
    return ParentNode(position);
  }

  // Counters for parent slot labeling
  int _ancestorLabel = 0;
  int _ancestorIndex = 0;

  // Track parent nodes that need ancestry resolution
  final List<_ParentInfo> _ancestry = [];

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
    // Reset ancestry tracking
    _ancestorLabel = 0;
    _ancestorIndex = 0;
    _ancestry.clear();

    // Process the AST and resolve ancestry
    final result = _processNode(node);

    // Check for unresolved parent references at top level
    if (result.node is ParentNode || result.seekingParent.isNotEmpty) {
      throw JsonataException(
        'S0217',
        "The object representing the 'parent' cannot be derived from this expression",
        position: node.position,
      );
    }

    return result.node;
  }

  /// Process a node and its children, resolving parent references.
  _ProcessResult _processNode(AstNode node) {
    return switch (node) {
      final ParentNode n => _processParentNode(n),
      final PathNode n => _processPathNode(n),
      final FilterNode n => _processFilterNode(n),
      final BinaryNode n => _processBinaryNode(n),
      final UnaryNode n => _processUnaryNode(n),
      final ArrayNode n => _processArrayNode(n),
      final ObjectNode n => _processObjectNode(n),
      final BlockNode n => _processBlockNode(n),
      final ConditionalNode n => _processConditionalNode(n),
      final LambdaNode n => _processLambdaNode(n),
      final FunctionCallNode n => _processFunctionCallNode(n),
      final AssignmentNode n => _processAssignmentNode(n),
      final TransformNode n => _processTransformNode(n),
      final SortNode n => _processSortNode(n),
      final FocusNode n => _processFocusNode(n),
      final IndexBindNode n => _processIndexBindNode(n),
      final KeepArrayNode n => _processKeepArrayNode(n),
      final IndexNode n => _processIndexNode(n),
      final RangeNode n => _processRangeNode(n),
      _ => _ProcessResult(node), // Leaf nodes pass through unchanged
    };
  }

  /// Process a parent node - assign it a slot.
  _ProcessResult _processParentNode(ParentNode node) {
    final slot = ParentSlot(
      label: '!${_ancestorLabel++}',
      level: 1,
      index: _ancestorIndex++,
    );
    final newNode = ParentNode(node.position, slot: slot);
    _ancestry.add(_ParentInfo(slot));
    return _ProcessResult(newNode, seekingParent: [slot]);
  }

  /// Process a path node - this is where parent references are resolved.
  _ProcessResult _processPathNode(PathNode node) {
    // Process left side first
    final leftResult = _processNode(node.left);

    // Process right side
    final rightResult = _processNode(node.right);

    // Collect seeking parents from both sides
    final seekingParent = <ParentSlot>[...leftResult.seekingParent];

    // Collect all parent slots to resolve from right side
    // Note: When right is a ParentNode, _processParentNode already adds its slot to seekingParent,
    // so we don't need to add it again here.
    final slotsToResolve = <ParentSlot>[...rightResult.seekingParent];

    // Resolve each slot by seeking through the left side
    var modifiedLeft = leftResult.node;
    for (final slot in slotsToResolve) {
      final (newLeft, continueUp) = _seekParent(modifiedLeft, slot);
      modifiedLeft = newLeft;
      if (continueUp) {
        // Couldn't resolve here - propagate up
        seekingParent.add(slot);
      }
    }

    final newPath = PathNode(
      node.position,
      modifiedLeft,
      rightResult.node,
      keepArray: node.keepArray,
    );

    final tuple = leftResult.tuple || rightResult.tuple ||
                  seekingParent.isNotEmpty ||
                  _hasAncestorBinding(modifiedLeft);

    return _ProcessResult(newPath, seekingParent: seekingParent, tuple: tuple);
  }

  /// Check if a node or its descendants have ancestor bindings.
  bool _hasAncestorBinding(AstNode node) {
    if (node is NameNode && node.ancestor != null) return true;
    if (node is WildcardNode && node.ancestor != null) return true;
    if (node is PathNode) {
      return _hasAncestorBinding(node.left) || _hasAncestorBinding(node.right);
    }
    if (node is BlockNode) {
      return node.expressions.any(_hasAncestorBinding);
    }
    return false;
  }

  /// Check if a node ends with a FocusNode (for detecting contiguous focus steps).
  /// This is used to implement JSONata's rule that "multiple contiguous steps
  /// that bind the focus should be skipped" when resolving parent references.
  bool _endsWithFocus(AstNode node) {
    if (node is FocusNode) return true;
    if (node is FilterNode) return _endsWithFocus(node.expr);
    if (node is PathNode) return _endsWithFocus(node.right);
    return false;
  }

  /// Seek the parent through a node, decrementing level for name/wildcard,
  /// incrementing for parent. Returns the possibly modified node and whether resolution continues.
  /// This mirrors JavaScript's seekParent function.
  (AstNode node, bool continueUp) _seekParent(AstNode node, ParentSlot slot) {
    if (node is NameNode) {
      slot.level--;
      if (slot.level == 0) {
        // This node binds the ancestor
        return (node.withAncestor(slot), false);
      }
      return (node, true);
    }
    if (node is WildcardNode) {
      slot.level--;
      if (slot.level == 0) {
        // This node binds the ancestor
        return (node.withAncestor(slot), false);
      }
      return (node, true);
    }
    if (node is ParentNode) {
      // Parent of parent - need to go back further
      slot.level++;
      return (node, true);
    }
    if (node is FocusNode) {
      // Focus nodes do NOT decrement the level when seeking parent.
      // This is because focus bindings keep the navigation context at the parent level.
      // We still need to seek through the inner expression and propagate any modifications.
      final (modifiedExpr, continueUp) = _seekParent(node.expr, slot);
      if (!continueUp) {
        return (FocusNode(node.position, modifiedExpr, node.variable), false);
      }
      // Continue seeking - the level is not decremented
      return (FocusNode(node.position, modifiedExpr, node.variable), true);
    }
    if (node is BlockNode && node.expressions.isNotEmpty) {
      // Look in the last expression
      final (modifiedExpr, continueUp) = _seekParent(node.expressions.last, slot);
      if (!continueUp) {
        // Update the block with modified last expression
        final newExprs = [...node.expressions];
        newExprs[newExprs.length - 1] = modifiedExpr;
        return (BlockNode(node.position, newExprs), false);
      }
      return (node, true);
    }
    if (node is PathNode) {
      // Check for contiguous focus steps - if both right and left end with focus,
      // skip the right side entirely (per JSONata spec: "multiple contiguous steps
      // that bind the focus should be skipped")
      if (_endsWithFocus(node.right) && _endsWithFocus(node.left)) {
        // Skip the right side, go straight to left
        final (modifiedLeft, continueLeft) = _seekParent(node.left, slot);
        if (!continueLeft) {
          return (PathNode(node.position, modifiedLeft, node.right, keepArray: node.keepArray), false);
        }
        return (PathNode(node.position, modifiedLeft, node.right, keepArray: node.keepArray), true);
      }

      // Work backwards through path: right first, then left
      final (modifiedRight, continueRight) = _seekParent(node.right, slot);
      if (!continueRight) {
        return (PathNode(node.position, node.left, modifiedRight, keepArray: node.keepArray), false);
      }
      // Continue to left
      final (modifiedLeft, continueLeft) = _seekParent(node.left, slot);
      if (!continueLeft) {
        return (PathNode(node.position, modifiedLeft, modifiedRight, keepArray: node.keepArray), false);
      }
      return (PathNode(node.position, modifiedLeft, modifiedRight, keepArray: node.keepArray), true);
    }
    if (node is FilterNode) {
      // Seek through the filtered expression
      final (modifiedExpr, continueUp) = _seekParent(node.expr, slot);
      if (!continueUp) {
        return (FilterNode(node.position, modifiedExpr, node.predicate), false);
      }
      return (FilterNode(node.position, modifiedExpr, node.predicate), true);
    }
    // For other types, we can't derive parent - error will be caught at top level
    return (node, true);
  }

  _ProcessResult _processFilterNode(FilterNode node) {
    final exprResult = _processNode(node.expr);
    final predResult = _processNode(node.predicate);

    // Parent refs in predicate can reference the current item (expr)
    final seekingParent = <ParentSlot>[...exprResult.seekingParent];

    // Resolve parent slots from predicate against the filtered expression
    var modifiedExpr = exprResult.node;
    for (final slot in predResult.seekingParent) {
      final (newExpr, continueUp) = _seekParent(modifiedExpr, slot);
      modifiedExpr = newExpr;
      if (continueUp) {
        seekingParent.add(slot);
      }
    }

    final newNode = FilterNode(node.position, modifiedExpr, predResult.node);
    final tuple = exprResult.tuple || predResult.tuple || _hasAncestorBinding(modifiedExpr);
    return _ProcessResult(newNode, seekingParent: seekingParent, tuple: tuple);
  }

  _ProcessResult _processBinaryNode(BinaryNode node) {
    final leftResult = _processNode(node.left);
    final rightResult = _processNode(node.right);
    final seekingParent = [...leftResult.seekingParent, ...rightResult.seekingParent];
    final newNode = BinaryNode(node.position, node.operator, leftResult.node, rightResult.node);
    return _ProcessResult(newNode, seekingParent: seekingParent);
  }

  _ProcessResult _processUnaryNode(UnaryNode node) {
    final operandResult = _processNode(node.operand);
    final newNode = UnaryNode(node.position, node.operator, operandResult.node);
    return _ProcessResult(newNode, seekingParent: operandResult.seekingParent);
  }

  _ProcessResult _processArrayNode(ArrayNode node) {
    final seekingParent = <ParentSlot>[];
    final elements = <AstNode>[];
    for (final elem in node.elements) {
      final result = _processNode(elem);
      elements.add(result.node);
      seekingParent.addAll(result.seekingParent);
    }
    return _ProcessResult(ArrayNode(node.position, elements), seekingParent: seekingParent);
  }

  _ProcessResult _processObjectNode(ObjectNode node) {
    final seekingParent = <ParentSlot>[];
    final pairs = <ObjectPair>[];
    for (final pair in node.pairs) {
      final keyResult = _processNode(pair.key);
      final valueResult = _processNode(pair.value);
      pairs.add(ObjectPair(keyResult.node, valueResult.node));
      seekingParent.addAll(keyResult.seekingParent);
      seekingParent.addAll(valueResult.seekingParent);
    }
    return _ProcessResult(ObjectNode(node.position, pairs), seekingParent: seekingParent);
  }

  _ProcessResult _processBlockNode(BlockNode node) {
    final seekingParent = <ParentSlot>[];
    final expressions = <AstNode>[];
    for (final expr in node.expressions) {
      final result = _processNode(expr);
      expressions.add(result.node);
      seekingParent.addAll(result.seekingParent);
    }
    return _ProcessResult(BlockNode(node.position, expressions), seekingParent: seekingParent);
  }

  _ProcessResult _processConditionalNode(ConditionalNode node) {
    final condResult = _processNode(node.condition);
    final thenResult = _processNode(node.thenExpr);
    final elseResult = node.elseExpr != null ? _processNode(node.elseExpr!) : null;

    final seekingParent = [
      ...condResult.seekingParent,
      ...thenResult.seekingParent,
      if (elseResult != null) ...elseResult.seekingParent,
    ];

    final newNode = ConditionalNode(
      node.position,
      condResult.node,
      thenResult.node,
      elseResult?.node,
    );
    return _ProcessResult(newNode, seekingParent: seekingParent);
  }

  _ProcessResult _processLambdaNode(LambdaNode node) {
    final bodyResult = _processNode(node.body);
    // Lambda creates a new scope, so parent refs in body stay local
    final newNode = LambdaNode(node.position, node.parameters, bodyResult.node);
    return _ProcessResult(newNode);
  }

  _ProcessResult _processFunctionCallNode(FunctionCallNode node) {
    final funcResult = _processNode(node.function);
    final seekingParent = <ParentSlot>[...funcResult.seekingParent];
    final args = <AstNode>[];
    for (final arg in node.arguments) {
      final result = _processNode(arg);
      args.add(result.node);
      seekingParent.addAll(result.seekingParent);
    }
    final newNode = FunctionCallNode(node.position, funcResult.node, args);
    return _ProcessResult(newNode, seekingParent: seekingParent);
  }

  _ProcessResult _processAssignmentNode(AssignmentNode node) {
    final valueResult = _processNode(node.value);
    final newNode = AssignmentNode(node.position, node.name, valueResult.node);
    return _ProcessResult(newNode, seekingParent: valueResult.seekingParent);
  }

  _ProcessResult _processTransformNode(TransformNode node) {
    final exprResult = _processNode(node.expr);
    final updateResult = _processNode(node.update);
    final deleteResult = node.delete != null ? _processNode(node.delete!) : null;

    final seekingParent = [
      ...exprResult.seekingParent,
      ...updateResult.seekingParent,
      if (deleteResult != null) ...deleteResult.seekingParent,
    ];

    final newNode = TransformNode(
      node.position,
      exprResult.node,
      updateResult.node,
      delete: deleteResult?.node,
    );
    return _ProcessResult(newNode, seekingParent: seekingParent);
  }

  _ProcessResult _processSortNode(SortNode node) {
    final exprResult = _processNode(node.expr);

    // Parent refs in sort terms can reference the sorted item (expr)
    final seekingParent = <ParentSlot>[...exprResult.seekingParent];

    // Resolve parent slots from sort terms against the sorted expression
    var modifiedExpr = exprResult.node;
    final terms = <SortTerm>[];
    for (final term in node.terms) {
      final keyResult = _processNode(term.expr);
      terms.add(SortTerm(keyResult.node, descending: term.descending));

      // Resolve parent slots from this sort term against the sorted expression
      for (final slot in keyResult.seekingParent) {
        final (newExpr, continueUp) = _seekParent(modifiedExpr, slot);
        modifiedExpr = newExpr;
        if (continueUp) {
          seekingParent.add(slot);
        }
      }
    }

    final newNode = SortNode(node.position, modifiedExpr, terms);
    final tuple = exprResult.tuple || _hasAncestorBinding(modifiedExpr);
    return _ProcessResult(newNode, seekingParent: seekingParent, tuple: tuple);
  }

  _ProcessResult _processFocusNode(FocusNode node) {
    final exprResult = _processNode(node.expr);
    final newNode = FocusNode(node.position, exprResult.node, node.variable);
    return _ProcessResult(newNode, seekingParent: exprResult.seekingParent, tuple: true);
  }

  _ProcessResult _processIndexBindNode(IndexBindNode node) {
    final exprResult = _processNode(node.expr);
    final newNode = IndexBindNode(node.position, exprResult.node, node.variable);
    return _ProcessResult(newNode, seekingParent: exprResult.seekingParent, tuple: true);
  }

  _ProcessResult _processKeepArrayNode(KeepArrayNode node) {
    final exprResult = _processNode(node.expr);
    final newNode = KeepArrayNode(node.position, exprResult.node);
    return _ProcessResult(newNode, seekingParent: exprResult.seekingParent);
  }

  _ProcessResult _processIndexNode(IndexNode node) {
    final exprResult = _processNode(node.expr);
    final indexResult = _processNode(node.index);
    final newNode = IndexNode(node.position, exprResult.node, indexResult.node);
    return _ProcessResult(newNode, seekingParent: [...exprResult.seekingParent, ...indexResult.seekingParent]);
  }

  _ProcessResult _processRangeNode(RangeNode node) {
    final startResult = _processNode(node.start);
    final endResult = _processNode(node.end);
    final newNode = RangeNode(node.position, startResult.node, endResult.node);
    return _ProcessResult(newNode, seekingParent: [...startResult.seekingParent, ...endResult.seekingParent]);
  }
}
