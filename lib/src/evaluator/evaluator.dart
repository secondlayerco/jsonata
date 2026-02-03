import '../errors/jsonata_exception.dart';
import '../parser/ast.dart';
import '../utils/jsonata_regex.dart';
import '../utils/undefined.dart';
import 'environment.dart';

/// A tuple containing a value and its evaluation environment (for parent tracking).
///
/// - `value`: The current result value (for producing final output)
/// - `context`: The navigation context for path evaluation (used for parent references)
///              With focus operators, context stays at the parent level while value
///              gets the focused item.
/// - `env`: The environment with bindings (focus variables, parent slots, etc.)
class _Tuple {
  final dynamic value;
  final dynamic context;
  final Environment env;
  _Tuple(this.value, this.env, {dynamic? context}) : context = context ?? value;
}

/// A tuple containing an item and its evaluated sort keys.
class _SortTuple {
  final dynamic item;
  final List<dynamic> keys;
  _SortTuple(this.item, this.keys);
}

/// A tuple containing an item, its sort keys, environment, and parent context.
/// Used for sorting with parent references.
class _SortTupleWithContext {
  final dynamic item;
  final List<dynamic> keys;
  final Environment env;
  final dynamic parentContext;
  _SortTupleWithContext(this.item, this.keys, this.env, this.parentContext);
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
      case final NameNode n:
        // NameNode can have ancestors attached by the parser
        slots.addAll(n.ancestors);
      case final WildcardNode w:
        // WildcardNode can also have ancestors attached
        slots.addAll(w.ancestors);
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
      case final SortNode s:
        _collectParentSlots(s.expr, slots);
        for (final term in s.terms) {
          _collectParentSlots(term.expr, slots);
        }
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
      final SortNode s => _evaluateSort(s, input, environment),
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
      // Check if key exists - distinguish between missing key and null value
      if (!input.containsKey(node.name)) {
        return undefined;
      }
      // Return the value even if it's null (JSON null is a valid value)
      return input[node.name];
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
    // FAST PATH: Simple name-only paths like a.b.c on non-array input
    // These don't need parent refs, focus ops, or keepArray checks
    // Only use fast path when input is a Map (not array) to avoid complex flattening
    if (input is Map && _isSimpleNamePath(node)) {
      final result = _evaluateSimplePath(node, input);
      if (result != null) return result;
      // Fall through to standard path if fast path returns null (might need special handling)
    }

    // FAST PATH: Paths with names and simple numeric index filters like a.b[0].c[0]
    // This pattern is very common for nested data access
    if (input is Map && _isSimpleIndexPath(node)) {
      final result = _evaluateSimpleIndexPath(node, input);
      if (result != null) return result;
      // Fall through if fast path can't handle it
    }

    // OPTIMIZATION: If left side is a simple NameNode with no ancestors,
    // we only need to check the right side for parent refs and focus ops.
    // This avoids full tree traversal for common patterns like: name.{...}, name[...], etc.
    final leftIsSimpleName = node.left is NameNode &&
                             (node.left as NameNode).ancestors.isEmpty;

    bool hasParentRefs;
    bool hasFocusOps;

    if (leftIsSimpleName) {
      // Only check the right side
      hasParentRefs = _findParentSlots(node.right).isNotEmpty;
      hasFocusOps = _containsFocusNode(node.right);
    } else {
      // Check the entire tree
      hasParentRefs = _findParentSlots(node).isNotEmpty;
      hasFocusOps = _containsFocusNode(node);
    }

    if (hasParentRefs || hasFocusOps) {
      // Use tuple-based evaluation for paths with parent references or focus operators
      return _evaluatePathWithTuples(node, input, env);
    }

    // Standard path evaluation (no parent references)
    return _evaluatePathStandard(node, input, env);
  }

  /// Check if a path consists only of simple name lookups (no filters, functions, etc.)
  /// and doesn't involve arrays at any level
  bool _isSimpleNamePath(AstNode node) {
    return switch (node) {
      NameNode n => n.ancestors.isEmpty,
      PathNode p => _isSimpleNamePath(p.left) && _isSimpleNamePath(p.right),
      _ => false,
    };
  }

  /// Fast evaluation for simple name-only paths like a.b.c
  /// Returns null if the path can't be handled with fast path
  /// Returns undefined if the path doesn't exist
  dynamic _evaluateSimplePath(PathNode node, dynamic input) {
    // Evaluate left side
    dynamic left;
    if (node.left is NameNode) {
      final name = (node.left as NameNode).value;
      if (input is Map) {
        left = input[name];
        if (left == null && !input.containsKey(name)) {
          return undefined;
        }
      } else {
        return null; // Can't use fast path
      }
    } else if (node.left is PathNode) {
      left = _evaluateSimplePath(node.left as PathNode, input);
      if (left == null) return null; // Can't use fast path
      if (isUndefined(left)) return undefined;
    } else {
      return null; // Can't use fast path
    }

    // Evaluate right side against left result
    final rightName = (node.right as NameNode).value;

    // If left is an array, project the right field over all elements (array projection)
    if (left is List) {
      final results = <dynamic>[];
      for (final item in left) {
        if (item is Map && item.containsKey(rightName)) {
          final value = item[rightName];
          if (!isUndefined(value)) {
            // Flatten nested arrays (JSONata semantics)
            if (value is List) {
              results.addAll(value);
            } else {
              results.add(value);
            }
          }
        }
      }
      return normalizeSequence(results);
    }

    // Handle single value
    if (left is Map) {
      final value = left[rightName];
      if (value == null && !left.containsKey(rightName)) {
        return undefined;
      }
      return value;
    }

    return undefined;
  }

  /// Check if a path consists of simple names and simple numeric index filters like a.b[0].c[0]
  /// This allows fast-path evaluation for very common nested data access patterns.
  bool _isSimpleIndexPath(AstNode node) {
    return switch (node) {
      NameNode n => n.ancestors.isEmpty,
      PathNode p => _isSimpleIndexPath(p.left) && _isSimpleIndexPath(p.right),
      FilterNode f =>
        f.expr is NameNode &&
        (f.expr as NameNode).ancestors.isEmpty &&
        _isSimpleLiteralIndex(f.predicate),
      _ => false,
    };
  }

  /// Check if a predicate is a simple literal index (positive or negative number)
  bool _isSimpleLiteralIndex(AstNode predicate) {
    if (predicate is NumberNode) return true;
    if (predicate is UnaryNode) {
      return predicate.operator == '-' && predicate.operand is NumberNode;
    }
    return false;
  }

  /// Fast evaluation for paths with names and simple index filters like a.b[0].c[0]
  /// Returns null if the path can't be handled with fast path (caller should use standard path)
  /// Returns undefined if the path doesn't exist
  dynamic _evaluateSimpleIndexPath(AstNode node, dynamic input) {
    if (node is NameNode) {
      if (input is Map) {
        if (!input.containsKey(node.value)) return undefined;
        return input[node.value];
      }
      return null; // Can't use fast path on non-Map
    }

    if (node is FilterNode) {
      // Get the field value first
      final fieldName = (node.expr as NameNode).value;
      if (input is! Map) return null;
      if (!input.containsKey(fieldName)) return undefined;

      final array = input[fieldName];
      if (array is! List) {
        // Single value with index [0] or [-1] returns the value
        int index = _getLiteralIndex(node.predicate);
        if (index == 0 || index == -1) return array;
        return undefined;
      }

      final index = _getLiteralIndex(node.predicate);
      final actualIndex = index < 0 ? array.length + index : index;
      if (actualIndex >= 0 && actualIndex < array.length) {
        return array[actualIndex];
      }
      return undefined;
    }

    if (node is PathNode) {
      // Evaluate left side
      final left = _evaluateSimpleIndexPath(node.left, input);
      if (left == null) return null; // Can't use fast path
      if (isUndefined(left)) return undefined;

      // If left is a list, we can't use this fast path
      if (left is List) return null;

      // Evaluate right side on the left result
      return _evaluateSimpleIndexPath(node.right, left);
    }

    return null; // Unknown node type
  }

  /// Get the literal integer index from a predicate (NumberNode or UnaryNode('-', NumberNode))
  int _getLiteralIndex(AstNode predicate) {
    if (predicate is NumberNode) {
      return predicate.value.toInt();
    }
    if (predicate is UnaryNode && predicate.operator == '-') {
      return -(predicate.operand as NumberNode).value.toInt();
    }
    throw StateError('Not a literal index');
  }

  /// Check if a node contains any FocusNode or IndexBindNode.
  bool _containsFocusNode(AstNode node) {
    return switch (node) {
      FocusNode() => true,
      IndexBindNode() => true,
      final PathNode p => _containsFocusNode(p.left) || _containsFocusNode(p.right),
      final FilterNode f => _containsFocusNode(f.expr) || _containsFocusNode(f.predicate),
      final BinaryNode b => _containsFocusNode(b.left) || _containsFocusNode(b.right),
      _ => false,
    };
  }

  /// Standard path evaluation without parent reference tracking.
  dynamic _evaluatePathStandard(PathNode node, dynamic input, Environment env) {
    var left = evaluate(node.left, input, env);
    if (isUndefined(left)) {
      return undefined;
    }

    // Check if this path should preserve array semantics
    // OPTIMIZATION: Simple NameNode can never be KeepArrayNode, skip the checks
    bool keepAsArray = node.left is KeepArrayNode || node.right is KeepArrayNode;
    if (!keepAsArray && node.left is FilterNode) {
      keepAsArray = (node.left as FilterNode).expr is KeepArrayNode;
    }
    if (!keepAsArray && node.left is! NameNode) {
      keepAsArray = _containsKeepArray(node.left);
    }

    // If the left side is a path ending with an ArrayNode, we need to flatten
    // the result before projecting the right side over it.
    // This handles cases like `arr.[field].next` where the array constructor
    // results should be flattened before accessing .next
    if (left is List && node.left is PathNode) {
      final leftPath = node.left as PathNode;
      if (leftPath.right is ArrayNode) {
        // Flatten one level of nested arrays
        final flattened = <dynamic>[];
        for (final item in left) {
          if (item is List) {
            flattened.addAll(item);
          } else if (!isUndefined(item)) {
            flattened.add(item);
          }
        }
        left = flattened.isEmpty ? undefined : (flattened.length == 1 ? flattened.first : flattened);
        if (isUndefined(left)) return undefined;
      }
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

    // If left is an array, map over it (except for SortNode which operates on the whole array)
    if (left is List) {
      // SortNode operates on the whole array, not per-element
      if (node.right is SortNode) {
        return evaluate(node.right, left, env.createChild(input: left));
      }

      // FAST PATH: Simple name projection over arrays (e.g., arr.fieldName)
      // This avoids creating child environments for each item
      if (node.right is NameNode &&
          (node.right as NameNode).ancestors.isEmpty) {
        final fieldName = (node.right as NameNode).value;
        final results = <dynamic>[];
        for (final item in left) {
          if (item is Map && item.containsKey(fieldName)) {
            final value = item[fieldName];
            if (!isUndefined(value)) {
              if (value is List) {
                results.addAll(value);
              } else {
                results.add(value);
              }
            }
          }
        }
        if (keepAsArray) {
          if (results.isEmpty) return undefined;
          return results;
        }
        return normalizeSequence(results);
      }

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
    // Initially, value and context are the same
    var tuples = [_Tuple(input, env, context: input)];

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];

      // SortNode needs special handling - it operates on ALL tuples at once
      if (step is SortNode) {
        tuples = _evaluateSortWithTuples(step, tuples, env);
        continue;
      }

      final newTuples = <_Tuple>[];

      for (final tuple in tuples) {
        // If this step has ancestor bindings, bind the CURRENT CONTEXT (before evaluating)
        // to each ancestor label. This is the parent value for subsequent % operators.
        // Use tuple.context (navigation context) for ancestor binding, not tuple.value
        final ancestors = _getStepAncestors(step);
        Environment stepEnv = tuple.env;
        if (ancestors.isNotEmpty) {
          stepEnv = tuple.env.createChild(input: tuple.context);
          for (final ancestor in ancestors) {
            stepEnv.bind(ancestor.label, tuple.context);
          }
        }

        // Handle FocusNode specially - bind variable to each result
        // but keep the navigation context unchanged
        if (step is FocusNode) {
          final focusResults = _evaluateFocusStepWithContext(step, tuple.context, stepEnv);
          for (final (result, resultEnv, newContext) in focusResults) {
            newTuples.add(_Tuple(result, resultEnv, context: newContext));
          }
        } else if (step is IndexBindNode) {
          // Handle IndexBindNode - bind the iteration index to a variable
          final indexResults = _evaluateIndexBindStepWithContext(step, tuple.context, stepEnv);
          for (final (result, resultEnv, newContext) in indexResults) {
            newTuples.add(_Tuple(result, resultEnv, context: newContext));
          }
        } else if (step is FilterNode) {
          // Handle FilterNode specially to preserve focus bindings
          final filterResults = _evaluateFilterWithTuplesAndContext(step, tuple.context, stepEnv);
          for (final (result, resultEnv, newContext) in filterResults) {
            newTuples.add(_Tuple(result, resultEnv, context: newContext));
          }
        } else {
          // Regular step - evaluate and update both value and context
          final stepResults = _evaluateStep(step, tuple.context, stepEnv);

          for (final result in stepResults) {
            // Create new environment for this result
            final childEnv = stepEnv.createChild(input: result);
            // Both value and context become the result
            newTuples.add(_Tuple(result, childEnv, context: result));
          }
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

  /// Evaluate a FocusNode step, returning a list of (result, environment, context) tuples.
  /// Each result has the focus variable bound in its environment.
  ///
  /// IMPORTANT: The focus operator binds the variable to each result,
  /// but the current context (@) remains the ORIGINAL input, not the result.
  /// This allows subsequent steps to navigate from the parent context.
  ///
  /// Returns: (value, environment, navigation_context)
  /// - value: The focused result (for producing final output)
  /// - environment: Contains the focus variable binding
  /// - navigation_context: Stays as input (for parent references)
  List<(dynamic, Environment, dynamic)> _evaluateFocusStepWithContext(FocusNode node, dynamic input, Environment env) {
    if (isUndefined(input) || input == null) {
      return [];
    }

    // Evaluate the inner expression
    final innerResults = _evaluateStep(node.expr, input, env);

    // For each result, bind the focus variable to that result
    // BUT keep the current context as the ORIGINAL input (not the result)
    final results = <(dynamic, Environment, dynamic)>[];
    for (final result in innerResults) {
      // Keep input as the current context, not result
      final childEnv = env.createChild(input: input);
      // Bind the focus variable (e.g., $L) to the result
      childEnv.bind(node.variable, result);
      // value = result (the focused item)
      // context = input (stays at parent level for navigation and parent references)
      results.add((result, childEnv, input));
    }

    return results;
  }

  /// Evaluate an IndexBindNode step, returning a list of (result, environment, context) tuples.
  /// Each result has the index variable bound in its environment.
  ///
  /// The index bind operator (#$var) binds the iteration index to a variable.
  /// Unlike focus (@$var) which binds the value, this binds the 0-based index.
  ///
  /// Returns: (value, environment, navigation_context)
  /// - value: The result item (for producing final output)
  /// - environment: Contains the index variable binding
  /// - navigation_context: The result item (unlike focus, context moves forward)
  List<(dynamic, Environment, dynamic)> _evaluateIndexBindStepWithContext(IndexBindNode node, dynamic input, Environment env) {
    if (isUndefined(input) || input == null) {
      return [];
    }

    // Evaluate the inner expression
    final innerResults = _evaluateStep(node.expr, input, env);

    // For each result, bind the index variable to the iteration index
    final results = <(dynamic, Environment, dynamic)>[];
    for (var i = 0; i < innerResults.length; i++) {
      final result = innerResults[i];
      // Create child environment with the result as input
      final childEnv = env.createChild(input: result);
      // Bind the index variable (e.g., $o) to the iteration index
      childEnv.bind(node.variable, i);
      // value = result, context = result (navigation moves forward)
      results.add((result, childEnv, result));
    }

    return results;
  }

  /// Evaluate a FilterNode in tuple context, preserving focus bindings.
  /// Returns a list of (result, environment, context) tuples.
  ///
  /// Returns: (value, environment, navigation_context)
  /// - value: The filtered result item (for producing final output)
  /// - environment: Contains focus variable binding if present
  /// - navigation_context: Stays as input when focus is present (for parent references)
  List<(dynamic, Environment, dynamic)> _evaluateFilterWithTuplesAndContext(FilterNode node, dynamic input, Environment env) {
    // Check if this filter should preserve array semantics
    final keepArray = node.expr is KeepArrayNode;

    // Unwrap KeepArrayNode to get actual expression
    AstNode exprNode = keepArray ? (node.expr as KeepArrayNode).expr : node.expr;

    // Check if the expression is a FocusNode - if so, we need special handling
    String? focusVariable;
    if (exprNode is FocusNode) {
      focusVariable = exprNode.variable;
      exprNode = exprNode.expr;
    }

    // Check if the filter expression has ancestor bindings
    // Use _getStepAncestors to handle complex expressions like BlockNode, PathNode, etc.
    final ancestors = _getStepAncestors(exprNode);

    // Special case: If the expression is a BlockNode containing a path with ancestor slots,
    // we need to evaluate using tuples to capture each item's parent context
    if (ancestors.isNotEmpty && exprNode is BlockNode && exprNode.expressions.isNotEmpty) {
      final lastExpr = exprNode.expressions.last;
      if (lastExpr is PathNode) {
        final tuples = _evaluateBlockWithTuples(exprNode, input, env);
        final results = <(dynamic, Environment, dynamic)>[];

        for (var i = 0; i < tuples.length; i++) {
          final (item, itemEnv) = tuples[i];
          final childEnv = itemEnv.createChild(input: item);

          if (focusVariable != null) {
            childEnv.bind(focusVariable, item);
          }

          final predicate = evaluate(node.predicate, item, childEnv);

          if (predicate is num) {
            final index = predicate.toInt();
            final actualIndex = index < 0 ? tuples.length + index : index;
            if (actualIndex == i) {
              final newContext = focusVariable != null ? input : item;
              results.add((item, childEnv, newContext));
            }
          } else if (_isTruthy(predicate)) {
            final newContext = focusVariable != null ? input : item;
            results.add((item, childEnv, newContext));
          }
        }

        return results;
      }
    }

    Environment filterEnv = env;
    if (ancestors.isNotEmpty) {
      filterEnv = env.createChild(input: input);
      for (final ancestor in ancestors) {
        filterEnv.bind(ancestor.label, input);
      }
    }

    // Evaluate the expression (unwrapped from FocusNode if present)
    final expr = evaluate(exprNode, input, filterEnv);
    if (isUndefined(expr)) return [];

    final items = expr is List ? expr : [expr];
    final results = <(dynamic, Environment, dynamic)>[];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final childEnv = filterEnv.createChild(input: item);

      // If this filter has a focus variable, bind it to the current item
      if (focusVariable != null) {
        childEnv.bind(focusVariable, item);
      }

      final predicate = evaluate(node.predicate, item, childEnv);

      if (predicate is num) {
        // Index access
        final index = predicate.toInt();
        final actualIndex = index < 0 ? items.length + index : index;
        if (actualIndex == i) {
          // Return the item with focus binding and proper context
          // If focus variable is present, context stays as input (not the item)
          final newContext = focusVariable != null ? input : item;
          results.add((item, childEnv, newContext));
        }
      } else if (_isTruthy(predicate)) {
        // Return the item with focus binding and proper context
        // If focus variable is present, context stays as input (not the item)
        final newContext = focusVariable != null ? input : item;
        results.add((item, childEnv, newContext));
      }
    }

    return results;
  }

  /// Get the ancestor slots for a step if it has any.
  List<ParentSlot> _getStepAncestors(AstNode step) {
    if (step is NameNode) return step.ancestors;
    if (step is WildcardNode) return step.ancestors;
    if (step is FocusNode) return _getStepAncestors(step.expr);
    if (step is IndexBindNode) return _getStepAncestors(step.expr);
    if (step is FilterNode) return _getStepAncestors(step.expr);
    if (step is BlockNode && step.expressions.isNotEmpty) {
      return _getStepAncestors(step.expressions.last);
    }
    if (step is PathNode) {
      // For paths, check the rightmost node first (deepest in the path)
      final rightAncestors = _getStepAncestors(step.right);
      if (rightAncestors.isNotEmpty) return rightAncestors;
      return _getStepAncestors(step.left);
    }
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

  /// Evaluate a sort expression.
  ///
  /// The sort operator (^) sorts an array based on one or more sort terms.
  /// Each term specifies a key expression and whether to sort ascending or descending.
  dynamic _evaluateSort(SortNode node, dynamic input, Environment env) {
    // First, evaluate the expression to get the array to sort
    final result = evaluate(node.expr, input, env);

    // If undefined or null, return undefined
    if (isUndefined(result) || result == null) {
      return undefined;
    }

    // Convert to list if not already
    final List<dynamic> items;
    if (result is List) {
      items = List<dynamic>.from(result);
    } else {
      // Single item - still apply sort (returns the same item)
      items = [result];
    }

    // If empty or single item, return as-is
    if (items.isEmpty) {
      return undefined;
    }
    if (items.length == 1) {
      return items[0];
    }

    // Evaluate sort keys for each item
    // Each item becomes a tuple of (item, [key1, key2, ...])
    final sortTuples = <_SortTuple>[];
    for (final item in items) {
      final keys = <dynamic>[];
      for (final term in node.terms) {
        // For self-reference ($), the key is the item itself
        final keyValue = _evaluateSortKey(term.expr, item, env);
        keys.add(keyValue);
      }
      sortTuples.add(_SortTuple(item, keys));
    }

    // Sort the tuples
    try {
      sortTuples.sort((a, b) => _compareSortTuples(a, b, node.terms, node.position));
    } on JsonataException {
      rethrow;
    }

    // Extract sorted items
    final sorted = sortTuples.map((t) => t.item).toList();

    return sorted;
  }

  /// Evaluate a sort key expression for an item.
  dynamic _evaluateSortKey(AstNode expr, dynamic item, Environment env) {
    // Create a child environment with the item as input
    final itemEnv = env.createChild(input: item);
    final key = evaluate(expr, item, itemEnv);
    return key;
  }

  /// Evaluate a SortNode with tuple tracking for parent references.
  /// This is used when the sort key expression contains % (parent references).
  List<_Tuple> _evaluateSortWithTuples(SortNode node, List<_Tuple> tuples, Environment env) {
    // First, evaluate the SortNode's inner expression for each tuple,
    // keeping track of the parent context for each result.
    // Each input tuple can produce multiple results (if the expr evaluates to an array).
    final itemsWithContext = <(dynamic item, Environment itemEnv, dynamic parentContext)>[];

    for (final tuple in tuples) {
      // Get ancestors from the sort expression (e.g., SKU with ancestors)
      final ancestors = _getStepAncestors(node.expr);
      Environment stepEnv = tuple.env;
      if (ancestors.isNotEmpty) {
        stepEnv = tuple.env.createChild(input: tuple.context);
        for (final ancestor in ancestors) {
          stepEnv.bind(ancestor.label, tuple.context);
        }
      }

      // Evaluate the inner expression (e.g., SKU)
      final results = _evaluateStep(node.expr, tuple.context, stepEnv);

      for (final result in results) {
        // Each result's parent context is the tuple's context (e.g., Product)
        itemsWithContext.add((result, stepEnv, tuple.context));
      }
    }

    if (itemsWithContext.isEmpty) {
      return [];
    }

    // Now sort the items using the sort terms
    // The key expression needs access to the parent context via % operator
    final sortTuples = <_SortTupleWithContext>[];
    for (final (item, itemEnv, parentContext) in itemsWithContext) {
      final keys = <dynamic>[];
      for (final term in node.terms) {
        // Evaluate the sort key with the item as input
        // The environment (itemEnv) has parent context bindings for % operator
        final key = evaluate(term.expr, item, itemEnv);
        keys.add(key);
      }
      sortTuples.add(_SortTupleWithContext(item, keys, itemEnv, parentContext));
    }

    // Sort the tuples
    try {
      sortTuples.sort((a, b) => _compareSortTuples(
        _SortTuple(a.item, a.keys),
        _SortTuple(b.item, b.keys),
        node.terms,
        node.position,
      ));
    } on JsonataException {
      rethrow;
    }

    // Return sorted tuples
    return sortTuples.map((t) {
      final childEnv = t.env.createChild(input: t.item);
      return _Tuple(t.item, childEnv, context: t.item);
    }).toList();
  }

  /// Compare two sort tuples based on the sort terms.
  int _compareSortTuples(
    _SortTuple a,
    _SortTuple b,
    List<SortTerm> terms,
    int position,
  ) {
    for (var i = 0; i < terms.length; i++) {
      final keyA = a.keys[i];
      final keyB = b.keys[i];
      final descending = terms[i].descending;

      final cmp = _compareSortValues(keyA, keyB, position);
      if (cmp != 0) {
        return descending ? -cmp : cmp;
      }
    }
    return 0;
  }

  /// Compare two sort values.
  ///
  /// Throws T2007 for type mismatch, T2008 for non-comparable values.
  int _compareSortValues(dynamic a, dynamic b, int position) {
    // Handle undefined values - undefined should be LAST in sort order
    // Note: null is NOT treated as undefined - null should throw T2008
    final aUndef = isUndefined(a);
    final bUndef = isUndefined(b);

    if (aUndef && bUndef) return 0;
    if (aUndef) return 1; // undefined is "greater than" defined, sorts last
    if (bUndef) return -1; // defined is "less than" undefined

    // Check types
    final aIsNum = a is num;
    final bIsNum = b is num;
    final aIsStr = a is String;
    final bIsStr = b is String;

    // If both are numbers
    if (aIsNum && bIsNum) {
      return a.compareTo(b);
    }

    // If both are strings
    if (aIsStr && bIsStr) {
      return a.compareTo(b);
    }

    // Type mismatch (one is number, other is string)
    if ((aIsNum && bIsStr) || (aIsStr && bIsNum)) {
      throw JsonataException(
        'T2007',
        'Type mismatch when comparing values $a and $b in order-by clause',
        position: position,
        value: [a, b],
      );
    }

    // Neither is a sortable type (bool, object, array, etc.)
    throw JsonataException(
      'T2008',
      'The expressions within an order-by clause must evaluate to numeric or string values',
      position: position,
      value: aIsNum || aIsStr ? b : a,
    );
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
    // FAST PATH: Simple numeric literal index without special features
    // This avoids iterating through all items and creating child environments
    // Handles both positive (NumberNode) and negative (UnaryNode with -) indices
    if (node.expr is! KeepArrayNode && node.expr is! FocusNode) {
      int? literalIndex;

      if (node.predicate is NumberNode) {
        literalIndex = (node.predicate as NumberNode).value.toInt();
      } else if (node.predicate is UnaryNode) {
        final unary = node.predicate as UnaryNode;
        if (unary.operator == '-' && unary.operand is NumberNode) {
          literalIndex = -(unary.operand as NumberNode).value.toInt();
        }
      }

      if (literalIndex != null) {
        final expr = evaluate(node.expr, input, env);
        if (isUndefined(expr)) return undefined;

        final items = expr is List ? expr : [expr];
        final actualIndex =
            literalIndex < 0 ? items.length + literalIndex : literalIndex;
        if (actualIndex >= 0 && actualIndex < items.length) {
          return items[actualIndex];
        }
        return undefined;
      }

      // FAST PATH: Simple equality predicate like [field = 'value'] or [field = 123]
      // This avoids creating child environments for each item
      if (node.predicate is BinaryNode) {
        final binary = node.predicate as BinaryNode;
        if (binary.operator == '=' &&
            binary.left is NameNode &&
            (binary.left as NameNode).ancestors.isEmpty) {
          final fieldName = (binary.left as NameNode).value;
          dynamic compareValue;
          bool isSimpleLiteral = false;

          if (binary.right is StringNode) {
            compareValue = (binary.right as StringNode).value;
            isSimpleLiteral = true;
          } else if (binary.right is NumberNode) {
            compareValue = (binary.right as NumberNode).value;
            isSimpleLiteral = true;
          } else if (binary.right is BooleanNode) {
            compareValue = (binary.right as BooleanNode).value;
            isSimpleLiteral = true;
          } else if (binary.right is NullNode) {
            compareValue = null;
            isSimpleLiteral = true;
          }

          if (isSimpleLiteral) {
            final expr = evaluate(node.expr, input, env);
            if (isUndefined(expr)) return undefined;

            final items = expr is List ? expr : [expr];
            final results = <dynamic>[];

            for (final item in items) {
              if (item is Map && item[fieldName] == compareValue) {
                results.add(item);
              }
            }

            return normalizeSequence(results);
          }
        }
      }
    }

    // Check if this filter should preserve array semantics
    final keepArray = node.expr is KeepArrayNode;

    // Unwrap KeepArrayNode to get actual expression
    AstNode exprNode = keepArray ? (node.expr as KeepArrayNode).expr : node.expr;

    // Check if the expression is a FocusNode - if so, we need special handling
    String? focusVariable;
    if (exprNode is FocusNode) {
      focusVariable = exprNode.variable;
      exprNode = exprNode.expr;
    }

    // Check if the filter expression has ancestor bindings
    // Use _getStepAncestors to handle complex expressions like BlockNode, PathNode, etc.
    final ancestors = _getStepAncestors(exprNode);

    // Special case: If the expression is a BlockNode containing a path with ancestor slots,
    // we need to evaluate using tuples to capture each item's parent context
    if (ancestors.isNotEmpty && exprNode is BlockNode && exprNode.expressions.isNotEmpty) {
      final lastExpr = exprNode.expressions.last;
      if (lastExpr is PathNode) {
        final tuples = _evaluateBlockWithTuples(exprNode, input, env);
        final results = <dynamic>[];

        for (var i = 0; i < tuples.length; i++) {
          final (item, itemEnv) = tuples[i];
          final childEnv = itemEnv.createChild(input: item);

          if (focusVariable != null) {
            childEnv.bind(focusVariable, item);
          }

          final predicate = evaluate(node.predicate, item, childEnv);

          if (predicate is num) {
            final index = predicate.toInt();
            final actualIndex = index < 0 ? tuples.length + index : index;
            if (actualIndex == i) {
              results.add(item);
            }
          } else if (_isTruthy(predicate)) {
            results.add(item);
          }
        }

        if (keepArray) {
          if (results.isEmpty) return undefined;
          return results;
        }
        return normalizeSequence(results);
      }
    }

    Environment filterEnv = env;
    if (ancestors.isNotEmpty) {
      filterEnv = env.createChild(input: input);
      for (final ancestor in ancestors) {
        filterEnv.bind(ancestor.label, input);
      }
    }

    // Evaluate the expression (unwrapped from FocusNode if present)
    final expr = evaluate(exprNode, input, filterEnv);
    if (isUndefined(expr)) return undefined;

    final items = expr is List ? expr : [expr];
    final results = <dynamic>[];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final childEnv = filterEnv.createChild(input: item);

      // If this filter has a focus variable, bind it to the current item
      if (focusVariable != null) {
        childEnv.bind(focusVariable, item);
      }

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

  /// Evaluate a BlockNode and return tuples of (value, environment) for each result.
  /// This is used when the block contains a path with ancestor slots that need
  /// to be preserved for filter predicates.
  List<(dynamic, Environment)> _evaluateBlockWithTuples(BlockNode node, dynamic input, Environment env) {
    final blockEnv = env.createChild(input: input);

    // For all expressions except the last, just evaluate normally
    for (var i = 0; i < node.expressions.length - 1; i++) {
      evaluate(node.expressions[i], input, blockEnv);
    }

    // For the last expression (which should be a PathNode), use tuple evaluation
    final lastExpr = node.expressions.last;
    if (lastExpr is PathNode) {
      // Check for parent slots in this path
      final parentSlots = _findParentSlots(lastExpr);
      if (parentSlots.isNotEmpty) {
        // Flatten the path into steps
        final steps = <AstNode>[];
        _flattenPath(lastExpr, steps);

        // Start with the input as a single tuple
        var tuples = [_Tuple(input, blockEnv, context: input)];

        for (var i = 0; i < steps.length; i++) {
          final step = steps[i];
          final newTuples = <_Tuple>[];

          for (final tuple in tuples) {
            // Bind ancestors to the current context
            final ancestors = _getStepAncestors(step);
            Environment stepEnv = tuple.env;
            if (ancestors.isNotEmpty) {
              stepEnv = tuple.env.createChild(input: tuple.context);
              for (final ancestor in ancestors) {
                stepEnv.bind(ancestor.label, tuple.context);
              }
            }

            // Evaluate the step
            final stepResults = _evaluateStep(step, tuple.context, stepEnv);

            for (final result in stepResults) {
              final childEnv = stepEnv.createChild(input: result);
              newTuples.add(_Tuple(result, childEnv, context: result));
            }
          }

          tuples = newTuples;
        }

        // Return (value, env) tuples - the env contains ancestor bindings
        return tuples.where((t) => !isUndefined(t.value)).map((t) => (t.value, t.env)).toList();
      }
    }

    // Fallback: evaluate normally and wrap each result
    final result = evaluate(lastExpr, input, blockEnv);
    if (isUndefined(result)) return [];
    if (result is List) {
      return result.map((item) => (item, blockEnv)).toList();
    }
    return [(result, blockEnv)];
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