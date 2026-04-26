import 'dart:async';
import 'dart:convert';
import 'dart:io';

export 'imported_recipe_data.dart';
import 'imported_recipe_data.dart';
import 'recipe_ai_importer.dart';
import 'recipe_html_fallback_parser.dart';

class RecipeImportException implements Exception {
  const RecipeImportException(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}

class RecipeUrlImporter {
  RecipeUrlImporter({
    RecipeAIImporter? aiImporter,
    RecipeHtmlFallbackParser? fallbackParser,
  })  : _aiImporter = aiImporter ?? RecipeAIImporter(),
        _fallbackParser = fallbackParser ?? const RecipeHtmlFallbackParser();

  final RecipeAIImporter _aiImporter;
  final RecipeHtmlFallbackParser _fallbackParser;

  static const String blockedImportMessage =
      "Ce site bloque l’import automatique. Essayez une autre URL ou copiez la recette manuellement.";
  static const String noRecipeFoundMessage =
      'Aucune recette exploitable trouvée sur cette page.';
  static const Duration _requestTimeout = Duration(seconds: 15);

  Future<ImportedRecipeData> importFromUrl(
    String rawUrl, {
    Future<String> Function(Uri uri)? fetchHtml,
  }) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('URL invalide');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException('URL invalide');
    }

    final html = await _fetchHtmlSafely(
      uri,
      fetchHtml: fetchHtml,
    );
    final fallback = _fallbackParser.parse(html, uri);

    ImportedRecipeData aiImported;
    try {
      aiImported = await _aiImporter.importRecipe(
        url: uri,
        htmlContent: html,
      );
    } catch (_) {
      aiImported = const ImportedRecipeData();
    }

    final combined = aiImported.merge(fallback);
    if (!combined.hasAnyValue) {
      throw const RecipeImportException(noRecipeFoundMessage);
    }

    return combined;
  }

  Future<String> _fetchHtmlSafely(
    Uri uri, {
    Future<String> Function(Uri uri)? fetchHtml,
  }) async {
    try {
      return await (fetchHtml ?? _fetchHtml)(uri);
    } on RecipeImportException {
      rethrow;
    } on TimeoutException {
      throw const RecipeImportException(blockedImportMessage);
    } on SocketException {
      throw const RecipeImportException(blockedImportMessage);
    } on HttpException {
      throw const RecipeImportException(blockedImportMessage);
    }
  }

  Future<String> _fetchHtml(Uri uri) async {
    final client = HttpClient();
    client.connectionTimeout = _requestTimeout;

    try {
      final request = await client.getUrl(uri).timeout(_requestTimeout);
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 '
        'Mobile/15E148 Safari/604.1 ChefBase/1.0',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      );
      request.headers.set(
        HttpHeaders.acceptLanguageHeader,
        'fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7',
      );
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      return response.transform(utf8.decoder).join().timeout(_requestTimeout);
    } finally {
      client.close(force: true);
    }
  }
}
