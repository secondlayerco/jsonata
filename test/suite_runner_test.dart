import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:jsonata_dart/jsonata_dart.dart';

/// Core test groups (non-function-specific)
const coreGroups = [
  'array-constructor',
  'blocks',
  'boolean-expresssions',
  'closures',
  'comments',
  'comparison-operators',
  'conditionals',
  'context',
  'fields',
  'flattening',
  'lambdas',
  'literals',
  'null',
  'numeric-operators',
  'object-constructor',
  'parentheses',
  'predicates',
  'range-operator',
  'simple-array-selectors',
  'string-concat',
  'variables',
  'wildcards',
  // HOF tests
  'higher-order-functions',
  'hof-map',
  'hof-filter',
  'hof-reduce',
  // Regex tests
  'regex',
  // Date/time tests
  'function-fromMillis',
  'function-tomillis',
];

void main() {
  final datasets = <String, dynamic>{};

  setUpAll(() async {
    // Load all datasets
    final datasetDir = Directory('test/test-suite/datasets');
    for (final file in datasetDir.listSync()) {
      if (file is File && file.path.endsWith('.json')) {
        final name = file.path.split('/').last.replaceAll('.json', '');
        datasets[name] = jsonDecode(await file.readAsString());
      }
    }
  });

  for (final groupName in coreGroups) {
    group(groupName, () {
      final groupDir = Directory('test/test-suite/groups/$groupName');
      if (!groupDir.existsSync()) {
        test('SKIP: group not found', () {}, skip: true);
        return;
      }

      final caseFiles = groupDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      for (final caseFile in caseFiles) {
        final baseName = caseFile.path.split('/').last.replaceAll('.json', '');

        // Read file content synchronously for test registration
        final content = File(caseFile.path).readAsStringSync();
        final decoded = jsonDecode(content);

        // Handle both single test case and array of test cases
        final testCases = decoded is List ? decoded : [decoded];

        for (var i = 0; i < testCases.length; i++) {
          final testCase = testCases[i] as Map<String, dynamic>;
          final caseName = testCases.length > 1 ? '$baseName[$i]' : baseName;

          test(caseName, () {
            final expr = testCase['expr'] as String?;
            if (expr == null) {
              // Skip tests without expr (like metadata-only files)
              return;
            }

            // Get input data
            dynamic inputData;
            if (testCase.containsKey('dataset')) {
              final datasetName = testCase['dataset'];
              if (datasetName != null && datasetName is String) {
                inputData = datasets[datasetName];
              }
            } else if (testCase.containsKey('data')) {
              inputData = testCase['data'];
            }

            // Check if this is an error test
            if (testCase.containsKey('code')) {
              // Expect an error
              try {
                final jsonata = Jsonata(expr);
                jsonata.evaluate(inputData);
                fail('Expected error with code ${testCase['code']}');
              } on JsonataException {
                // Expected
              }
              return;
            }

            // Normal test - expect a result
            try {
              final jsonata = Jsonata(expr);

              // Apply bindings
              if (testCase.containsKey('bindings')) {
                final bindings = testCase['bindings'] as Map<String, dynamic>;
                for (final entry in bindings.entries) {
                  jsonata.bind(entry.key, entry.value);
                }
              }

              final result = jsonata.evaluate(inputData);
              final expected = testCase['result'];

              expect(result, equals(expected),
                  reason: 'Expression: $expr\nInput: $inputData');
            } on JsonataException catch (e) {
              fail('Unexpected error: $e\nExpression: $expr');
            }
          });
        }
      }
    });
  }
}

