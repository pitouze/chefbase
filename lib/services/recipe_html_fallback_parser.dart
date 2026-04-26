import 'dart:convert';

import 'imported_recipe_data.dart';

class RecipeHtmlFallbackParser {
  const RecipeHtmlFallbackParser();

  static final RegExp _ingredientGarbageCutPattern = RegExp(
    r'\b(?:top\s*\d*|meilleurs?|acheter|d[ée]tails?|ustensiles?|casseroles?|four|balance)\b[\s\S]*$',
    caseSensitive: false,
  );

  ImportedRecipeData parse(String html, Uri baseUri) {
    final jsonLd = _parseJsonLd(html, baseUri);
    final meta = _parseMeta(html, baseUri);
    final visibleText = _parseVisibleText(html);
    return jsonLd.merge(meta).merge(visibleText);
  }

  ImportedRecipeData _parseJsonLd(String html, Uri baseUri) {
    final matches = RegExp(
      "<script[^>]*type=[\"']application/ld\\+json[\"'][^>]*>([\\s\\S]*?)</script>",
      caseSensitive: false,
    ).allMatches(html);

    for (final match in matches) {
      final rawBlock = _cleanupScriptContent(match.group(1) ?? '');
      if (rawBlock.isEmpty) continue;

      try {
        final decoded = jsonDecode(rawBlock);
        final recipeNode = _findRecipeNode(decoded);
        if (recipeNode == null) continue;
        return _recipeFromJsonLd(recipeNode, baseUri);
      } catch (_) {
        // Ignore malformed JSON-LD blocks and continue scanning.
      }
    }

    return const ImportedRecipeData();
  }

  Map<String, dynamic>? _findRecipeNode(dynamic node) {
    final candidates = _collectRecipeNodes(node);
    if (candidates.isEmpty) return null;
    final scored = <_RecipeNodeScore>[];
    for (var i = 0; i < candidates.length; i += 1) {
      final score = _scoreRecipeNode(candidates[i], i);
      if (score.isValid) scored.add(score);
    }
    if (scored.isEmpty) return null;
    scored.sort((left, right) {
      final ingredientComparison =
          right.ingredientCount.compareTo(left.ingredientCount);
      if (ingredientComparison != 0) return ingredientComparison;
      final scoreComparison = right.score.compareTo(left.score);
      if (scoreComparison != 0) return scoreComparison;
      return left.index.compareTo(right.index);
    });
    return scored.first.recipe;
  }

  List<Map<String, dynamic>> _collectRecipeNodes(dynamic node) {
    if (node is List) {
      final found = <Map<String, dynamic>>[];
      for (final item in node) {
        found.addAll(_collectRecipeNodes(item));
      }
      return found;
    }

    if (node is! Map) return const [];
    final map = Map<String, dynamic>.from(node);

    if (map.containsKey('@graph')) {
      final graph = map['@graph'];
      final graphNodes = graph is List ? graph : [graph];
      final found = <Map<String, dynamic>>[];
      for (final entry in graphNodes) {
        found.addAll(_collectRecipeNodes(entry));
      }
      return found;
    }

    if (_isRecipeNode(map)) {
      return [map];
    }

    final found = <Map<String, dynamic>>[];
    for (final key in const ['itemListElement', 'mainEntity']) {
      found.addAll(_collectRecipeNodes(map[key]));
    }
    return found;
  }

  bool _isRecipeNode(Map<String, dynamic> node) {
    return _isRecipeType(node['@type']);
  }

  _RecipeNodeScore _scoreRecipeNode(Map<String, dynamic> recipe, int index) {
    final ingredientCount = _stringList(recipe['recipeIngredient']).length;
    final instructionCount =
        _parseInstructionNodes(recipe['recipeInstructions']).length;
    final hasIngredients = ingredientCount > 0;
    final hasInstructions = instructionCount > 0;
    final title = _stringValue(recipe['name'] ?? recipe['headline']) ?? '';
    final hasRejectedTitle = RegExp(
            r'\b(partenaires?|cookies?|rgpd|utiliser)\b',
            caseSensitive: false)
        .hasMatch(title);
    final score = (hasIngredients ? 1 : 0) +
        (hasInstructions ? 1 : 0) +
        (ingredientCount > 3 ? 1 : 0) +
        (instructionCount > 2 ? 1 : 0);

    return _RecipeNodeScore(
      recipe: recipe,
      index: index,
      score: score,
      ingredientCount: ingredientCount,
      isValid: !hasRejectedTitle && hasIngredients && hasInstructions,
    );
  }

  bool _isRecipeType(dynamic type) {
    if (type is String) {
      return type.toLowerCase() == 'recipe';
    }
    if (type is List) {
      return type.any(
        (entry) => entry.toString().toLowerCase() == 'recipe',
      );
    }
    return false;
  }

  ImportedRecipeData _recipeFromJsonLd(
    Map<String, dynamic> recipe,
    Uri baseUri,
  ) {
    final ingredientLines = _stringList(recipe['recipeIngredient']);
    final instructionLines =
        _parseInstructionNodes(recipe['recipeInstructions']);
    final yieldRaw = _stringValue(recipe['recipeYield']);
    final categoryLines = _stringList(recipe['recipeCategory']);
    final prepIso = _parseIso8601Duration(_stringValue(recipe['prepTime']));
    final cookIso = _parseIso8601Duration(_stringValue(recipe['cookTime']));
    final totalIso = _parseIso8601Duration(_stringValue(recipe['totalTime']));

    final prepTime =
        prepIso ?? (totalIso != null && cookIso == null ? totalIso : null);
    final cookTime = cookIso;

    return ImportedRecipeData(
      title: _stringValue(recipe['name']),
      description: _stringValue(recipe['description']),
      ingredients: ingredientLines
          .map(_ingredientFromLine)
          .whereType<Map<String, dynamic>>()
          .toList(),
      instructions: instructionLines,
      prepTime: prepTime,
      cookTime: cookTime,
      servings: _parseServings(yieldRaw),
      imageUrl: _resolveUrl(_imageValue(recipe['image']), baseUri),
      notes: _stringValue(recipe['keywords']),
      categories: categoryLines
          .expand((entry) => entry.split(RegExp(r'[,|/]')))
          .map(_cleanText)
          .whereType<String>()
          .toSet()
          .toList(),
    );
  }

  ImportedRecipeData _parseMeta(String html, Uri baseUri) {
    final title = _metaContent(html, 'property', 'og:title') ??
        _metaContent(html, 'name', 'twitter:title') ??
        _titleTag(html);
    final description = _metaContent(html, 'name', 'description') ??
        _metaContent(html, 'property', 'og:description');
    final imageUrl = _resolveUrl(
      _metaContent(html, 'property', 'og:image') ??
          _metaContent(html, 'name', 'twitter:image'),
      baseUri,
    );

    return ImportedRecipeData(
      title: _cleanText(title),
      description: _cleanText(description),
      imageUrl: imageUrl,
    );
  }

  ImportedRecipeData _parseVisibleText(String html) {
    final text = _htmlToText(html);
    if (text.isEmpty) {
      return const ImportedRecipeData();
    }

    final lines = text.split('\n').map(_cleanText).whereType<String>().toList();

    final title = lines.isEmpty ? null : lines.first;
    final description = lines.length > 1 ? lines[1] : null;
    final ingredientLines = _collectSectionLines(
      lines,
      headings: const ['ingredients', 'ingredient'],
      stopHeadings: const [
        'instructions',
        'preparation',
        'méthode',
        'etapes',
        'étapes'
      ],
    );
    final instructionLines = _collectSectionLines(
      lines,
      headings: const [
        'instructions',
        'preparation',
        'méthode',
        'etapes',
        'étapes'
      ],
      stopHeadings: const ['notes', 'nutrition', 'commentaires'],
    );

    return ImportedRecipeData(
      title: _looksLikeTitle(title) ? title : null,
      description:
          description != null && description.length > 24 ? description : null,
      ingredients: ingredientLines
          .map(_ingredientFromLine)
          .whereType<Map<String, dynamic>>()
          .toList(),
      instructions: instructionLines,
      prepTime: _extractTime(text, const ['prep time', 'préparation', 'prep']),
      cookTime: _extractTime(text, const ['cook time', 'cuisson', 'cook']),
      servings: _extractServings(text),
      notes: _extractNotes(lines),
      categories: _guessCategories([
        title,
        description,
        ...ingredientLines,
      ].whereType<String>().join(' ')),
    );
  }

  String _cleanupScriptContent(String value) {
    return value.replaceAll('&quot;', '"').replaceAll('&amp;', '&').trim();
  }

  String? _titleTag(String html) {
    final match = RegExp(
      r'<title[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    ).firstMatch(html);
    return match?.group(1);
  }

  String? _metaContent(String html, String attr, String value) {
    final attrPattern = RegExp.escape(attr);
    final valuePattern = RegExp.escape(value);
    final regex = RegExp(
      "<meta[^>]*$attrPattern=[\"']$valuePattern[\"'][^>]*content=[\"']([^\"']+)[\"'][^>]*>",
      caseSensitive: false,
    );
    final reversedRegex = RegExp(
      "<meta[^>]*content=[\"']([^\"']+)[\"'][^>]*$attrPattern=[\"']$valuePattern[\"'][^>]*>",
      caseSensitive: false,
    );
    return regex.firstMatch(html)?.group(1) ??
        reversedRegex.firstMatch(html)?.group(1);
  }

  String _htmlToText(String html) {
    final withoutScripts = html
        .replaceAll(
            RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');

    return withoutScripts
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
            RegExp(r'</(p|div|li|h1|h2|h3|h4|section)>', caseSensitive: false),
            '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\r'), '')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }

  List<String> _collectSectionLines(
    List<String> lines, {
    required List<String> headings,
    required List<String> stopHeadings,
  }) {
    final normalizedHeadings = headings.map(_normalizeHeading).toSet();
    final normalizedStops = stopHeadings.map(_normalizeHeading).toSet();
    final collected = <String>[];
    var inSection = false;

    for (final line in lines) {
      final normalized = _normalizeHeading(line);
      if (normalizedHeadings.contains(normalized)) {
        inSection = true;
        continue;
      }

      if (inSection && normalizedStops.contains(normalized)) {
        break;
      }

      if (!inSection) continue;
      if (line.length < 2) continue;
      if (_looksLikeTitle(line) && collected.length > 8) break;
      if (RegExp(r'^(serves?|portions?|yield)\b', caseSensitive: false)
          .hasMatch(line)) {
        break;
      }

      final cleaned = line.replaceFirst(RegExp(r'^[\-\u2022]\s*'), '');
      if (cleaned.isNotEmpty) {
        collected.add(cleaned);
      }

      if (collected.length >= 20) break;
    }

    return collected;
  }

  String _normalizeHeading(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zàâäçéèêëîïôöùûüÿœæ]'), '');
  }

  List<String> _stringList(dynamic value) {
    if (value == null) return const [];
    if (value is String) {
      final cleaned = _cleanText(value);
      return cleaned == null ? const [] : [cleaned];
    }
    if (value is List) {
      return value
          .map(_stringValue)
          .whereType<String>()
          .map(_cleanText)
          .whereType<String>()
          .toList();
    }
    return const [];
  }

  List<String> _parseInstructionNodes(dynamic value) {
    if (value == null) return const [];
    if (value is String) {
      final single = _cleanText(value);
      return single == null ? const [] : [single];
    }
    if (value is List) {
      final lines = <String>[];
      for (final entry in value) {
        if (entry is String) {
          final line = _cleanText(entry);
          if (line != null) lines.add(line);
          continue;
        }
        if (entry is Map) {
          final map = Map<String, dynamic>.from(entry);
          final nested =
              _stringValue(map['text'] ?? map['name'] ?? map['item']);
          final line = _cleanText(nested);
          if (line != null) lines.add(line);
        }
      }
      return lines;
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final nested = _stringValue(map['text'] ?? map['name']);
      final line = _cleanText(nested);
      return line == null ? const [] : [line];
    }
    return const [];
  }

  Map<String, dynamic>? _ingredientFromLine(String line) {
    final cleaned = _cleanIngredientLine(line);
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

    final quantity =
        double.tryParse((match.group(1) ?? '').replaceAll(',', '.')) ?? 0;
    final unit = (match.group(2) ?? '').trim();
    final name = (match.group(3) ?? cleaned).trim();
    if (name.isEmpty) return null;

    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
    };
  }

  String? _cleanIngredientLine(String value) {
    return _cleanText(
      value
          .replaceFirst(_ingredientGarbageCutPattern, '')
          .replaceFirst(RegExp(r'\s+\d+(?:[.,]\d+)?(?:/\d+)?\s*$'), ''),
    );
  }

  String? _imageValue(dynamic value) {
    if (value is String) return value;
    if (value is List && value.isNotEmpty) {
      return _imageValue(value.first);
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      return _stringValue(map['url'] ?? map['contentUrl']);
    }
    return null;
  }

  String? _resolveUrl(String? value, Uri baseUri) {
    final cleaned = _cleanText(value);
    if (cleaned == null) return null;
    final uri = Uri.tryParse(cleaned);
    if (uri == null) return null;
    return (uri.hasScheme ? uri : baseUri.resolveUri(uri)).toString();
  }

  String? _parseIso8601Duration(String? value) {
    if (value == null || value.isEmpty) return null;

    final match = RegExp(
      r'^P(?:\d+Y)?(?:\d+M)?(?:\d+D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return _cleanText(value);

    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
    final buffer = <String>[];
    if (hours > 0) buffer.add('${hours} h');
    if (minutes > 0) buffer.add('${minutes} min');
    if (seconds > 0 && hours == 0) buffer.add('${seconds} s');
    return buffer.isEmpty ? null : buffer.join(' ');
  }

  int? _parseServings(String? value) {
    if (value == null || value.isEmpty) return null;
    final match = RegExp(r'(\d{1,3})').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  int? _extractServings(String text) {
    final match = RegExp(
      r'(?:serves?|portions?|yield)\s*[:\-]?\s*(\d{1,3})',
      caseSensitive: false,
    ).firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  String? _extractTime(String text, List<String> labels) {
    for (final label in labels) {
      final match = RegExp(
        '${RegExp.escape(label)}\\s*[:\\-]?\\s*(\\d+\\s*(?:h|hr|min|mn|minutes?))',
        caseSensitive: false,
      ).firstMatch(text);
      if (match != null) {
        return _cleanText(match.group(1));
      }
    }
    return null;
  }

  String? _extractNotes(List<String> lines) {
    final joined = lines.join('\n');
    final match = RegExp(
      r'(?:notes?|tips?)\s*[:\-]\s*(.+)',
      caseSensitive: false,
    ).firstMatch(joined);
    return _cleanText(match?.group(1));
  }

  List<String> _guessCategories(String text) {
    final lower = text.toLowerCase();
    final categories = <String>[];
    const mapping = {
      'dessert': ['dessert', 'cake', 'tarte', 'cookie', 'chocolat'],
      'poisson': ['saumon', 'thon', 'poisson', 'cabillaud', 'crevette'],
      'viande': ['boeuf', 'veau', 'porc', 'agneau', 'steak'],
      'volaille': ['poulet', 'dinde', 'canard'],
      'légumes': ['courgette', 'carotte', 'champignon', 'aubergine', 'légume'],
      'sauce': ['sauce', 'vinaigrette', 'condiment'],
      'soupe': ['soupe', 'velouté', 'bouillon'],
      'plat': ['plat', 'dîner', 'diner', 'main course'],
      'entrée': ['entrée', 'starter', 'apéritif'],
    };

    mapping.forEach((category, keywords) {
      if (keywords.any(lower.contains)) {
        categories.add(category);
      }
    });

    return categories;
  }

  bool _looksLikeTitle(String? value) {
    if (value == null || value.isEmpty) return false;
    if (value.length > 80) return false;
    final lower = value.toLowerCase();
    return !lower.contains('http') &&
        !lower.contains('{') &&
        !lower.contains('}');
  }

  String? _stringValue(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    if (value is List && value.isNotEmpty) return _stringValue(value.first);
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      return _stringValue(map['@value'] ?? map['name'] ?? map['text']);
    }
    return null;
  }

  String? _cleanText(String? value) {
    if (value == null) return null;
    final cleaned = value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(' ,', ',')
        .replaceAll(' .', '.')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}

class _RecipeNodeScore {
  const _RecipeNodeScore({
    required this.recipe,
    required this.index,
    required this.score,
    required this.ingredientCount,
    required this.isValid,
  });

  final Map<String, dynamic> recipe;
  final int index;
  final int score;
  final int ingredientCount;
  final bool isValid;
}
