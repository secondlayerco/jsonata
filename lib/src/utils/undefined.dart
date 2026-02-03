/// Sentinel value representing JSONata's "undefined" concept.
///
/// JSONata distinguishes between `undefined` (missing/no value) and `null`
/// (explicit null value). This class provides a way to represent that
/// distinction in Dart.
///
/// Use [isUndefined] to check if a value is undefined.
/// Use [undefined] constant to get the undefined value.
class Undefined {
  const Undefined._();

  /// The singleton undefined instance.
  static const instance = Undefined._();

  @override
  String toString() => 'undefined';
}

/// The undefined value constant for easy use.
const undefined = Undefined.instance;

/// Returns true if [value] represents JSONata's undefined value.
bool isUndefined(dynamic value) => value == undefined;

/// Normalizes a value for external output.
///
/// Converts [Undefined] to null and recursively processes collections.
dynamic normalizeResult(dynamic value) {
  if (isUndefined(value)) return null;
  if (value is List) {
    return value.map(normalizeResult).toList();
  }
  if (value is Map) {
    return value.map((k, v) => MapEntry(k, normalizeResult(v)));
  }
  return value;
}
