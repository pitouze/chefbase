import 'dart:convert';
import 'dart:io';

import 'package:chefbase_app/services/backend_recipe_importer.dart';
import 'package:chefbase_app/services/imported_recipe_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps structured backend ingredients without reparsing them', () async {
    final result = await _withBackendResponse(
      {
        'title': 'Pain simple',
        'ingredients': [
          {'name': 'farine', 'quantity': 100, 'unit': 'g'},
          {'name': 'sel', 'unit': 'pincée'},
          {'name': 'eau', 'quantity': '12,5', 'unit': 'cl'},
        ],
        'instructions': [
          'Étape 1',
          'Mélanger les ingrédients',
          'Etape 2:',
          'Cuire',
        ],
        'servings': 4,
      },
    );

    expect(result.ingredients, [
      {'name': 'farine', 'quantity': 100, 'unit': 'g'},
      {'name': 'sel', 'unit': 'pincée'},
      {'name': 'eau', 'quantity': 12.5, 'unit': 'cl'},
    ]);
    expect(result.instructions, ['Mélanger les ingrédients', 'Cuire']);
    expect(result.servings, 4);
  });

  test('keeps string ingredient fallback parsing', () async {
    final result = await _withBackendResponse(
      {
        'title': 'Compote',
        'ingredients': ['2 pommes', '120 g sucre', 'cannelle'],
        'steps': ['Couper', 'Cuire'],
      },
    );

    expect(result.ingredients, [
      {'name': 'pommes', 'quantity': 2.0, 'unit': ''},
      {'name': 'sucre', 'quantity': 120.0, 'unit': 'g'},
      {'name': 'cannelle', 'quantity': 0, 'unit': ''},
    ]);
  });

  test('ignores implausible backend serving counts from page chrome', () async {
    final result = await _withBackendResponse(
      {
        'title': '100 partenaires',
        'ingredients': [
          {'name': 'farine', 'quantity': 100, 'unit': 'g'},
        ],
        'instructions': ['Mélanger'],
        'servings': 100,
      },
    );

    expect(result.servings, isNull);
  });
}

Future<ImportedRecipeData> _withBackendResponse(
  Map<String, dynamic> responseJson,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

  try {
    final requestFuture = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/import-recipe');

      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(responseJson));
      await request.response.close();
    });

    final importer = BackendRecipeImporter(
      baseUrl: 'http://${server.address.host}:${server.port}',
    );
    final result = await importer.importFromUrl('https://example.com/recipe');
    await requestFuture;
    return result;
  } finally {
    await server.close(force: true);
  }
}
