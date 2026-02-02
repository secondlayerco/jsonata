/// Abstract Syntax Tree (AST) node definitions for JSONata expressions.
///
/// The AST represents the parsed structure of a JSONata expression.
/// Each node type corresponds to a different language construct.
library;

/// Base class for all AST nodes.
sealed class AstNode {
  /// The character position in the source expression where this node starts.
  final int position;

  /// Creates an AST node at the given position.
  const AstNode(this.position);

  /// Whether this node should keep its array wrapper in path expressions.
  bool get keepArray => false;
}

/// A numeric literal value.
class NumberNode extends AstNode {
  /// The numeric value.
  final num value;

  const NumberNode(super.position, this.value);

  @override
  String toString() => 'NumberNode($value)';
}

/// A string literal value.
class StringNode extends AstNode {
  /// The string value (with escape sequences processed).
  final String value;

  const StringNode(super.position, this.value);

  @override
  String toString() => 'StringNode("$value")';
}

/// A boolean literal value.
class BooleanNode extends AstNode {
  /// The boolean value.
  final bool value;

  const BooleanNode(super.position, this.value);

  @override
  String toString() => 'BooleanNode($value)';
}

/// A null literal value.
class NullNode extends AstNode {
  const NullNode(super.position);

  @override
  String toString() => 'NullNode()';
}

/// A regular expression literal.
class RegexNode extends AstNode {
  /// The regex pattern.
  final String pattern;

  /// The regex flags (e.g., "i", "m", "g").
  final String flags;

  const RegexNode(super.position, this.pattern, this.flags);

  @override
  String toString() => 'RegexNode(/$pattern/$flags)';
}

/// A name/identifier reference (field access).
class NameNode extends AstNode {
  /// The name/identifier.
  final String value;

  /// Alias for value - the name/identifier.
  String get name => value;

  /// Whether this name was escaped (backtick-quoted).
  final bool escaped;

  /// Whether to keep array results as arrays.
  @override
  final bool keepArray;

  const NameNode(super.position, this.value,
      {this.escaped = false, this.keepArray = false});

  @override
  String toString() => 'NameNode($value)';
}

/// A variable reference ($name).
class VariableNode extends AstNode {
  /// The variable name (without the $ prefix).
  final String name;

  const VariableNode(super.position, this.name);

  @override
  String toString() => 'VariableNode(\$$name)';
}

/// A binary operation (e.g., +, -, *, /, =, and, or).
class BinaryNode extends AstNode {
  /// The operator.
  final String operator;

  /// The left operand.
  final AstNode left;

  /// The right operand.
  final AstNode right;

  const BinaryNode(super.position, this.operator, this.left, this.right);

  @override
  String toString() => 'BinaryNode($operator)';
}

/// A unary operation (e.g., -, not).
class UnaryNode extends AstNode {
  /// The operator.
  final String operator;

  /// The operand.
  final AstNode operand;

  const UnaryNode(super.position, this.operator, this.operand);

  @override
  String toString() => 'UnaryNode($operator)';
}

/// A path expression (e.g., a.b.c).
class PathNode extends AstNode {
  /// The left side of the path.
  final AstNode left;

  /// The right side of the path.
  final AstNode right;

  /// Whether to keep the singleton array wrapper.
  @override
  final bool keepArray;

  const PathNode(super.position, this.left, this.right, {this.keepArray = false});

  @override
  String toString() => 'PathNode()';
}

/// A predicate/filter expression (e.g., items[price > 10]).
class FilterNode extends AstNode {
  /// The expression being filtered.
  final AstNode expr;

  /// The predicate expression.
  final AstNode predicate;

  const FilterNode(super.position, this.expr, this.predicate);

  @override
  String toString() => 'FilterNode()';
}

/// An array index expression (e.g., items[0]).
class IndexNode extends AstNode {
  /// The expression being indexed.
  final AstNode expr;

  /// The index expression.
  final AstNode index;

  const IndexNode(super.position, this.expr, this.index);

  @override
  String toString() => 'IndexNode()';
}

/// An array constructor (e.g., [1, 2, 3]).
class ArrayNode extends AstNode {
  /// The array elements.
  final List<AstNode> elements;

  const ArrayNode(super.position, this.elements);

  @override
  String toString() => 'ArrayNode(${elements.length} elements)';
}

/// An object constructor (e.g., {"a": 1, "b": 2}).
class ObjectNode extends AstNode {
  /// The key-value pairs.
  final List<ObjectPair> pairs;

  const ObjectNode(super.position, this.pairs);

  @override
  String toString() => 'ObjectNode(${pairs.length} pairs)';
}

/// A key-value pair in an object constructor.
class ObjectPair {
  /// The key expression.
  final AstNode key;

  /// The value expression.
  final AstNode value;

  const ObjectPair(this.key, this.value);
}

/// A function call expression.
class FunctionCallNode extends AstNode {
  /// The function being called (name or expression).
  final AstNode function;

  /// The arguments to the function.
  final List<AstNode> arguments;

  const FunctionCallNode(super.position, this.function, this.arguments);

  @override
  String toString() => 'FunctionCallNode(${arguments.length} args)';
}

/// A lambda/function definition.
class LambdaNode extends AstNode {
  /// The parameter names.
  final List<String> parameters;

  /// The function body.
  final AstNode body;

  /// The function signature (if specified).
  final String? signature;

  const LambdaNode(super.position, this.parameters, this.body, {this.signature});

  @override
  String toString() => 'LambdaNode(${parameters.length} params)';
}

/// A conditional expression (condition ? then : else).
class ConditionalNode extends AstNode {
  /// The condition expression.
  final AstNode condition;

  /// The expression to evaluate if condition is true.
  final AstNode thenExpr;

  /// The expression to evaluate if condition is false (optional).
  final AstNode? elseExpr;

  const ConditionalNode(
      super.position, this.condition, this.thenExpr, this.elseExpr);

  @override
  String toString() => 'ConditionalNode()';
}

/// A variable binding expression (name := value).
class AssignmentNode extends AstNode {
  /// The variable name.
  final String name;

  /// The value expression.
  final AstNode value;

  const AssignmentNode(super.position, this.name, this.value);

  @override
  String toString() => 'AssignmentNode($name)';
}

/// A block expression (expr1; expr2; ...).
class BlockNode extends AstNode {
  /// The expressions in the block.
  final List<AstNode> expressions;

  const BlockNode(super.position, this.expressions);

  @override
  String toString() => 'BlockNode(${expressions.length} exprs)';
}

/// A wildcard expression (*).
class WildcardNode extends AstNode {
  const WildcardNode(super.position);

  @override
  String toString() => 'WildcardNode()';
}

/// A descendant wildcard expression (**).
class DescendantNode extends AstNode {
  const DescendantNode(super.position);

  @override
  String toString() => 'DescendantNode()';
}

/// A parent reference expression (%).
class ParentNode extends AstNode {
  const ParentNode(super.position);

  @override
  String toString() => 'ParentNode()';
}

/// A context reference expression ($).
class ContextNode extends AstNode {
  const ContextNode(super.position);

  @override
  String toString() => 'ContextNode()';
}

/// A sort expression (expr ^(< field)).
class SortNode extends AstNode {
  /// The expression to sort.
  final AstNode expr;

  /// The sort terms.
  final List<SortTerm> terms;

  const SortNode(super.position, this.expr, this.terms);

  @override
  String toString() => 'SortNode(${terms.length} terms)';
}

/// A sort term specifying field and direction.
class SortTerm {
  /// The expression to sort by.
  final AstNode expr;

  /// True for descending, false for ascending.
  final bool descending;

  const SortTerm(this.expr, {this.descending = false});
}

/// A transform expression (| expr | update |).
class TransformNode extends AstNode {
  /// The expression to transform.
  final AstNode expr;

  /// The update expression.
  final AstNode update;

  /// The delete expression (optional).
  final AstNode? delete;

  const TransformNode(super.position, this.expr, this.update, {this.delete});

  @override
  String toString() => 'TransformNode()';
}

/// A range expression (start..end).
class RangeNode extends AstNode {
  /// The start of the range.
  final AstNode start;

  /// The end of the range.
  final AstNode end;

  const RangeNode(super.position, this.start, this.end);

  @override
  String toString() => 'RangeNode()';
}

/// A partial application placeholder (?).
class PlaceholderNode extends AstNode {
  const PlaceholderNode(super.position);

  @override
  String toString() => 'PlaceholderNode()';
}

/// A focus/map expression (expr @ $v).
class FocusNode extends AstNode {
  /// The expression to focus on.
  final AstNode expr;

  /// The variable to bind.
  final String variable;

  const FocusNode(super.position, this.expr, this.variable);

  @override
  String toString() => 'FocusNode($variable)';
}

/// An index binding expression (expr # $i).
class IndexBindNode extends AstNode {
  /// The expression.
  final AstNode expr;

  /// The variable to bind the index to.
  final String variable;

  const IndexBindNode(super.position, this.expr, this.variable);

  @override
  String toString() => 'IndexBindNode($variable)';
}

/// A keep-array expression (expr[]).
/// This forces the result to always be an array, even for single items.
class KeepArrayNode extends AstNode {
  /// The expression to wrap as an array.
  final AstNode expr;

  const KeepArrayNode(super.position, this.expr);

  @override
  String toString() => 'KeepArrayNode';
}
