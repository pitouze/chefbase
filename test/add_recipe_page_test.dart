import 'dart:io';

import 'package:chefbase_app/pages/add_recipe_page.dart';
import 'package:chefbase_app/services/backend_recipe_importer.dart';
import 'package:chefbase_app/services/recipe_url_importer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingBackendRecipeImporter extends BackendRecipeImporter {
  @override
  Future<ImportedRecipeData> importFromUrl(String rawUrl) async {
    throw const SocketException('backend unavailable');
  }
}

class _SuccessfulBackendRecipeImporter extends BackendRecipeImporter {
  @override
  Future<ImportedRecipeData> importFromUrl(String rawUrl) async {
    return const ImportedRecipeData(
      title: 'Recette backend',
      description: 'Description backend',
      ingredients: [
        {'name': 'farine', 'quantity': 200, 'unit': 'g'},
      ],
      instructions: ['Mélanger.'],
      servings: 2,
    );
  }
}

class _FailingRecipeUrlImporter extends RecipeUrlImporter {
  @override
  Future<ImportedRecipeData> importFromUrl(
    String rawUrl, {
    Future<String> Function(Uri uri)? fetchHtml,
  }) async {
    throw const RecipeImportException(RecipeUrlImporter.blockedImportMessage);
  }
}

class _SuccessfulRecipeUrlImporter extends RecipeUrlImporter {
  @override
  Future<ImportedRecipeData> importFromUrl(
    String rawUrl, {
    Future<String> Function(Uri uri)? fetchHtml,
  }) async {
    return const ImportedRecipeData(
      title: 'Recette locale',
      description: 'Description locale',
    );
  }
}

void main() {
  testWidgets('uses backend importer before local URL importer',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddRecipePage(
          backendRecipeImporter: _SuccessfulBackendRecipeImporter(),
          recipeUrlImporter: _SuccessfulRecipeUrlImporter(),
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'https://www.marmiton.org/recettes/recette_test.aspx',
    );
    final importButton = find.widgetWithText(
      ElevatedButton,
      'Importer depuis URL',
    );
    await tester.ensureVisible(importButton);
    await tester.tap(importButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Recette backend'), findsOneWidget);
    expect(find.text('Description backend'), findsOneWidget);
    expect(find.text('Recette locale'), findsNothing);
  });

  testWidgets('shows backend error when backend import fails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddRecipePage(
          backendRecipeImporter: _FailingBackendRecipeImporter(),
          recipeUrlImporter: _SuccessfulRecipeUrlImporter(),
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'https://www.marmiton.org/recettes/recette_test.aspx',
    );
    final importButton = find.widgetWithText(
      ElevatedButton,
      'Importer depuis URL',
    );
    await tester.ensureVisible(importButton);
    await tester.tap(importButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Recette locale'), findsNothing);
    expect(find.text('Description locale'), findsNothing);
    expect(
      find.text(
        'Backend erreur: SocketException: backend unavailable\n'
        'L’URL reste en place pour continuer.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps URL and existing form values when URL import fails',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddRecipePage(
          backendRecipeImporter: _FailingBackendRecipeImporter(),
          recipeUrlImporter: _FailingRecipeUrlImporter(),
        ),
      ),
    );

    final fields = find.byType(TextFormField);

    await tester.enterText(fields.at(1), 'Recette existante');
    await tester.enterText(fields.at(2), 'Description existante');
    await tester.enterText(fields.at(3), 'Notes existantes');
    await tester.enterText(
      fields.at(0),
      'https://www.marmiton.org/recettes/recette_test.aspx',
    );
    final importButton = find.widgetWithText(
      ElevatedButton,
      'Importer depuis URL',
    );
    await tester.ensureVisible(importButton);
    await tester.tap(importButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text(
        'Backend erreur: SocketException: backend unavailable\n'
        'L’URL reste en place pour continuer.',
      ),
      findsOneWidget,
    );
    expect(find.text('Recette existante'), findsOneWidget);
    expect(find.text('Description existante'), findsOneWidget);
    expect(find.text('Notes existantes'), findsOneWidget);
    expect(
      find.text('https://www.marmiton.org/recettes/recette_test.aspx'),
      findsOneWidget,
    );
  });
}
