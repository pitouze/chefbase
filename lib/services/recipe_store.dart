import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecipeStore {
  static const String storageKey = 'chefbase_recipes_v1';
  static const String storageFileName = 'chefbase_recipes_v2.json';
  static const String lastOpenedAtKey = 'lastOpenedAt';

  static Directory? _testStorageDirectory;
  static Future<void> _writeQueue = Future<void>.value();

  static String normalizeForSearch(String value) {
    final lower = value.toLowerCase().trim();
    const accents = {
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'å': 'a',
      'ç': 'c',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ñ': 'n',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ý': 'y',
      'ÿ': 'y',
      'œ': 'oe',
      'æ': 'ae',
      '’': "'",
    };

    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(accents[char] ?? char);
    }
    return buffer.toString();
  }

  @visibleForTesting
  static void configureTestStorageDirectory(Directory? directory) {
    _testStorageDirectory = directory;
  }

  static Future<List<Map<String, dynamic>>> loadRecipes() async {
    try {
      final file = await _storageFile();
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final loaded = _decodeRecipes(jsonString);
        if (loaded != null) {
          return await _finalizeLoadedRecipes(loaded);
        }
      }

      final legacyRecipes = await _loadLegacyRecipes();
      if (legacyRecipes != null) {
        final finalized = await _finalizeLoadedRecipes(legacyRecipes);
        await _clearLegacyStorage();
        return finalized;
      }
    } catch (error, stackTrace) {
      debugPrint('RecipeStore: load failed $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    return _defaultRecipesWithBestEffortSave();
  }

  static Future<void> saveRecipes(List<Map<String, dynamic>> recipes) async {
    final normalizedRecipes = _sanitizeRecipes(recipes);
    final json = jsonEncode(normalizedRecipes);

    _writeQueue = _writeQueue.then((_) async {
      final file = await _storageFile();
      final tempFile = File('${file.path}.tmp');

      await file.parent.create(recursive: true);
      await tempFile.writeAsString(json, flush: true);

      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(file.path);

      debugPrint(
        'RecipeStore: saved recipes count=${normalizedRecipes.length} '
        'jsonLength=${json.length}',
      );
    });

    try {
      await _writeQueue;
      await _clearLegacyStorage();
    } catch (error, stackTrace) {
      debugPrint('RecipeStore: save failed $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> markRecipeOpened(
    Map<String, dynamic> recipe,
  ) async {
    final recipes = await loadRecipes();
    final index = _findRecipeIndex(recipes, recipe);
    if (index == -1) return recipes;

    recipes[index][lastOpenedAtKey] = DateTime.now().millisecondsSinceEpoch;
    await saveRecipes(recipes);
    return recipes;
  }

  static List<Map<String, dynamic>> latestOpenedRecipes(
    List<Map<String, dynamic>> recipes, {
    int limit = 5,
  }) {
    final opened = recipes.where((recipe) {
      final value = recipe[lastOpenedAtKey];
      return value is num && value > 0;
    }).toList();

    opened.sort((a, b) {
      final openedAtA = (a[lastOpenedAtKey] as num?)?.toInt() ?? 0;
      final openedAtB = (b[lastOpenedAtKey] as num?)?.toInt() ?? 0;
      return openedAtB.compareTo(openedAtA);
    });

    return opened.take(limit).toList();
  }

  static int _findRecipeIndex(
    List<Map<String, dynamic>> recipes,
    Map<String, dynamic> recipe,
  ) {
    final createdAt = recipe['createdAt'];
    final title = normalizeForSearch(recipe['title']?.toString() ?? '');

    return recipes.indexWhere((candidate) {
      final candidateTitle = normalizeForSearch(
        candidate['title']?.toString() ?? '',
      );
      return candidateTitle == title && candidate['createdAt'] == createdAt;
    });
  }

  static Future<List<Map<String, dynamic>>> _finalizeLoadedRecipes(
    List<Map<String, dynamic>> recipes,
  ) async {
    if (recipes.isEmpty) {
      return _defaultRecipesWithBestEffortSave();
    }

    final updatedSaved = _migrateRecipeDefaults(recipes);
    final migrated = _mergeMissingDefaults(updatedSaved);

    if (!_recipesEqual(recipes, migrated)) {
      try {
        await saveRecipes(migrated);
      } catch (_) {
        // Returning in-memory data is preferable to failing startup reads.
      }
    }

    return migrated;
  }

  static List<Map<String, dynamic>>? _decodeRecipes(String jsonString) {
    if (jsonString.trim().isEmpty) return null;

    final decoded = jsonDecode(jsonString);
    if (decoded is! List) return null;

    return decoded
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  static Future<List<Map<String, dynamic>>?> _loadLegacyRecipes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(storageKey);
      if (jsonString == null || jsonString.isEmpty) {
        return null;
      }
      return _decodeRecipes(jsonString);
    } catch (error, stackTrace) {
      debugPrint('RecipeStore: legacy load failed $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  static Future<void> _clearLegacyStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(storageKey)) {
        await prefs.remove(storageKey);
      }
    } catch (_) {
      // Ignore cleanup failures. The file is now the source of truth.
    }
  }

  static Future<List<Map<String, dynamic>>>
      _defaultRecipesWithBestEffortSave() async {
    final defaults = defaultRecipes();

    try {
      await saveRecipes(defaults);
    } catch (_) {
      // Keep launch resilient even if initial persistence fails.
    }

    return defaults;
  }

  static Future<File> _storageFile() async {
    final directory =
        _testStorageDirectory ?? await getApplicationSupportDirectory();
    return File('${directory.path}/$storageFileName');
  }

  static List<Map<String, dynamic>> _sanitizeRecipes(
    List<Map<String, dynamic>> recipes,
  ) {
    return recipes
        .map((recipe) => Map<String, dynamic>.from(recipe))
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _mergeMissingDefaults(
    List<Map<String, dynamic>> saved,
  ) {
    final existingTitles = saved
        .map((recipe) => normalizeForSearch(recipe['title']?.toString() ?? ''))
        .toSet();

    final missing = defaultRecipes().where((recipe) {
      final title = normalizeForSearch(recipe['title']?.toString() ?? '');
      return !existingTitles.contains(title);
    }).toList();

    if (missing.isEmpty) return saved;

    return [
      ...missing,
      ...saved,
    ];
  }

  static bool _recipesEqual(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    return jsonEncode(a) == jsonEncode(b);
  }

  static List<Map<String, dynamic>> _migrateRecipeDefaults(
    List<Map<String, dynamic>> saved,
  ) {
    var changed = false;
    const structuredTimerDefaults = {
      'puree de pommes de terre': [
        {'label': 'Cuisson 25 min', 'durationSeconds': 1500},
      ],
      'poulet roti': [
        {'label': 'Cuisson 1 h 15', 'durationSeconds': 4500},
        {'label': 'Repos 15 min', 'durationSeconds': 900},
      ],
      'tarte citron': [
        {'label': '20 min', 'durationSeconds': 1200},
        {'label': '10 min', 'durationSeconds': 600},
      ],
      'risotto aux champignons': [
        {'label': 'Cuisson 18 min', 'durationSeconds': 1080},
        {'label': 'Repos 2 min', 'durationSeconds': 120},
      ],
      'saumon mi-cuit': [
        {'label': 'Four 12 min', 'durationSeconds': 720},
        {'label': 'Repos 3 min', 'durationSeconds': 180},
      ],
    };
    const legacySingleStepTimers = {
      'puree de pommes de terre': {'label': 'Purée', 'durationSeconds': 1500},
      'poulet roti': {'label': 'Poulet rôti', 'durationSeconds': 4500},
      'tarte citron': {'label': 'Tarte citron', 'durationSeconds': 2100},
      'risotto aux champignons': {'label': 'Risotto', 'durationSeconds': 1500},
      'saumon mi-cuit': {'label': 'Saumon', 'durationSeconds': 1080},
    };
    const outdatedStructuredTimerDefaults = {
      'poulet roti': [
        {'label': 'Cuisson 45 min', 'durationSeconds': 2700},
        {'label': 'Repos 15 min', 'durationSeconds': 900},
      ],
    };

    final migrated = saved.map((recipe) {
      final title = normalizeForSearch(recipe['title']?.toString() ?? '');
      final targetTimerDefaults = structuredTimerDefaults[title];
      final legacyTimer = legacySingleStepTimers[title];
      final outdatedTimerDefaults = outdatedStructuredTimerDefaults[title];

      if (targetTimerDefaults == null || legacyTimer == null) {
        return recipe;
      }

      final timerDefaults = List<Map<String, dynamic>>.from(
        recipe['timerDefaults'] as List? ?? [],
      );

      final shouldReplaceTimerDefaults = timerDefaults.length == 1 &&
          (timerDefaults.first['label']?.toString().trim() ?? '') ==
              legacyTimer['label'] &&
          (timerDefaults.first['durationSeconds'] as num?)?.toInt() ==
              legacyTimer['durationSeconds'];
      final shouldReplaceOutdatedStructuredDefaults =
          outdatedTimerDefaults != null &&
              jsonEncode(timerDefaults) == jsonEncode(outdatedTimerDefaults);

      if (!shouldReplaceTimerDefaults &&
          !shouldReplaceOutdatedStructuredDefaults) {
        return recipe;
      }

      changed = true;
      return {
        ...recipe,
        'timerDefaults': targetTimerDefaults,
      };
    }).toList();

    return changed ? migrated : saved;
  }

  static List<Map<String, dynamic>> defaultRecipes() {
    return [
      {
        'title': 'Purée de pommes de terre',
        'description': 'Une purée maison bien lisse, beurrée et onctueuse.',
        'notes': 'Passer au tamis pour une texture plus fine.',
        'imageUrl': '',
        'imageData': '',
        'ingredients': [
          {'name': 'pommes de terre', 'quantity': 1000.0, 'unit': 'g'},
          {'name': 'beurre', 'quantity': 120.0, 'unit': 'g'},
          {'name': 'lait', 'quantity': 200.0, 'unit': 'ml'},
          {'name': 'sel', 'quantity': 8.0, 'unit': 'g'},
        ],
        'instructions': [
          'Éplucher les pommes de terre',
          'Cuire dans l’eau salée',
          'Égoutter',
          'Écraser au presse-purée',
          'Ajouter beurre et lait chaud',
          'Assaisonner',
        ],
        'prepTime': '20 min',
        'cookTime': '25 min',
        'timerDefaults': [
          {'label': 'Cuisson 25 min', 'durationSeconds': 1500},
        ],
        'servings': 4,
        'categories': ['accompagnement', 'pomme de terre'],
        'isFavorite': true,
        'createdAt': 30,
      },
      {
        'title': 'Poulet rôti',
        'description': 'Poulet rôti croustillant avec chair moelleuse.',
        'notes': 'Arroser souvent et laisser reposer 15 minutes.',
        'imageUrl': '',
        'imageData': '',
        'ingredients': [
          {'name': 'poulet', 'quantity': 1.0, 'unit': 'pièce'},
          {'name': 'beurre', 'quantity': 80.0, 'unit': 'g'},
          {'name': 'thym', 'quantity': 4.0, 'unit': 'brins'},
          {'name': 'sel', 'quantity': 10.0, 'unit': 'g'},
          {'name': 'poivre', 'quantity': 3.0, 'unit': 'g'},
        ],
        'instructions': [
          'Préchauffer le four à 180°C',
          'Assaisonner le poulet',
          'Ajouter beurre et thym',
          'Enfourner',
          'Arroser régulièrement',
          'Cuire 1 h 15',
        ],
        'prepTime': '15 min',
        'cookTime': '1 h 15',
        'timerDefaults': [
          {'label': 'Cuisson 1 h 15', 'durationSeconds': 4500},
          {'label': 'Repos 15 min', 'durationSeconds': 900},
        ],
        'servings': 4,
        'categories': ['plat', 'volaille'],
        'isFavorite': false,
        'createdAt': 29,
      },
      {
        'title': 'Carottes glacées',
        'description': 'Carottes fondantes et légèrement sucrées.',
        'notes': '',
        'imageUrl': '',
        'imageData': '',
        'ingredients': [
          {'name': 'carottes', 'quantity': 600.0, 'unit': 'g'},
          {'name': 'beurre', 'quantity': 40.0, 'unit': 'g'},
          {'name': 'sucre', 'quantity': 12.0, 'unit': 'g'},
          {'name': 'sel', 'quantity': 4.0, 'unit': 'g'},
        ],
        'instructions': [
          'Éplucher les carottes',
          'Couper en bâtonnets',
          'Cuire avec beurre et sucre',
          'Ajouter un peu d’eau',
          'Laisser glacer',
        ],
        'prepTime': '10 min',
        'cookTime': '20 min',
        'timerDefaults': [
          {'label': 'Carottes', 'durationSeconds': 1200},
        ],
        'servings': 3,
        'categories': ['légumes', 'accompagnement'],
        'isFavorite': true,
        'createdAt': 28,
      },
      {
        'title': 'Tarte citron',
        'description': 'Dessert frais avec crème citron et pâte croustillante.',
        'notes': 'Refroidir complètement avant de détailler.',
        'imageUrl': '',
        'imageData': '',
        'ingredients': [
          {'name': 'citron', 'quantity': 4.0, 'unit': 'pièces'},
          {'name': 'sucre', 'quantity': 180.0, 'unit': 'g'},
          {'name': 'beurre', 'quantity': 120.0, 'unit': 'g'},
        ],
        'instructions': [
          'Préparer la pâte',
          'Cuire à blanc',
          'Réaliser l’appareil citron',
          'Garnir et finir',
        ],
        'prepTime': '30 min',
        'cookTime': '35 min',
        'timerDefaults': [
          {'label': '20 min', 'durationSeconds': 1200},
          {'label': '10 min', 'durationSeconds': 600},
        ],
        'servings': 6,
        'categories': ['dessert', 'tarte'],
        'isFavorite': false,
        'createdAt': 27,
      },
      {
        'title': 'Risotto aux champignons',
        'description': 'Riz crémeux, champignons sautés et parmesan.',
        'notes': 'Ajouter le bouillon chaud petit à petit.',
        'imageUrl': '',
        'imageData': '',
        'ingredients': [
          {'name': 'riz arborio', 'quantity': 320.0, 'unit': 'g'},
          {'name': 'champignons', 'quantity': 400.0, 'unit': 'g'},
          {'name': 'bouillon', 'quantity': 900.0, 'unit': 'ml'},
          {'name': 'parmesan', 'quantity': 80.0, 'unit': 'g'},
        ],
        'instructions': [
          'Suer l’oignon',
          'Nacrer le riz',
          'Mouiller au bouillon chaud',
          'Ajouter les champignons sautés',
          'Lier au parmesan',
        ],
        'prepTime': '15 min',
        'cookTime': '25 min',
        'timerDefaults': [
          {'label': 'Cuisson 18 min', 'durationSeconds': 1080},
          {'label': 'Repos 2 min', 'durationSeconds': 120},
        ],
        'servings': 4,
        'categories': ['plat', 'riz', 'légumes'],
        'isFavorite': false,
        'createdAt': 26,
      },
      {
        'title': 'Saumon mi-cuit',
        'description': 'Saumon fondant, cuisson douce et assaisonnement net.',
        'notes': 'Sortir du four quand le centre reste nacré.',
        'imageUrl': '',
        'imageData': '',
        'ingredients': [
          {'name': 'saumon', 'quantity': 4.0, 'unit': 'pavés'},
          {'name': 'huile d’olive', 'quantity': 30.0, 'unit': 'ml'},
          {'name': 'citron', 'quantity': 1.0, 'unit': 'pièce'},
          {'name': 'sel', 'quantity': 5.0, 'unit': 'g'},
        ],
        'instructions': [
          'Assaisonner les pavés',
          'Huiler légèrement',
          'Cuire au four à 90°C',
          'Finir avec citron et herbes',
        ],
        'prepTime': '10 min',
        'cookTime': '18 min',
        'timerDefaults': [
          {'label': 'Four 12 min', 'durationSeconds': 720},
          {'label': 'Repos 3 min', 'durationSeconds': 180},
        ],
        'servings': 4,
        'categories': ['plat', 'poisson'],
        'isFavorite': false,
        'createdAt': 25,
      },
      {
        'title': 'Vinaigrette classique',
        'description': 'Base rapide pour salade et crudités.',
        'notes': 'Respecter 1 volume de vinaigre pour 3 volumes d’huile.',
        'imageUrl': '',
        'imageData': '',
        'ingredients': [
          {'name': 'moutarde', 'quantity': 15.0, 'unit': 'g'},
          {'name': 'vinaigre', 'quantity': 30.0, 'unit': 'ml'},
          {'name': 'huile', 'quantity': 90.0, 'unit': 'ml'},
          {'name': 'sel', 'quantity': 2.0, 'unit': 'g'},
        ],
        'instructions': [
          'Mélanger moutarde, vinaigre et sel',
          'Monter progressivement à l’huile',
          'Rectifier l’assaisonnement',
        ],
        'prepTime': '5 min',
        'cookTime': '-',
        'servings': 4,
        'categories': ['sauce', 'base'],
        'isFavorite': true,
        'createdAt': 24,
      },
      {
        'title': 'Pâte brisée',
        'description': 'Pâte simple pour tartes salées et sucrées.',
        'notes': 'Ne pas trop travailler la pâte après ajout de l’eau.',
        'imageUrl': '',
        'imageData': '',
        'ingredients': [
          {'name': 'farine', 'quantity': 250.0, 'unit': 'g'},
          {'name': 'beurre', 'quantity': 125.0, 'unit': 'g'},
          {'name': 'eau froide', 'quantity': 60.0, 'unit': 'ml'},
          {'name': 'sel', 'quantity': 4.0, 'unit': 'g'},
        ],
        'instructions': [
          'Sabler farine et beurre',
          'Ajouter sel et eau froide',
          'Former une boule',
          'Repos au froid 30 min',
        ],
        'prepTime': '15 min',
        'cookTime': '30 min repos',
        'timerDefaults': [
          {'label': 'Repos 30 min', 'durationSeconds': 1800},
        ],
        'servings': 1,
        'categories': ['base', 'pâte'],
        'isFavorite': false,
        'createdAt': 23,
      },
    ];
  }
}
