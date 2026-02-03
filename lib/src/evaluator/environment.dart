import '../utils/undefined.dart';
import 'evaluator.dart';

/// A function that can be called from JSONata expressions.
typedef JsonataFunction = dynamic Function(
  List<dynamic> args,
  dynamic input,
  Environment environment,
);

/// Represents an execution environment with variable bindings.
///
/// Environments form a chain for lexical scoping - each environment
/// has an optional parent that is searched if a binding is not found locally.
class Environment {
  final Environment? _parent;
  final Map<String, dynamic> _bindings = {};
  final Map<String, JsonataFunction> _functions = {};
  Evaluator? _evaluator;

  /// The current input being processed (for $ reference).
  dynamic input;

  /// Creates a new environment.
  Environment({Environment? parent, this.input}) : _parent = parent;

  /// Sets the evaluator for this environment (used for HOF).
  void setEvaluator(Evaluator evaluator) {
    _evaluator = evaluator;
  }

  /// Gets the evaluator (searches up the parent chain if needed).
  Evaluator? get evaluator {
    if (_evaluator != null) return _evaluator;
    return _parent?.evaluator;
  }

  /// Creates a child environment with this as parent.
  Environment createChild({dynamic input}) {
    return Environment(parent: this, input: input ?? this.input);
  }

  /// Binds a value to a variable name.
  void bind(String name, dynamic value) {
    _bindings[name] = value;
  }

  /// Looks up a variable binding.
  ///
  /// Returns [undefined] if the variable is not found.
  dynamic lookup(String name) {
    if (_bindings.containsKey(name)) {
      return _bindings[name];
    }
    final parent = _parent;
    if (parent != null) {
      return parent.lookup(name);
    }
    return undefined;
  }

  /// Checks if a variable is bound in this environment or any parent.
  bool contains(String name) {
    if (_bindings.containsKey(name)) {
      return true;
    }
    return _parent?.contains(name) ?? false;
  }

  /// Registers a function.
  void registerFunction(String name, JsonataFunction function) {
    _functions[name] = function;
  }

  /// Looks up a function by name.
  JsonataFunction? lookupFunction(String name) {
    if (_functions.containsKey(name)) {
      return _functions[name];
    }
    return _parent?.lookupFunction(name);
  }

  /// Gets the root input (for $$ reference).
  dynamic get rootInput {
    final parent = _parent;
    if (parent == null) {
      return input;
    }
    return parent.rootInput;
  }
}
