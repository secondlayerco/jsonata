import 'package:jsonata/jsonata.dart';
import 'package:test/test.dart';

void main() {
  // Test empty block and object constructor
  group('Object Constructor with undefined', () {
    test('object with undefined value should exclude key', () {
      final expr = Jsonata('{"test": ()}');
      expect(expr.evaluate(null), equals({}));
    });
  });

  group('Basic Path Expressions', () {
    test('simple field access', () {
      final expr = Jsonata('name');
      expect(expr.evaluate({'name': 'John'}), equals('John'));
    });

    test('nested field access', () {
      final expr = Jsonata('person.name');
      expect(
        expr.evaluate({'person': {'name': 'John'}}),
        equals('John'),
      );
    });

    test('deep nested access', () {
      final expr = Jsonata('a.b.c.d');
      expect(
        expr.evaluate({'a': {'b': {'c': {'d': 42}}}}),
        equals(42),
      );
    });

    test('missing field returns null', () {
      final expr = Jsonata('missing');
      expect(expr.evaluate({'name': 'John'}), isNull);
    });
  });

  group('Literals', () {
    test('number literal', () {
      final expr = Jsonata('42');
      expect(expr.evaluate(null), equals(42));
    });

    test('string literal', () {
      final expr = Jsonata('"hello"');
      expect(expr.evaluate(null), equals('hello'));
    });

    test('boolean true', () {
      final expr = Jsonata('true');
      expect(expr.evaluate(null), equals(true));
    });

    test('boolean false', () {
      final expr = Jsonata('false');
      expect(expr.evaluate(null), equals(false));
    });

    test('null literal', () {
      final expr = Jsonata('null');
      expect(expr.evaluate(null), isNull);
    });
  });

  group('Arithmetic', () {
    test('addition', () {
      final expr = Jsonata('1 + 2');
      expect(expr.evaluate(null), equals(3));
    });

    test('subtraction', () {
      final expr = Jsonata('5 - 3');
      expect(expr.evaluate(null), equals(2));
    });

    test('multiplication', () {
      final expr = Jsonata('4 * 5');
      expect(expr.evaluate(null), equals(20));
    });

    test('division', () {
      final expr = Jsonata('10 / 2');
      expect(expr.evaluate(null), equals(5.0));
    });

    test('modulo', () {
      final expr = Jsonata('7 % 3');
      expect(expr.evaluate(null), equals(1));
    });

    test('unary minus', () {
      final expr = Jsonata('-5');
      expect(expr.evaluate(null), equals(-5));
    });

    test('complex expression', () {
      final expr = Jsonata('(2 + 3) * 4');
      expect(expr.evaluate(null), equals(20));
    });
  });

  group('Comparison', () {
    test('equality', () {
      final expr = Jsonata('value = 10');
      expect(expr.evaluate({'value': 10}), equals(true));
      expect(expr.evaluate({'value': 5}), equals(false));
    });

    test('inequality', () {
      final expr = Jsonata('value != 10');
      expect(expr.evaluate({'value': 5}), equals(true));
    });

    test('less than', () {
      final expr = Jsonata('value < 10');
      expect(expr.evaluate({'value': 5}), equals(true));
      expect(expr.evaluate({'value': 15}), equals(false));
    });

    test('greater than', () {
      final expr = Jsonata('value > 10');
      expect(expr.evaluate({'value': 15}), equals(true));
    });
  });

  group('Logical Operators', () {
    test('and operator', () {
      final expr = Jsonata('a and b');
      expect(expr.evaluate({'a': true, 'b': true}), equals(true));
      expect(expr.evaluate({'a': true, 'b': false}), equals(false));
    });

    test('or operator', () {
      final expr = Jsonata('a or b');
      expect(expr.evaluate({'a': false, 'b': true}), equals(true));
      expect(expr.evaluate({'a': false, 'b': false}), equals(false));
    });
  });

  group('String Concatenation', () {
    test('basic concatenation', () {
      final expr = Jsonata('"Hello" & " " & "World"');
      expect(expr.evaluate(null), equals('Hello World'));
    });

    test('concat with field values', () {
      final expr = Jsonata('first & " " & last');
      expect(
        expr.evaluate({'first': 'John', 'last': 'Doe'}),
        equals('John Doe'),
      );
    });
  });

  group('Arrays', () {
    test('array constructor', () {
      final expr = Jsonata('[1, 2, 3]');
      expect(expr.evaluate(null), equals([1, 2, 3]));
    });

    test('array access', () {
      final expr = Jsonata('items[0]');
      expect(expr.evaluate({'items': ['a', 'b', 'c']}), equals('a'));
    });

    test('negative array index', () {
      final expr = Jsonata('items[-1]');
      expect(expr.evaluate({'items': ['a', 'b', 'c']}), equals('c'));
    });
  });

  group('Objects', () {
    test('object constructor', () {
      final expr = Jsonata('{"name": "John", "age": 30}');
      expect(expr.evaluate(null), equals({'name': 'John', 'age': 30}));
    });
  });

  group('Conditional', () {
    test('ternary with true condition', () {
      final expr = Jsonata('value > 5 ? "big" : "small"');
      expect(expr.evaluate({'value': 10}), equals('big'));
    });

    test('ternary with false condition', () {
      final expr = Jsonata('value > 5 ? "big" : "small"');
      expect(expr.evaluate({'value': 3}), equals('small'));
    });
  });

  group('Variables', () {
    test('variable binding', () {
      final expr = Jsonata(r'($x := 5; $x * 2)');
      expect(expr.evaluate(null), equals(10));
    });

    test('external variable binding', () {
      final jsonata = Jsonata(r'$multiplier * value');
      jsonata.bind('multiplier', 10);
      expect(jsonata.evaluate({'value': 5}), equals(50));
    });
  });

  group('Lambda Functions', () {
    test('lambda definition and call', () {
      final expr = Jsonata(r'($double := function($x) { $x * 2 }; $double(5))');
      expect(expr.evaluate(null), equals(10));
    });
  });

  group('Built-in Functions', () {
    test(r'$sum', () {
      final expr = Jsonata(r'$sum([1, 2, 3, 4, 5])');
      expect(expr.evaluate(null), equals(15));
    });

    test(r'$count', () {
      final expr = Jsonata(r'$count([1, 2, 3])');
      expect(expr.evaluate(null), equals(3));
    });

    test(r'$string', () {
      final expr = Jsonata(r'$string(42)');
      expect(expr.evaluate(null), equals('42'));
    });

    test(r'$length', () {
      final expr = Jsonata(r'$length("hello")');
      expect(expr.evaluate(null), equals(5));
    });

    test(r'$uppercase', () {
      final expr = Jsonata(r'$uppercase("hello")');
      expect(expr.evaluate(null), equals('HELLO'));
    });

    test(r'$lowercase', () {
      final expr = Jsonata(r'$lowercase("HELLO")');
      expect(expr.evaluate(null), equals('hello'));
    });

    test(r'$substring', () {
      final expr = Jsonata(r'$substring("hello world", 0, 5)');
      expect(expr.evaluate(null), equals('hello'));
    });

    test(r'$split', () {
      final expr = Jsonata(r'$split("a,b,c", ",")');
      expect(expr.evaluate(null), equals(['a', 'b', 'c']));
    });

    test(r'$join', () {
      final expr = Jsonata(r'$join(["a", "b", "c"], "-")');
      expect(expr.evaluate(null), equals('a-b-c'));
    });

    test(r'$abs', () {
      final expr = Jsonata(r'$abs(-5)');
      expect(expr.evaluate(null), equals(5));
    });

    test(r'$floor', () {
      final expr = Jsonata(r'$floor(3.7)');
      expect(expr.evaluate(null), equals(3));
    });

    test(r'$ceil', () {
      final expr = Jsonata(r'$ceil(3.2)');
      expect(expr.evaluate(null), equals(4));
    });

    test(r'$round', () {
      final expr = Jsonata(r'$round(3.456, 2)');
      expect(expr.evaluate(null), equals(3.46));
    });

    test(r'$keys', () {
      final expr = Jsonata(r'$keys({"a": 1, "b": 2})');
      expect(expr.evaluate(null), containsAll(['a', 'b']));
    });

    test(r'$values', () {
      final expr = Jsonata(r'$values({"a": 1, "b": 2})');
      expect(expr.evaluate(null), containsAll([1, 2]));
    });

    test(r'$type', () {
      expect(Jsonata(r'$type(42)').evaluate(null), equals('number'));
      expect(Jsonata(r'$type("hi")').evaluate(null), equals('string'));
      expect(Jsonata(r'$type(true)').evaluate(null), equals('boolean'));
      expect(Jsonata(r'$type([])').evaluate(null), equals('array'));
      expect(Jsonata(r'$type({})').evaluate(null), equals('object'));
    });

    test(r'$boolean', () {
      expect(Jsonata(r'$boolean(1)').evaluate(null), equals(true));
      expect(Jsonata(r'$boolean(0)').evaluate(null), equals(false));
      expect(Jsonata(r'$boolean("")').evaluate(null), equals(false));
      expect(Jsonata(r'$boolean("hi")').evaluate(null), equals(true));
    });

    test(r'$not', () {
      expect(Jsonata(r'$not(true)').evaluate(null), equals(false));
      expect(Jsonata(r'$not(false)').evaluate(null), equals(true));
    });
  });

  group('Range', () {
    test('simple range', () {
      final expr = Jsonata('[1..5]');
      expect(expr.evaluate(null), equals([1, 2, 3, 4, 5]));
    });
  });

  group('Wildcard', () {
    test('* operator on object', () {
      final expr = Jsonata('obj.*');
      expect(
        expr.evaluate({'obj': {'a': 1, 'b': 2, 'c': 3}}),
        containsAll([1, 2, 3]),
      );
    });
  });
}

