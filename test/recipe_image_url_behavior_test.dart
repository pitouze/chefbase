import 'dart:io';

import 'package:chefbase_app/services/recipe_image_source.dart';
import 'package:chefbase_app/services/recipe_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('valid http imageUrl wins over base64', () {
    expect(
      resolveRecipeImageSource(
        ' https://example.com/image.jpg ',
        'base64-data',
      ),
      RecipeImageSource.network,
    );
  });

  test('base64 is used only when imageUrl is empty', () {
    expect(
      resolveRecipeImageSource('', 'base64-data'),
      RecipeImageSource.memory,
    );
    expect(
      resolveRecipeImageSource('not-a-valid-url', 'base64-data'),
      RecipeImageSource.placeholder,
    );
  });

  test('recipe store preserves exact imageUrl value', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp(
      'chefbase_recipe_image_url_store_',
    );
    RecipeStore.configureTestStorageDirectory(tempDir);

    try {
      await RecipeStore.saveRecipes([
        {
          'title': 'Stored raw URL',
          'description': 'Desc',
          'notes': '',
          'imageUrl': ' https://example.com/saved.jpg ',
          'imageData': '',
          'ingredients': const [],
          'instructions': const ['Step'],
          'prepTime': '-',
          'cookTime': '-',
          'servings': 2,
          'categories': const ['plat'],
          'isFavorite': false,
          'createdAt': 11,
        },
      ]);

      final loaded = await RecipeStore.loadRecipes();
      final stored = loaded.singleWhere((recipe) => recipe['createdAt'] == 11);
      expect(stored['imageUrl'], ' https://example.com/saved.jpg ');
    } finally {
      RecipeStore.configureTestStorageDirectory(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}
