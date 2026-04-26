import 'dart:convert';
import 'dart:io';

import 'package:chefbase_app/services/recipe_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('chefbase_recipe_store_');
    RecipeStore.configureTestStorageDirectory(tempDir);
  });

  tearDown(() async {
    RecipeStore.configureTestStorageDirectory(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('persists add edit delete favorite and latest opened in file storage',
      () async {
    final recipes = RecipeStore.defaultRecipes().map((recipe) {
      return Map<String, dynamic>.from(recipe);
    }).toList();

    final createdAt = DateTime(2026, 4, 24).millisecondsSinceEpoch;
    recipes.add({
      'title': 'Salade test',
      'description': 'Fraîche',
      'notes': 'Ajouter au dernier moment',
      'imageUrl': 'https://example.com/salade.jpg',
      'imageData': '',
      'ingredients': [
        {'name': 'salade', 'quantity': 1.0, 'unit': 'pièce'},
      ],
      'instructions': ['Mélanger'],
      'prepTime': '10 min',
      'cookTime': '-',
      'servings': 2,
      'categories': ['entrée'],
      'isFavorite': false,
      'createdAt': createdAt,
    });

    await RecipeStore.saveRecipes(recipes);

    var loaded = await RecipeStore.loadRecipes();
    final addedIndex =
        loaded.indexWhere((recipe) => recipe['createdAt'] == createdAt);
    expect(addedIndex, isNonNegative);
    expect(loaded[addedIndex]['imageUrl'], 'https://example.com/salade.jpg');

    loaded[addedIndex]['description'] = 'Fraîche et croquante';
    loaded[addedIndex]['isFavorite'] = true;
    await RecipeStore.saveRecipes(loaded);

    loaded = await RecipeStore.markRecipeOpened(loaded[addedIndex]);
    final latest = RecipeStore.latestOpenedRecipes(loaded, limit: 1);
    expect(latest, hasLength(1));
    expect(latest.single['createdAt'], createdAt);

    loaded.removeAt(addedIndex);
    await RecipeStore.saveRecipes(loaded);

    final afterDelete = await RecipeStore.loadRecipes();
    expect(
      afterDelete.where((recipe) => recipe['createdAt'] == createdAt),
      isEmpty,
    );

    final storageFile = File('${tempDir.path}/${RecipeStore.storageFileName}');
    expect(await storageFile.exists(), isTrue);
  });

  test('migrates legacy shared preferences recipes into file storage',
      () async {
    final legacyRecipes = [
      {
        'title': 'Legacy',
        'description': 'Stored before migration',
        'notes': '',
        'imageUrl': 'https://example.com/legacy.jpg',
        'imageData': '',
        'ingredients': const [],
        'instructions': const ['Step'],
        'prepTime': '5 min',
        'cookTime': '10 min',
        'servings': 2,
        'categories': const ['plat'],
        'isFavorite': true,
        'createdAt': 999,
      },
    ];

    SharedPreferences.setMockInitialValues({
      RecipeStore.storageKey: jsonEncode(legacyRecipes),
    });

    final loaded = await RecipeStore.loadRecipes();
    expect(
      loaded.any((recipe) => recipe['createdAt'] == 999),
      isTrue,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(RecipeStore.storageKey), isFalse);

    final storageFile = File('${tempDir.path}/${RecipeStore.storageFileName}');
    final fileContent = await storageFile.readAsString();
    expect(fileContent, contains('legacy.jpg'));
  });
}
