import 'lib/jsonata.dart';

void main() {
  // Test cases
  print('Test 1: str.$uppercase()');
  var jsonata = Jsonata(r'"hello".$uppercase()');
  print('  Result: ' + jsonata.evaluate(null).toString());
  
  print('Test 2: str.$substringBefore(" ")');
  jsonata = Jsonata(r'"BOWLER HAT".$substringBefore(" ")');
  print('  Result: ' + jsonata.evaluate(null).toString());
  
  print('Test 3: origin.$lowercase(name)');
  jsonata = Jsonata(r'origin.$lowercase(name)');
  print('  Result: ' + jsonata.evaluate({"origin": {"name": "TEST"}}).toString());
  
  print('Test 4: simple $lowercase(name)');
  jsonata = Jsonata(r'$lowercase(name)');
  print('  Result: ' + jsonata.evaluate({"name": "TEST"}).toString());
}
