import 'dart:convert';

import 'imported_recipe_data.dart';
import 'recipe_html_fallback_parser.dart';

typedef RecipeAIMockResponseBuilder = Future<String> Function({
  required Uri url,
  required String htmlContent,
});

class RecipeAIImporter {
  RecipeAIImporter({
    RecipeAIMockResponseBuilder? requestRecipeJson,
    RecipeHtmlFallbackParser? seedParser,
  }) : _requestRecipeJson = requestRecipeJson ??
            _buildDefaultRequestRecipeJson(
              seedParser ?? const RecipeHtmlFallbackParser(),
            );

  final RecipeAIMockResponseBuilder _requestRecipeJson;

  static RecipeAIMockResponseBuilder _buildDefaultRequestRecipeJson(
    RecipeHtmlFallbackParser seedParser,
  ) {
    return ({
      required Uri url,
      required String htmlContent,
    }) {
      return _mockRecipeJsonResponse(
        url: url,
        htmlContent: htmlContent,
        seedParser: seedParser,
      );
    };
  }

  Future<ImportedRecipeData> importRecipe({
    required Uri url,
    required String htmlContent,
  }) async {
    final rawResponse = await _requestRecipeJson(
      url: url,
      htmlContent: htmlContent,
    );

    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map) {
      throw const FormatException('AI response must be a JSON object.');
    }

    final data = Map<String, dynamic>.from(decoded);
    return ImportedRecipeData(
      title: _stringOrNull(data['title']),
      description: _stringOrNull(data['description']),
      ingredients: _ingredientMaps(data['ingredients']),
      instructions: _stringList(data['steps']),
      servings: _intOrNull(data['servings']),
    );
  }

  static Future<String> _mockRecipeJsonResponse({
    required Uri url,
    required String htmlContent,
    required RecipeHtmlFallbackParser seedParser,
  }) async {
    final parsed = seedParser.parse(htmlContent, url);

    final response = <String, dynamic>{
      'title': parsed.title,
      'description': parsed.description,
      'ingredients': parsed.ingredients
          .map((ingredient) => _ingredientToPromptLine(ingredient))
          .whereType<String>()
          .toList(),
      'steps': parsed.instructions,
      'servings': parsed.servings,
    };

    return jsonEncode(response);
  }

  List<Map<String, dynamic>> _ingredientMaps(dynamic value) {
    if (value is! List) return const [];

    return value
        .map((entry) => _ingredientFromString(entry?.toString()))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Map<String, dynamic>? _ingredientFromString(String? value) {
    final cleaned = _stringOrNull(value);
    if (cleaned == null) return null;

    final match = RegExp(
      r'^\s*(\d+(?:[.,]\d+)?)?\s*([a-zA-Zéèêëàâäîïôöùûüçµ%]+)?\s+(.+)$',
    ).firstMatch(cleaned);

    if (match == null) {
      return {
        'name': cleaned,
        'quantity': 0,
        'unit': '',
      };
    }

    return {
      'name': (match.group(3) ?? cleaned).trim(),
      'quantity':
          double.tryParse((match.group(1) ?? '').replaceAll(',', '.')) ?? 0,
      'unit': (match.group(2) ?? '').trim(),
    };
  }

  static String? _ingredientToPromptLine(Map<String, dynamic> ingredient) {
    final name = _stringOrNull(ingredient['name']?.toString());
    if (name == null) return null;

    final quantity = ingredient['quantity'];
    final unit = _stringOrNull(ingredient['unit']?.toString()) ?? '';
    final quantityText = quantity is num && quantity > 0 ? '$quantity ' : '';
    final unitText = unit.isNotEmpty ? '$unit ' : '';
    return '$quantityText$unitText$name'.trim();
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((entry) => _stringOrNull(entry?.toString()))
        .whereType<String>()
        .toList();
  }

  static String? _stringOrNull(String? value) {
    if (value == null) return null;
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  int? _intOrNull(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}
