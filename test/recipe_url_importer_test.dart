import 'dart:async';
import 'dart:io';

import 'package:chefbase_app/services/recipe_ai_importer.dart';
import 'package:chefbase_app/services/recipe_url_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports recipe fields from schema.org json-ld', () async {
    final importer = RecipeUrlImporter();
    const html = '''
<!doctype html>
<html>
  <head>
    <script type="application/ld+json">
      {
        "@context": "https://schema.org",
        "@type": "Recipe",
        "name": "Tarte aux pommes",
        "description": "Un grand classique.",
        "recipeIngredient": ["2 pommes", "120 g sucre"],
        "recipeInstructions": [
          {"@type": "HowToStep", "text": "Préchauffer le four"},
          {"@type": "HowToStep", "text": "Cuire 35 min"}
        ],
        "prepTime": "PT20M",
        "cookTime": "PT35M",
        "recipeYield": "6 portions",
        "image": "/images/tarte.jpg",
        "recipeCategory": ["dessert", "tarte"],
        "keywords": "Feuilletée"
      }
    </script>
  </head>
</html>
''';

    final result = await importer.importFromUrl(
      'https://example.com/tarte',
      fetchHtml: (_) async => html,
    );

    expect(result.title, 'Tarte aux pommes');
    expect(result.description, 'Un grand classique.');
    expect(result.ingredients, hasLength(2));
    expect(result.instructions, ['Préchauffer le four', 'Cuire 35 min']);
    expect(result.prepTime, '20 min');
    expect(result.cookTime, '35 min');
    expect(result.servings, 6);
    expect(result.imageUrl, 'https://example.com/images/tarte.jpg');
    expect(result.notes, 'Feuilletée');
    expect(result.categories, containsAll(['dessert', 'tarte']));
  });

  test('chooses usable Recipe node from noisy json-ld graph', () async {
    final importer = RecipeUrlImporter();
    const html = '''
<!doctype html>
<html>
  <head>
    <script type="application/ld+json">
      {
        "@context": "https://schema.org",
        "@graph": [
          {
            "@type": "WebPage",
            "name": "1100 partenaires",
            "recipeIngredient": ["cookies", "publicité", "données", "tracking"],
            "recipeInstructions": "Accepter les cookies."
          },
          {
            "@type": "Article",
            "name": "1100 partenaires"
          },
          {
            "@type": "Organization",
            "name": "Marmiton"
          },
          {
            "@type": "Recipe",
            "name": "1100 partenaires",
            "recipeIngredient": [
              "cookies",
              "publicité",
              "données personnelles",
              "tracking",
              "consentement"
            ],
            "recipeInstructions": [
              {"@type": "HowToStep", "text": "Utiliser les cookies."},
              {"@type": "HowToStep", "text": "Accepter les partenaires."},
              {"@type": "HowToStep", "text": "Valider le consentement."}
            ]
          },
          {
            "@type": "Recipe",
            "name": "Cake moelleux au citron",
            "recipeIngredient": [
              "180 g farine casserole Top 2",
              "3 œufs 1 casserole Top 3 meilleurs ustensiles acheter détails",
              "120 g sucre acheter en promotion",
              "1 citron",
              "1 sachet levure balance de cuisine"
            ],
            "recipeInstructions": [
              {"@type": "HowToStep", "text": "Mélanger les œufs et le sucre."},
              {"@type": "HowToStep", "text": "Ajouter la farine, la levure et le citron."},
              {"@type": "HowToStep", "text": "Cuire le cake 35 min."}
            ]
          }
        ]
      }
    </script>
  </head>
  <body>1100 partenaires</body>
</html>
''';

    final result = await importer.importFromUrl(
      'https://example.com/cake',
      fetchHtml: (_) async => html,
    );

    expect(result.title, isNot('1100 partenaires'));
    expect(result.title?.toLowerCase(), isNot(contains('partenaires')));
    expect(
        result.title, matches(RegExp(r'cake|moelleux', caseSensitive: false)));
    expect(result.title, 'Cake moelleux au citron');
    expect(result.instructions, [
      'Mélanger les œufs et le sucre.',
      'Ajouter la farine, la levure et le citron.',
      'Cuire le cake 35 min.',
    ]);
    final ingredientText = result.ingredients.toString().toLowerCase();
    expect(ingredientText, isNot(contains('casserole')));
    expect(ingredientText, isNot(contains('top')));
    expect(ingredientText, isNot(contains('acheter')));
  });

  test('falls back to meta tags and visible text', () async {
    final importer = RecipeUrlImporter();
    const html = '''
<!doctype html>
<html>
  <head>
    <title>Soupe de carottes</title>
    <meta name="description" content="Douce et rapide." />
    <meta property="og:image" content="https://example.com/soupe.jpg" />
  </head>
  <body>
    <h1>Soupe de carottes</h1>
    <p>Douce et rapide.</p>
    <h2>Ingredients</h2>
    <ul>
      <li>500 g carottes</li>
      <li>1 oignon</li>
    </ul>
    <h2>Instructions</h2>
    <ol>
      <li>Faire revenir l'oignon</li>
      <li>Cuire 20 min</li>
    </ol>
    <p>Serves: 4</p>
  </body>
</html>
''';

    final result = await importer.importFromUrl(
      'https://example.com/soupe',
      fetchHtml: (_) async => html,
    );

    expect(result.title, 'Soupe de carottes');
    expect(result.description, 'Douce et rapide.');
    expect(result.imageUrl, 'https://example.com/soupe.jpg');
    expect(result.ingredients, hasLength(2));
    expect(result.instructions, ['Faire revenir l\'oignon', 'Cuire 20 min']);
    expect(result.servings, 4);
  });

  test('uses fallback parser when AI importer fails', () async {
    final importer = RecipeUrlImporter(
      aiImporter: RecipeAIImporter(
        requestRecipeJson: ({required url, required htmlContent}) async {
          throw StateError('mock AI unavailable');
        },
      ),
    );
    const html = '''
<!doctype html>
<html>
  <head>
    <title>Soupe de carottes</title>
    <meta name="description" content="Douce et rapide." />
  </head>
  <body>
    <h1>Soupe de carottes</h1>
    <p>Douce et rapide.</p>
    <h2>Ingredients</h2>
    <ul>
      <li>500 g carottes</li>
      <li>1 oignon</li>
    </ul>
    <h2>Instructions</h2>
    <ol>
      <li>Faire revenir l'oignon</li>
      <li>Cuire 20 min</li>
    </ol>
    <p>Serves: 4</p>
  </body>
</html>
''';

    final result = await importer.importFromUrl(
      'https://example.com/soupe',
      fetchHtml: (_) async => html,
    );

    expect(result.title, 'Soupe de carottes');
    expect(result.ingredients, hasLength(2));
    expect(result.instructions, ['Faire revenir l\'oignon', 'Cuire 20 min']);
    expect(result.servings, 4);
  });

  test('merges AI response with fallback-only fields', () async {
    final importer = RecipeUrlImporter(
      aiImporter: RecipeAIImporter(
        requestRecipeJson: ({required url, required htmlContent}) async => '''
{
  "title": "Tarte pommes AI",
  "description": "Version IA",
  "ingredients": ["2 pommes", "120 g sucre"],
  "steps": ["Préchauffer le four", "Cuire 35 min"],
  "servings": 6
}
''',
      ),
    );
    const html = '''
<!doctype html>
<html>
  <head>
    <meta property="og:image" content="https://example.com/tarte.jpg" />
    <script type="application/ld+json">
      {
        "@context": "https://schema.org",
        "@type": "Recipe",
        "name": "Tarte aux pommes",
        "description": "Un grand classique.",
        "recipeIngredient": ["2 pommes", "120 g sucre"],
        "recipeInstructions": [
          {"@type": "HowToStep", "text": "Préchauffer le four"},
          {"@type": "HowToStep", "text": "Cuire 35 min"}
        ],
        "recipeYield": "6 portions",
        "image": "https://example.com/tarte-jsonld.jpg",
        "recipeCategory": ["dessert", "tarte"],
        "keywords": "Feuilletée"
      }
    </script>
  </head>
</html>
''';

    final result = await importer.importFromUrl(
      'https://example.com/tarte',
      fetchHtml: (_) async => html,
    );

    expect(result.title, 'Tarte pommes AI');
    expect(result.description, 'Version IA');
    expect(result.instructions, ['Préchauffer le four', 'Cuire 35 min']);
    expect(result.servings, 6);
    expect(result.imageUrl, 'https://example.com/tarte-jsonld.jpg');
    expect(result.notes, 'Feuilletée');
    expect(result.categories, containsAll(['dessert', 'tarte']));
  });

  test('maps blocked fetch errors to a user-safe french message', () async {
    final importer = RecipeUrlImporter();

    expect(
      () => importer.importFromUrl(
        'https://example.com/marmiton',
        fetchHtml: (_) async => throw const HttpException(
          'Connection closed while receiving data',
        ),
      ),
      throwsA(
        isA<RecipeImportException>().having(
          (error) => error.userMessage,
          'userMessage',
          RecipeUrlImporter.blockedImportMessage,
        ),
      ),
    );
  });

  test('maps timeout fetch errors to the same manual fallback message',
      () async {
    final importer = RecipeUrlImporter();

    expect(
      () => importer.importFromUrl(
        'https://example.com/marmiton',
        fetchHtml: (_) async => throw TimeoutException('timed out'),
      ),
      throwsA(
        isA<RecipeImportException>().having(
          (error) => error.userMessage,
          'userMessage',
          RecipeUrlImporter.blockedImportMessage,
        ),
      ),
    );
  });
}
