import 'dart:collection';

import 'undefined.dart';

/// A JSONata sequence - a list with special singleton behavior.
///
/// In JSONata, sequences have special semantics:
/// - An empty sequence is equivalent to undefined
/// - A single-item sequence is equivalent to that item
/// - Multi-item sequences behave as arrays
///
/// This class implements [List] to allow normal list operations while
/// providing the [value] getter for JSONata-specific unwrapping behavior.
class JsonataSequence<T> extends ListBase<T> {
  final List<T> _inner;

  /// Creates an empty sequence.
  JsonataSequence() : _inner = [];

  /// Creates a sequence from an existing list.
  JsonataSequence.from(Iterable<T> items) : _inner = List<T>.from(items);

  /// Creates a sequence with a single item.
  JsonataSequence.single(T item) : _inner = [item];

  @override
  int get length => _inner.length;

  @override
  set length(int newLength) => _inner.length = newLength;

  @override
  T operator [](int index) => _inner[index];

  @override
  void operator []=(int index, T value) => _inner[index] = value;

  @override
  void add(T element) => _inner.add(element);

  @override
  void addAll(Iterable<T> iterable) => _inner.addAll(iterable);

  /// Gets the unwrapped value according to JSONata semantics.
  ///
  /// - Empty sequence returns [Undefined.instance]
  /// - Single-item sequence returns that item
  /// - Multi-item sequence returns the sequence itself
  dynamic get value {
    if (isEmpty) return Undefined.instance;
    if (length == 1) return first;
    return this;
  }

  /// Returns true if this is a JSONata sequence.
  bool get isSequence => true;
}

/// Creates a new JSONata sequence.
///
/// If [item] is provided, creates a sequence with that single item.
/// Otherwise creates an empty sequence.
JsonataSequence<dynamic> createSequence([dynamic item]) {
  if (item != null && !isUndefined(item)) {
    return JsonataSequence.single(item);
  }
  return JsonataSequence();
}

/// Returns true if [value] is a JSONata sequence.
bool isSequence(dynamic value) => value is JsonataSequence;

/// Appends a value to a sequence, creating a new sequence if needed.
///
/// Handles the special JSONata semantics for building up result sequences.
JsonataSequence<dynamic> appendToSequence(dynamic sequence, dynamic value) {
  if (isUndefined(value)) {
    if (sequence is JsonataSequence) return sequence;
    return createSequence(sequence);
  }

  final result = JsonataSequence<dynamic>();

  if (sequence is JsonataSequence) {
    result.addAll(sequence);
  } else if (!isUndefined(sequence)) {
    result.add(sequence);
  }

  if (value is JsonataSequence) {
    result.addAll(value);
  } else {
    result.add(value);
  }

  return result;
}

