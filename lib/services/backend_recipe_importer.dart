import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'imported_recipe_data.dart';

// Set this for production builds with:
// flutter build ios --dart-define=CHEFBASE_BACKEND_URL=https://your-service.onrender.com
const String defaultBackendRecipeImporterBaseUrl = String.fromEnvironment(
  'CHEFBASE_BACKEND_URL',
  defaultValue: 'https://your-chefbase-backend.onrender.com',
);

class BackendRecipeImporter {
  BackendRecipeImporter({
    String baseUrl = defaultBackendRecipeImporterBaseUrl,
  }) : _baseUri = Uri.parse(baseUrl) {
    debugPrint('BackendRecipeImporter backend URL: $_baseUri');
  }

  final Uri _baseUri;

  static const Duration _requestTimeout = Duration(seconds: 10);

  Future<ImportedRecipeData> importFromUrl(String rawUrl) async {
    final recipeUri = Uri.tryParse(rawUrl.trim());
    if (recipeUri == null ||
        !recipeUri.hasScheme ||
        recipeUri.host.isEmpty ||
        (recipeUri.scheme != 'http' && recipeUri.scheme != 'https')) {
      throw const FormatException('URL invalide');
    }

    final responseJson = await _postImportRecipe(recipeUri.toString());
    final imported = _mapRecipeJson(responseJson);
    if (!imported.hasAnyValue) {
      throw const FormatException('Backend recipe response is empty.');
    }

    return imported;
  }

  Future<Map<String, dynamic>> _postImportRecipe(String url) async {
    final endpoint = _baseUri.resolve('/import-recipe');
    final client = HttpClient();
    client.connectionTimeout = _requestTimeout;

    try {
      final request = await client.postUrl(endpoint).timeout(_requestTimeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode({'url': url}));

      final response = await request.close().timeout(_requestTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'BackendRecipeImporter failed HTTP ${response.statusCode}: $body',
        );
        throw HttpException(
          'Backend import failed with HTTP ${response.statusCode}: $body',
          uri: endpoint,
        );
      }

      final Object? decoded;
      try {
        decoded = jsonDecode(body);
      } on FormatException catch (error) {
        debugPrint(
          'BackendRecipeImporter invalid JSON HTTP ${response.statusCode}: '
          '$body',
        );
        throw FormatException(
          'Backend response JSON invalide: ${error.message}',
        );
      }
      if (decoded is! Map) {
        debugPrint(
          'BackendRecipeImporter unexpected JSON HTTP ${response.statusCode}: '
          '$body',
        );
        throw const FormatException('Backend response must be a JSON object.');
      }

      return Map<String, dynamic>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }

  ImportedRecipeData _mapRecipeJson(Map<String, dynamic> data) {
    return ImportedRecipeData(
      title: _stringOrNull(data['title']),
      description: _stringOrNull(data['description']),
      ingredients: _ingredientMaps(data['ingredients']),
      instructions: _instructionList(data['instructions'] ?? data['steps']),
      prepTime: _stringOrNull(data['prepTime'] ?? data['prep_time']),
      cookTime: _stringOrNull(data['cookTime'] ?? data['cook_time']),
      servings: _servingsOrNull(data['servings'] ?? data['yield']),
      imageUrl: _stringOrNull(data['imageUrl'] ?? data['image_url']),
      notes: _stringOrNull(data['notes']),
      categories: _stringList(data['categories']),
    );
  }

  List<Map<String, dynamic>> _ingredientMaps(dynamic value) {
    if (value is! List) return const [];

    return value
        .map((entry) {
          if (entry is Map) {
            return _ingredientFromMap(entry);
          }

          final text = _stringOrNull(entry);
          if (text == null) return null;

          return _ingredientFromString(text);
        })
        .whereType<Map<String, dynamic>>()
        .where((ingredient) => ingredient['name'].toString().isNotEmpty)
        .toList();
  }

  Map<String, dynamic>? _ingredientFromMap(Map<dynamic, dynamic> entry) {
    final name = _stringOrNull(entry['name']);
    if (name == null) return null;

    final ingredient = <String, dynamic>{
      'name': name,
    };

    final quantity = _numberOrNull(entry['quantity']);
    if (quantity != null) {
      ingredient['quantity'] = quantity;
    }

    final unit = _stringOrNull(entry['unit']);
    if (unit != null) {
      ingredient['unit'] = unit;
    }

    return ingredient;
  }

  Map<String, dynamic>? _ingredientFromString(String value) {
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

  List<String> _instructionList(dynamic value) {
    return _stringList(value)
        .where((instruction) => !_isStandaloneStepLabel(instruction))
        .toList();
  }

  bool _isStandaloneStepLabel(String value) {
    return RegExp(
      r'^(?:é|e)tape\s*\d+\s*[:.\-]?$',
      caseSensitive: false,
    ).hasMatch(value);
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const [];

    return value
        .map((entry) => _stringOrNull(entry))
        .whereType<String>()
        .toList();
  }

  String? _stringOrNull(dynamic value) {
    if (value == null) return null;

    final trimmed = value.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _servingsOrNull(dynamic value) {
    int? servings;
    if (value is int) {
      servings = value;
    } else if (value is num) {
      servings = value.toInt();
    } else {
      final text = _stringOrNull(value);
      if (text == null) return null;

      if (RegExp(r'^\d+$').hasMatch(text)) {
        servings = int.tryParse(text);
      } else if (RegExp(
        r'\b(?:serves?|portions?|personnes?|convives?|yield)\b',
        caseSensitive: false,
      ).hasMatch(text)) {
        final match = RegExp(r'\d+').firstMatch(text);
        servings = match == null ? null : int.tryParse(match.group(0)!);
      }
    }

    if (servings == null || servings < 1 || servings > 50) {
      return null;
    }
    return servings;
  }

  num? _numberOrNull(dynamic value) {
    if (value is num) return value;

    final text = _stringOrNull(value);
    return text == null ? null : double.tryParse(text.replaceAll(',', '.'));
  }
}
