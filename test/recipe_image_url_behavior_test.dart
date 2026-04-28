import 'dart:io';

import 'package:chefbase_app/pages/recipes_page.dart';
import 'package:chefbase_app/pages/recipe_detail_page.dart';
import 'package:chefbase_app/services/recipe_image_source.dart';
import 'package:chefbase_app/services/recipe_store.dart';
import 'package:flutter/material.dart';
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

  test('imported recipe with imageUrl persists it', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp(
      'chefbase_imported_recipe_image_url_',
    );
    RecipeStore.configureTestStorageDirectory(tempDir);

    try {
      await RecipeStore.saveRecipes([
        {
          'title': 'Imported recipe',
          'description': 'Imported from URL',
          'notes': '',
          'imageUrl': 'https://example.com/imported.jpg',
          'imageData': '',
          'ingredients': const [
            {'name': 'farine'},
          ],
          'instructions': const ['Cuire.'],
          'prepTime': '-',
          'cookTime': '-',
          'servings': 1,
          'categories': const ['plat'],
          'isFavorite': false,
          'createdAt': 33,
        },
      ]);

      final loaded = await RecipeStore.loadRecipes();
      final stored = loaded.singleWhere((recipe) => recipe['createdAt'] == 33);
      expect(stored['imageUrl'], 'https://example.com/imported.jpg');
      expect(stored['imageData'], isEmpty);
    } finally {
      RecipeStore.configureTestStorageDirectory(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  testWidgets('detail page displays remote imageUrl when present',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RecipeDetailPage(
          title: 'Remote image recipe',
          description: 'Desc',
          imageUrl: 'https://example.com/remote.jpg',
          imageData: 'base64-data',
          ingredients: [],
          instructions: ['Step'],
          prepTime: '-',
          cookTime: '-',
          servings: 2,
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
    expect((image.image as NetworkImage).url, 'https://example.com/remote.jpg');
  });

  testWidgets('recipe list thumbnail displays remote imageUrl', (tester) async {
    const imageUrl = 'https://example.com/list-remote.jpg';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecipeListThumbnail(
            imageUrl: imageUrl,
            imageData: 'base64-data',
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byKey(const ValueKey(imageUrl)));
    expect(image.image, isA<NetworkImage>());
    expect((image.image as NetworkImage).url, imageUrl);
  });
}
