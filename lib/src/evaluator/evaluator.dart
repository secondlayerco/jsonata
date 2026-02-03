import '../errors/jsonata_exception.dart';
import '../parser/ast.dart';
import '../utils/jsonata_regex.dart';
import '../utils/undefined.dart';
import 'environment.dart';

/// A tuple containing a value and its evaluation environment (for parent tracking).
class _Tuple {
  final dynamic value;
  final Environment env;
  _Tuple(this.value, this.env);
}

/// Evaluates JSONata AST nodes against input data.
class Evaluator {
  /// Find all parent slots in an AST node.
  List<ParentSlot> _findParentSlots(AstNode node) {
    final slots = <ParentSlot>[];
    _collectParentSlots(node, slots);
    return slots;
  }

  void _collectParentSlots(AstNode node, List<ParentSlot> slots) {
    switch (node) {
      case final ParentNode p when p.slot != null:
        slots.add(p.slot!);
      case final PathNode p:
        _collectParentSlots(p.left, slots);
        _collectParentSlots(p.right, slots);
      case final FilterNode f:
        _collectParentSlots(f.expr, slots);
        _collectParentSlots(f.predicate, slots);
      case final BinaryNode b:
        _collectParentSlots(b.left, slots);
        _collectParentSlots(b.right, slots);
      case final UnaryNode u:
        _collectParentSlots(u.operand, slots);
      case final ArrayNode a:
        for (final elem in a.elements) {
          _collectParentSlots(elem, slots);
        }
      case final ObjectNode o:
        for (final pair in o.pairs) {
          _collectParentSlots(pair.key, slots);
          _collectParentSlots(pair.value, slots);
        }
      case final BlockNode b:
        for (final expr in b.expressions) {
          _collectParentSlots(expr, slots);
        }
      case final AssignmentNode a:
        _collectParentSlots(a.value, slots);
      case final ConditionalNode c:
        _collectParentSlots(c.condition, slots);
        _collectParentSlots(c.thenExpr, slots);
        if (c.elseExpr != null) {
          _collectParentSlots(c.elseExpr!, slots);
        }
      case final FunctionCallNode f:
        _collectParentSlots(f.function, slots);
        for (final arg in f.arguments) {
          _collectParentSlots(arg, slots);
        }
      case final IndexNode i:
        _collectParentSlots(i.expr, slots);
        _collectParentSlots(i.index, slots);
      case final KeepArrayNode k:
        _collectParentSlots(k.expr, slots);
      default:
        // Leaf nodes or nodes we don't need to traverse
        break;
    }
  }

  /// Evaluates an AST node against input data.
  dynamic evaluate(AstNode node, dynamic input, Environment environment) {
    return switch (node) {
      final NumberNode n => n.value,
      final StringNode s => s.value,
      final BooleanNode b => b.value,
      NullNode() => null,
      final NameNode n => _evaluateName(n, input, environment),
      final VariableNode v => _evaluateVariable(v, environment),
      ContextNode() => environment.input,
      final PathNode p => _evaluatePath(p, input, environment),
      final BinaryNode b => _evaluateBinary(b, input, environment),
      final UnaryNode u => _evaluateUnary(u, input, environment),
      final FilterNode f => _evaluateFilter(f, input, environment),
      final ArrayNode a => _evaluateArray(a, input, environment),
      final ObjectNode o => _evaluateObject(o, input, environment),
      final FunctionCallNode f => _evaluateFunctionCall(f, input, environment),
      final LambdaNode l => _evaluateLambda(l, environment),
      final ConditionalNode c => _evaluateConditional(c, input, environment),
      final AssignmentNode a => _evaluateAssignment(a, input, environment),
      final BlockNode b => _evaluateBlock(b, input, environment),
      WildcardNode() => _evaluateWildcard(input),
      DescendantNode() => _evaluateDescendant(input),
      final RangeNode r => _evaluateRange(r, input, environment),
      final RegexNode r => JsonataRegex(r.pattern, r.flags),
      final ParentNode p => _evaluateParent(p, environment),
      SortNode() => throw JsonataException(
          'D3012',
          'Sort operator not yet implemented',
          position: node.position,
        ),
      TransformNode() => throw JsonataException(
          'D3013',
          'Transform operator not yet implemented',
          position: node.position,
        ),
      PlaceholderNode() => throw JsonataException(
          'D3014',
          'Placeholder should not be evaluated directly',
          position: node.position,
        ),
      FocusNode() => throw JsonataException(
          'D3015',
          'Focus operator not yet implemented',
          position: node.position,
        ),
      IndexBindNode() => throw JsonataException(
          'D3016',
          'Index bind operator not yet implemented',
          position: node.position,
        ),
      final IndexNode i => _evaluateIndex(i, input, environment),
      final KeepArrayNode k => _evaluateKeepArray(k, input, environment),
    };
  }

  dynamic _evaluateName(NameNode node, dynamic input, Environment env) {
    if (input == null || isUndefined(input)) {
      return undefined;
    }
    if (input is Map<String, dynamic>) {
      final value = input[node.name];
      return value ?? undefined;
    }
    if (input is List) {
      // Map over array
      return _mapOverArray(input, (item) => _evaluateName(node, item, env));
    }
    return undefined;
  }

  dynamic _evaluateVariable(VariableNode node, Environment env) {
    // $$ refers to the root input context
    if (node.name == r'$$') {
      return env.rootInput;
    }
    // $ refers to the current input context
    if (node.name == r'$') {
      return env.input;
    }
    // First check bindings
    final value = env.lookup(node.name);
    if (!isUndefined(value)) return value;

    // Then check for function references (for passing to HOFs like $map, $reduce)
    final func = env.lookupFunction('\$${node.name}');
    if (func != null) {
      return NativeFunctionReference(func, env);
    }
    return undefined;
  }

  dynamic _evaluatePath(PathNode node, dynamic input, Environment env) {
    // Check if this path or any descendant uses parent references
    final hasParentRefs = _findParentSlots(node).isNotEmpty;

    if (hasParentRefs) {
      // Use tuple-based evaluation for paths with parent references
      return _evaluatePathWithTuples(node, input, env);
    }

    // Standard path evaluation (no parent references)
    return _evaluatePathStandard(node, input, env);
  }

  /// Standard path evaluation without parent reference tracking.
  dynamic _evaluatePathStandard(PathNode node, dynamic input, Environment env) {
    final left = evaluate(node.left, input, env);
    if (isUndefined(left)) {
      return undefined;
    }

    // Check if this path should preserve array semantics
    bool keepAsArray = node.left is KeepArrayNode || node.right is KeepArrayNode;
    if (!keepAsArray && node.left is FilterNode) {
      keepAsArray = (node.left as FilterNode).expr is KeepArrayNode;
    }
    if (!keepAsArray) {
      keepAsArray = _containsKeepArray(node.left);
    }

    // Helper to evaluate the right side of a path
    dynamic evalRight(dynamic item) {
      final right = node.right;
      if (right is StringNode) {
        if (item is Map) {
          return item[right.value] ?? undefined;
        }
        return undefined;
      }
      if (right is FunctionCallNode) {
        return _evaluateFunctionCallWithContext(right, item, env);
      }
      return evaluate(right, item, env.createChild(input: item));
    }

    // If left is an array, map over it
    if (left is List) {
      final shouldFlatten = node.right is! ArrayNode &&
                           node.right is! ObjectNode &&
                           node.right is! KeepArrayNode;
      return _mapOverArray(left, evalRight, flatten: shouldFlatten, keepAsArray: keepAsArray);
    }

    return evalRight(left);
  }

  /// Evaluate a path with tuple tracking for parent references.
  dynamic _evaluatePathWithTuples(PathNode node, dynamic input, Environment env) {
    // Flatten the path into steps
    final steps = <AstNode>[];
    _flattenPath(node, steps);

    // Start with the input as a single tuple
    var tuples = [_Tuple(input, env)];

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final newTuples = <_Tuple>[];

      for (final tuple in tuples) {
        // If this step has ancestor bindings, bind the CURRENT context (before evaluating)
        // to each ancestor label. This is the parent value for subsequent % operators.
        final ancestors = _getStepAncestors(step);
        Environment stepEnv = tuple.env;
        if (ancestors.isNotEmpty) {
          stepEnv = tuple.env.createChild(input: tuple.value);
          for (final ancestor in ancestors) {
            stepEnv.bind(ancestor.label, tuple.value);
          }
        }

        final stepResults = _evaluateStep(step, tuple.value, stepEnv);

        for (final result in stepResults) {
          // Create new environment for this result, preserving ancestor bindings
          final childEnv = stepEnv.createChild(input: result);
          newTuples.add(_Tuple(result, childEnv));
        }
      }

      tuples = newTuples;
    }

    // Extract values from tuples
    final results = tuples.map((t) => t.value).where((v) => !isUndefined(v)).toList();
    if (results.isEmpty) return undefined;
    if (results.length == 1) return results[0];
    return results;
  }

  /// Get the ancestor slots for a step if it has any.
  List<ParentSlot> _getStepAncestors(AstNode step) {
    if (step is NameNode) return step.ancestors;
    if (step is WildcardNode) return step.ancestors;
    return const [];
  }

  /// Flatten a path node into a list of steps.
  void _flattenPath(AstNode node, List<AstNode> steps) {
    if (node is PathNode) {
      _flattenPath(node.left, steps);
      _flattenPath(node.right, steps);
    } else {
      steps.add(node);
    }
  }

  /// Evaluate a single step, returning a list of results.
  List<dynamic> _evaluateStep(AstNode step, dynamic input, Environment env) {
    if (isUndefined(input) || input == null) {
      return [];
    }

    // Handle array input - map over it (except for array constructor which operates on single items)
    if (input is List && step is! ArrayNode) {
      final results = <dynamic>[];
      for (final item in input) {
        results.addAll(_evaluateStep(step, item, env.createChild(input: item)));
      }
      return results;
    }

    // For array constructor on array input, still iterate over items
    if (input is List && step is ArrayNode) {
      final results = <dynamic>[];
      for (final item in input) {
        final itemEnv = env.createChild(input: item);
        final result = evaluate(step, item, itemEnv);
        if (!isUndefined(result)) {
          // Flatten array constructor results
          if (result is List) {
            results.addAll(result);
          } else {
            results.add(result);
          }
        }
      }
      return results;
    }

    // Evaluate the step
    final result = evaluate(step, input, env.createChild(input: input));

    if (isUndefined(result)) {
      return [];
    }

    // Flatten arrays for path evaluation (except KeepArrayNode)
    if (result is List && step is! KeepArrayNode) {
      return result;
    }

    return [result];
  }

  /// Evaluate a parent node by looking up its slot in the environment.
  dynamic _evaluateParent(ParentNode node, Environment env) {
    if (node.slot == null) {
      // This shouldn't happen if parsing was done correctly
      throw JsonataException(
        'D3011',
        'Parent operator has no slot assigned',
        position: node.position,
      );
    }
    final value = env.lookup(node.slot!.label);
    if (isUndefined(value)) {
      // Parent not bound - this can happen at runtime
      throw JsonataException(
        'S0217',
        "The object representing the 'parent' cannot be derived from this expression",
        position: node.position,
      );
    }
    return value;
  }

  dynamic _evaluateBinary(BinaryNode node, dynamic input, Environment env) {
    final op = node.operator;

    // Short-circuit evaluation for logical operators
    if (op == 'and') {
      final left = evaluate(node.left, input, env);
      if (!_isTruthy(left)) return false;
      return _isTruthy(evaluate(node.right, input, env));
    }
    if (op == 'or') {
      final left = evaluate(node.left, input, env);
      if (_isTruthy(left)) return true;
      return _isTruthy(evaluate(node.right, input, env));
    }

    // Chain operator
    if (op == '~>') {
      final left = evaluate(node.left, input, env);
      // Right side should be a function - call it with left as argument
      var right = node.right;

      // Unwrap KeepArrayNode if present - we'll apply it after the function call
      AstNode? keepArrayWrapper;
      if (right is KeepArrayNode) {
        keepArrayWrapper = right;
        right = right.expr;
      }

      dynamic result;
      if (right is FunctionCallNode) {
        // Insert left as first argument
        final newArgs = [node.left, ...right.arguments];
        final newCall = FunctionCallNode(right.position, right.function, newArgs);
        result = evaluate(newCall, input, env);
      } else {
        // If right is just a function reference, call it with left
        final rightValue = evaluate(right, input, env);
        if (rightValue is JsonataFunction) {
          result = rightValue([left], input, env);
        } else {
          throw JsonataException(
            'T2006',
            'Right side of ~> must be a function',
            position: node.position,
          );
        }
      }

      // Apply keep-array if it was present
      if (keepArrayWrapper != null) {
        if (isUndefined(result)) return undefined;
        if (result is List) return result;
        return [result];
      }
      return result;
    }

    // String concatenation
    if (op == '&') {
      final left = evaluate(node.left, input, env);
      final right = evaluate(node.right, input, env);
      return _toString(left) + _toString(right);
    }

    // Object grouping operator: expr{key: value}
    if (op == '{') {
      return _evaluateObjectGrouping(node, input, env);
    }

    // Evaluate both sides for other operators
    final left = evaluate(node.left, input, env);
    final right = evaluate(node.right, input, env);

    return _applyBinaryOp(op, left, right, node.position);
  }

  dynamic _applyBinaryOp(String op, dynamic left, dynamic right, int position) {
    // For comparison operators (<, >, <=, >=), validate types BEFORE checking undefined
    if (op == '<' || op == '>' || op == '<=' || op == '>=') {
      // Check type validity for non-undefined values
      if (!isUndefined(left) && left is! num && left is! String) {
        throw JsonataException(
          'T2010',
          'The operands of the comparison operator must be numbers or strings',
          position: position,
        );
      }
      if (!isUndefined(right) && right is! num && right is! String) {
        throw JsonataException(
          'T2010',
          'The operands of the comparison operator must be numbers or strings',
          position: position,
        );
      }
      // If either is undefined (but types are valid), return undefined
      if (isUndefined(left) || isUndefined(right)) {
        return undefined;
      }
    }

    // For arithmetic operators, check types BEFORE undefined check
    // This ensures `false + $x` throws T2001 even when $x is undefined
    if (op == '+' || op == '-' || op == '*' || op == '/' || op == '%') {
      // Check if either non-undefined operand is not a number
      if (!isUndefined(left) && left is! num) {
        throw JsonataException(
          'T2001',
          'Type error: expected numbers',
          position: position,
        );
      }
      if (!isUndefined(right) && right is! num) {
        throw JsonataException(
          'T2001',
          'Type error: expected numbers',
          position: position,
        );
      }
      // If either is undefined (but types are valid), return undefined
      if (isUndefined(left) || isUndefined(right)) {
        return undefined;
      }
    }

    // Handle undefined for other operators
    if (isUndefined(left) || isUndefined(right)) {
      if (op == '=' || op == '!=') {
        // In JSONata, any comparison involving undefined returns false
        // undefined = undefined is false, not true
        return false;
      }
      return undefined;
    }

    return switch (op) {
      '+' => _numericOp(left, right, (a, b) => a + b, position),
      '-' => _numericOp(left, right, (a, b) => a - b, position),
      '*' => _numericOp(left, right, (a, b) => a * b, position),
      '/' => _numericOp(left, right, (a, b) => a / b, position),
      '%' => _numericOp(left, right, (a, b) => a % b, position),
      '=' => _equals(left, right),
      '!=' => !_equals(left, right),
      '<' => _compare(left, right, position) < 0,
      '>' => _compare(left, right, position) > 0,
      '<=' => _compare(left, right, position) <= 0,
      '>=' => _compare(left, right, position) >= 0,
      'in' => _evaluateIn(left, right),
      '?:' => isUndefined(left) ? right : left,
      '??' => (left == null || isUndefined(left)) ? right : left,
      '{' => _evaluateGrouping(left, right, position),
      _ => throw JsonataException(
          'D3001',
          'Unknown operator: $op',
          position: position,
        ),
    };
  }

  num _numericOp(
    dynamic left,
    dynamic right,
    num Function(num, num) op,
    int position,
  ) {
    if (left is! num || right is! num) {
      throw JsonataException(
        'T2001',
        'Type error: expected numbers',
        position: position,
      );
    }
    final result = op(left, right);
    // Check for infinity or NaN (overflow/underflow)
    if (result.isInfinite || result.isNaN) {
      throw JsonataException(
        'D1001',
        'Number out of range: result is ${result.isNaN ? "NaN" : "Infinity"}',
        position: position,
      );
    }
    return result;
  }

  bool _equals(dynamic left, dynamic right) {
    if (left is num && right is num) {
      return left == right;
    }
    if (left is String && right is String) {
      return left == right;
    }
    if (left is bool && right is bool) {
      return left == right;
    }
    if (left == null && right == null) {
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (!_equals(left[i], right[i])) return false;
      }
      return true;
    }
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final key in left.keys) {
        if (!right.containsKey(key)) return false;
        if (!_equals(left[key], right[key])) return false;
      }
      return true;
    }
    return false;
  }

  int _compare(dynamic left, dynamic right, int position) {
    if (left is num && right is num) {
      return left.compareTo(right);
    }
    if (left is String && right is String) {
      return left.compareTo(right);
    }
    // Type mismatch - throw error
    if (left is String || right is String) {
      throw JsonataException(
        'T2009',
        'The operands of the "comparison" operator must be of the same type',
        position: position,
      );
    }
    throw JsonataException(
      'T2010',
      'The operands of the "comparison" operator must be numbers or strings',
      position: position,
    );
  }

  bool _evaluateIn(dynamic left, dynamic right) {
    if (right is List) {
      return right.any((item) => _equals(left, item));
    }
    return _equals(left, right);
  }

  dynamic _evaluateGrouping(dynamic input, dynamic groupSpec, int position) {
    // Grouping operation - to be implemented
    throw JsonataException(
      'D3020',
      'Grouping operator not yet implemented',
      position: position,
    );
  }

  dynamic _evaluateUnary(UnaryNode node, dynamic input, Environment env) {
    final operand = evaluate(node.operand, input, env);

    return switch (node.operator) {
      '-' => operand is num ? -operand : undefined,
      _ => throw JsonataException(
          'D3002',
          'Unknown unary operator: ${node.operator}',
          position: node.position,
        ),
    };
  }

  dynamic _evaluateFilter(FilterNode node, dynamic input, Environment env) {
    // Check if this filter should preserve array semantics
    final keepArray = node.expr is KeepArrayNode;

    // Check if the filter expression has ancestor bindings
    // If so, bind the current input (parent context) to those labels
    List<ParentSlot> ancestors = const [];
    final exprNode = keepArray ? (node.expr as KeepArrayNode).expr : node.expr;
    if (exprNode is NameNode) {
      ancestors = exprNode.ancestors;
    } else if (exprNode is WildcardNode) {
      ancestors = exprNode.ancestors;
    }

    Environment filterEnv = env;
    if (ancestors.isNotEmpty) {
      filterEnv = env.createChild(input: input);
      for (final ancestor in ancestors) {
        filterEnv.bind(ancestor.label, input);
      }
    }

    final expr = evaluate(node.expr, input, filterEnv);
    if (isUndefined(expr)) return undefined;

    final items = expr is List ? expr : [expr];
    final results = <dynamic>[];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final childEnv = filterEnv.createChild(input: item);

      final predicate = evaluate(node.predicate, item, childEnv);

      if (predicate is num) {
        // Index access
        final index = predicate.toInt();
        final actualIndex = index < 0 ? items.length + index : index;
        if (actualIndex == i) {
          results.add(item);
        }
      } else if (_isTruthy(predicate)) {
        results.add(item);
      }
    }

    // If keep array semantics, don't normalize (always return array)
    if (keepArray) {
      if (results.isEmpty) return undefined;
      return results;
    }
    return normalizeSequence(results);
  }

  dynamic _evaluateIndex(IndexNode node, dynamic input, Environment env) {
    final expr = evaluate(node.expr, input, env);
    final index = evaluate(node.index, input, env);

    if (isUndefined(expr)) return undefined;

    if (index is num) {
      final items = expr is List ? expr : [expr];
      final i = index.toInt();
      final actualIndex = i < 0 ? items.length + i : i;
      if (actualIndex >= 0 && actualIndex < items.length) {
        return items[actualIndex];
      }
      return undefined;
    }

    // Treat as filter predicate
    return _evaluateFilter(FilterNode(node.position, node.expr, node.index), input, env);
  }

  dynamic _evaluateKeepArray(KeepArrayNode node, dynamic input, Environment env) {
    final value = evaluate(node.expr, input, env);
    if (isUndefined(value)) return undefined;
    // Force result to be an array
    if (value is List) return value;
    return [value];
  }

  dynamic _evaluateArray(ArrayNode node, dynamic input, Environment env) {
    final results = <dynamic>[];
    for (final element in node.elements) {
      final value = evaluate(element, input, env);
      if (!isUndefined(value)) {
        // Only preserve nested arrays for explicit array literals
        // Flatten ranges and path expressions
        if (value is List && element is! ArrayNode) {
          results.addAll(value);
        } else {
          results.add(value);
        }
      }
    }
    return results;
  }

  dynamic _evaluateObject(ObjectNode node, dynamic input, Environment env) {
    final result = <String, dynamic>{};
    for (final pair in node.pairs) {
      final key = evaluate(pair.key, input, env);
      final value = evaluate(pair.value, input, env);

      if (isUndefined(key)) continue;

      // Key must be a string in object construction
      if (key is! String) {
        throw JsonataException(
          'T1003',
          'Key in object structure must evaluate to a string; got ${key.runtimeType}',
          position: node.position,
        );
      }

      if (!isUndefined(value)) {
        // D1009: Check for duplicate keys
        if (result.containsKey(key)) {
          throw JsonataException(
            'D1009',
            'Duplicate key "$key" in object structure',
            position: node.position,
          );
        }
        result[key] = value;
      }
    }
    return result;
  }

  /// Evaluates the object grouping operator: expr{key: value}
  /// Groups items by key, then evaluates value expression with grouped items.
  dynamic _evaluateObjectGrouping(
    BinaryNode node,
    dynamic input,
    Environment env,
  ) {
    // Left side is the expression to iterate over
    final items = evaluate(node.left, input, env);
    if (isUndefined(items)) return undefined;

    // Right side must be an ObjectNode with key-value pairs
    final objectNode = node.right;
    if (objectNode is! ObjectNode) {
      throw JsonataException(
        'T1003',
        'Object grouping requires an object template',
        position: node.position,
      );
    }

    // Collect items into a list
    final itemList = items is List ? items : [items];
    if (itemList.isEmpty) return <String, dynamic>{};

    // Result object
    final result = <String, dynamic>{};

    // Process each key-value pair in the template
    for (final pair in objectNode.pairs) {
      // First pass: group items by key value
      final groups = <String, List<dynamic>>{};

      for (final item in itemList) {
        final itemEnv = env.createChild(input: item);
        final keyValue = evaluate(pair.key, item, itemEnv);
        if (isUndefined(keyValue)) continue;

        // Key must be a string in object grouping
        if (keyValue is! String) {
          throw JsonataException(
            'T1003',
            'Key in object grouping must evaluate to a string',
            position: node.position,
          );
        }

        final keyStr = keyValue;
        groups.putIfAbsent(keyStr, () => []).add(item);
      }

      // Second pass: evaluate value expression for each group
      for (final entry in groups.entries) {
        final keyStr = entry.key;
        final groupItems = entry.value;

        // Check for duplicate keys across pairs
        if (result.containsKey(keyStr)) {
          throw JsonataException(
            'D1009',
            'Duplicate key "$keyStr" in object grouping',
            position: node.position,
          );
        }

        // Create context: single item or array of items
        final groupContext =
            groupItems.length == 1 ? groupItems.first : groupItems;
        final groupEnv = env.createChild(input: groupContext);

        // Evaluate value expression with group as context
        final value = evaluate(pair.value, groupContext, groupEnv);
        if (!isUndefined(value)) {
          result[keyStr] = value;
        }
      }
    }

    return result.isEmpty ? undefined : result;
  }

  dynamic _evaluateFunctionCall(
    FunctionCallNode node,
    dynamic input,
    Environment env,
  ) {
    // Check for partial application (arguments contain PlaceholderNode)
    final hasPlaceholder = node.arguments.any((a) => a is PlaceholderNode);
    if (hasPlaceholder) {
      return _createPartialApplication(node, input, env);
    }

    final func = evaluate(node.function, input, env);

    if (func is LambdaClosure) {
      return _callLambda(func, node.arguments, input, env);
    }

    if (func is JsonataFunction) {
      final args = node.arguments.map((a) => evaluate(a, input, env)).toList();
      return func(args, input, env);
    }

    // Check if it's a function reference by name
    if (node.function is NameNode) {
      final name = (node.function as NameNode).name;
      final builtIn = env.lookupFunction(name);
      if (builtIn != null) {
        final args = node.arguments.map((a) => evaluate(a, input, env)).toList();
        return builtIn(args, input, env);
      }
    }

    // Check if it's a variable reference to a function (e.g., $sum)
    if (node.function is VariableNode) {
      final name = (node.function as VariableNode).name;
      // Functions are registered with $ prefix, so add it back
      final builtIn = env.lookupFunction('\$$name');
      if (builtIn != null) {
        final args = node.arguments.map((a) => evaluate(a, input, env)).toList();
        return builtIn(args, input, env);
      }
    }

    throw JsonataException(
      'T1005',
      'Attempted to invoke a non-function',
      position: node.position,
    );
  }

  /// Create a partially applied function from a function call with placeholders.
  dynamic _createPartialApplication(
    FunctionCallNode node,
    dynamic input,
    Environment env,
  ) {
    final func = evaluate(node.function, input, env);

    // Evaluate non-placeholder arguments now, placeholders will be filled later
    final evaluatedArgs = <dynamic>[];
    final placeholderIndices = <int>[];

    for (var i = 0; i < node.arguments.length; i++) {
      if (node.arguments[i] is PlaceholderNode) {
        evaluatedArgs.add(null); // Placeholder
        placeholderIndices.add(i);
      } else {
        evaluatedArgs.add(evaluate(node.arguments[i], input, env));
      }
    }

    // Return a PartialApplication object
    return PartialApplication(func, evaluatedArgs, placeholderIndices, env);
  }

  /// Evaluate a function call with context value prepended to arguments.
  /// Used for path context syntax like `value.$function(args)`.
  /// For built-in functions, context is prepended to args.
  /// For lambdas, context is passed as input but NOT prepended.
  dynamic _evaluateFunctionCallWithContext(
    FunctionCallNode node,
    dynamic contextValue,
    Environment env,
  ) {
    final func = evaluate(node.function, contextValue, env);

    // Evaluate arguments with contextValue as the input (so $ resolves correctly)
    final childEnv = env.createChild(input: contextValue);
    final evaluatedArgs =
        node.arguments.map((a) => evaluate(a, contextValue, childEnv)).toList();

    if (func is LambdaClosure) {
      // For lambdas, do NOT prepend context - just pass as input
      // The user must explicitly use $ if they want the context value
      final lambdaEnv = func.environment.createChild();
      final params = func.node.parameters;
      for (var i = 0; i < params.length; i++) {
        final value = i < evaluatedArgs.length ? evaluatedArgs[i] : undefined;
        lambdaEnv.bind(params[i], value);
      }
      return evaluate(func.node.body, contextValue, lambdaEnv);
    }

    // For built-in functions with context syntax (a.b.$func(...)):
    // Always prepend context value as first argument, function will handle it
    final argsWithContext = [contextValue, ...evaluatedArgs];

    if (func is JsonataFunction) {
      return func(argsWithContext, contextValue, env);
    }

    if (func is NativeFunctionReference) {
      return func.invoke(this, argsWithContext, contextValue);
    }

    // Check if it's a variable reference to a function (e.g., $substringBefore)
    if (node.function is VariableNode) {
      final name = (node.function as VariableNode).name;
      final builtIn = env.lookupFunction('\$$name');
      if (builtIn != null) {
        return builtIn(argsWithContext, contextValue, env);
      }
    }

    throw JsonataException(
      'T1005',
      'Attempted to invoke a non-function',
      position: node.position,
    );
  }

  LambdaClosure _evaluateLambda(LambdaNode node, Environment env) {
    return LambdaClosure(node, env);
  }

  dynamic _callLambda(
    LambdaClosure closure,
    List<AstNode> argNodes,
    dynamic input,
    Environment env,
  ) {
    final lambdaEnv = closure.environment.createChild();

    // Bind parameters
    final params = closure.node.parameters;
    for (var i = 0; i < params.length; i++) {
      final value = i < argNodes.length
          ? evaluate(argNodes[i], input, env)
          : undefined;
      lambdaEnv.bind(params[i], value);
    }

    // Use the closure's captured input context, not the call-site input.
    // This ensures field references like `Account Name` resolve correctly
    // when the lambda is called from a different context (e.g., object grouping).
    final closureInput = closure.environment.input;

    return evaluate(closure.node.body, closureInput, lambdaEnv);
  }

  dynamic _evaluateConditional(
    ConditionalNode node,
    dynamic input,
    Environment env,
  ) {
    final condition = evaluate(node.condition, input, env);
    if (_isTruthy(condition)) {
      return evaluate(node.thenExpr, input, env);
    }
    if (node.elseExpr != null) {
      return evaluate(node.elseExpr!, input, env);
    }
    return undefined;
  }

  dynamic _evaluateAssignment(
    AssignmentNode node,
    dynamic input,
    Environment env,
  ) {
    final value = evaluate(node.value, input, env);
    env.bind(node.name, value);
    return value;
  }

  dynamic _evaluateBlock(BlockNode node, dynamic input, Environment env) {
    // Blocks create their own scope for variable bindings
    final blockEnv = env.createChild(input: input);
    dynamic result = undefined;
    for (final expr in node.expressions) {
      result = evaluate(expr, input, blockEnv);
    }
    return result;
  }

  dynamic _evaluateWildcard(dynamic input) {
    if (input == null || isUndefined(input)) return undefined;
    if (input is Map<String, dynamic>) {
      // Return all property values, flattening arrays
      final results = <dynamic>[];
      for (final value in input.values) {
        if (value is List) {
          results.addAll(value);
        } else {
          results.add(value);
        }
      }
      return normalizeSequence(results);
    }
    if (input is List) {
      // Map wildcard over array elements
      final results = <dynamic>[];
      for (final item in input) {
        final value = _evaluateWildcard(item);
        if (!isUndefined(value)) {
          if (value is List) {
            results.addAll(value);
          } else {
            results.add(value);
          }
        }
      }
      return normalizeSequence(results);
    }
    // For primitives, return the value itself
    return input;
  }

  dynamic _evaluateDescendant(dynamic input) {
    if (input == null || isUndefined(input)) return undefined;

    final results = <dynamic>[];

    void recurse(dynamic value) {
      if (value is Map<String, dynamic>) {
        for (final v in value.values) {
          results.add(v);
          recurse(v);
        }
      } else if (value is List) {
        for (final item in value) {
          results.add(item);
          recurse(item);
        }
      }
    }

    recurse(input);
    return normalizeSequence(results);
  }

  dynamic _evaluateRange(RangeNode node, dynamic input, Environment env) {
    final start = evaluate(node.start, input, env);
    final end = evaluate(node.end, input, env);

    // Type validation - check if values are valid before checking for undefined
    // Non-integer numbers are always an error
    if (start is num && start != start.toInt()) {
      throw JsonataException(
        'T2003',
        'The left side of the range operator (..) must evaluate to an integer',
        position: node.position,
      );
    }
    if (end is num && end != end.toInt()) {
      throw JsonataException(
        'T2004',
        'The right side of the range operator (..) must evaluate to an integer',
        position: node.position,
      );
    }

    // Non-numeric, non-undefined types are an error
    if (!isUndefined(start) && start is! num) {
      throw JsonataException(
        'T2003',
        'The left side of the range operator (..) must evaluate to an integer',
        position: node.position,
      );
    }
    if (!isUndefined(end) && end is! num) {
      throw JsonataException(
        'T2004',
        'The right side of the range operator (..) must evaluate to an integer',
        position: node.position,
      );
    }

    // If either bound is undefined (after type checks), return empty array
    if (isUndefined(start) || isUndefined(end)) {
      return <int>[];
    }

    final startInt = (start as num).toInt();
    final endInt = (end as num).toInt();

    if (startInt > endInt) {
      return <int>[];
    }

    // Check for range too large (max 10 million elements)
    final rangeSize = endInt - startInt + 1;
    if (rangeSize > 10000000) {
      throw JsonataException(
        'D2014',
        'The size of the range ($rangeSize) exceeds the maximum allowed (10000000)',
        position: node.position,
      );
    }

    return List.generate(rangeSize, (i) => startInt + i);
  }

  dynamic _mapOverArray(List<dynamic> array, dynamic Function(dynamic) mapper,
      {bool flatten = true, bool keepAsArray = false}) {
    final results = <dynamic>[];
    for (final item in array) {
      final value = mapper(item);
      if (!isUndefined(value)) {
        // Flatten arrays when traversing paths (JSONata semantics)
        if (flatten && value is List) {
          results.addAll(value);
        } else {
          results.add(value);
        }
      }
    }
    // If keepAsArray is true, always return as array (don't normalize)
    if (keepAsArray) {
      if (results.isEmpty) return undefined;
      return results;
    }
    return normalizeSequence(results);
  }

  /// Recursively check if an AST node contains a KeepArrayNode.
  /// Used to propagate array preservation through nested paths.
  bool _containsKeepArray(AstNode node) {
    if (node is KeepArrayNode) return true;
    if (node is PathNode) {
      return _containsKeepArray(node.left) || _containsKeepArray(node.right);
    }
    if (node is FilterNode) {
      return node.expr is KeepArrayNode || _containsKeepArray(node.expr);
    }
    return false;
  }

  bool _isTruthy(dynamic value) {
    if (value == null || isUndefined(value)) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  String _toString(dynamic value) {
    if (value == null || isUndefined(value)) return '';
    if (value is String) return value;
    if (value is num) {
      // Handle integer representation
      if (value == value.toInt()) {
        return value.toInt().toString();
      }
      return value.toString();
    }
    if (value is bool) return value.toString();
    // Use JSON encoding for arrays and maps (compact, no spaces)
    if (value is List || value is Map) {
      return _jsonEncode(value);
    }
    return value.toString();
  }

  String _jsonEncode(dynamic value) {
    if (value == null || isUndefined(value)) return 'null';
    if (value is String) return '"${_escapeJsonString(value)}"';
    if (value is num) {
      if (value == value.toInt()) {
        return value.toInt().toString();
      }
      return value.toString();
    }
    if (value is bool) return value.toString();
    if (value is List) {
      return '[${value.map(_jsonEncode).join(',')}]';
    }
    if (value is Map) {
      final entries =
          value.entries.map((e) => '"${e.key}":${_jsonEncode(e.value)}');
      return '{${entries.join(',')}}';
    }
    return value.toString();
  }

  String _escapeJsonString(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }

  /// Normalizes a result list into JSONata sequence semantics.
  dynamic normalizeSequence(List<dynamic> results) {
    if (results.isEmpty) return undefined;
    if (results.length == 1) return results.first;
    return results;
  }
}

/// Represents a lambda closure with captured environment.
class LambdaClosure {
  final LambdaNode node;
  final Environment environment;

  LambdaClosure(this.node, this.environment);

  /// Invokes the closure with the given argument values.
  ///
  /// This is used by higher-order functions like $map, $filter, $reduce.
  dynamic invoke(Evaluator evaluator, List<dynamic> args, dynamic input) {
    final lambdaEnv = environment.createChild();

    // Bind parameters
    final params = node.parameters;
    for (var i = 0; i < params.length; i++) {
      final value = i < args.length ? args[i] : undefined;
      lambdaEnv.bind(params[i], value);
    }

    return evaluator.evaluate(node.body, input, lambdaEnv);
  }
}

/// Represents a reference to a native (built-in) function.
///
/// This allows native functions to be passed as arguments to higher-order
/// functions like $map, $filter, $reduce.
class NativeFunctionReference {
  final JsonataFunction function;
  final Environment environment;

  NativeFunctionReference(this.function, this.environment);

  /// Invokes the native function with the given arguments.
  dynamic invoke(Evaluator evaluator, List<dynamic> args, dynamic input) {
    return function(args, input, environment);
  }
}

/// Represents a partially applied function.
///
/// Created when a function is called with placeholder arguments (?).
/// When invoked, the placeholders are filled in with the provided arguments.
class PartialApplication {
  final dynamic function;
  final List<dynamic> evaluatedArgs;
  final List<int> placeholderIndices;
  final Environment environment;

  PartialApplication(
    this.function,
    this.evaluatedArgs,
    this.placeholderIndices,
    this.environment,
  );

  /// Invokes the partial application with arguments to fill placeholders.
  dynamic invoke(Evaluator evaluator, List<dynamic> args, dynamic input) {
    // Fill in the placeholders with the provided arguments
    final filledArgs = List<dynamic>.from(evaluatedArgs);
    for (var i = 0; i < placeholderIndices.length && i < args.length; i++) {
      filledArgs[placeholderIndices[i]] = args[i];
    }

    // Call the underlying function
    if (function is LambdaClosure) {
      return (function as LambdaClosure).invoke(evaluator, filledArgs, input);
    }
    if (function is NativeFunctionReference) {
      return (function as NativeFunctionReference)
          .invoke(evaluator, filledArgs, input);
    }
    if (function is JsonataFunction) {
      return (function as JsonataFunction)(filledArgs, input, environment);
    }
    return undefined;
  }
}