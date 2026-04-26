import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chefbase_app/main.dart';
import 'package:chefbase_app/pages/products_page.dart';
import 'package:chefbase_app/pages/sous_vide_detail_page.dart';
import 'package:chefbase_app/pages/sous_vide_page.dart';
import 'package:chefbase_app/pages/techniques_page.dart';
import 'package:chefbase_app/services/notification_service.dart';
import 'package:chefbase_app/widgets/inline_timer_card.dart';

class _ScheduleCall {
  final int id;
  final String title;
  final Duration duration;

  const _ScheduleCall({
    required this.id,
    required this.title,
    required this.duration,
  });
}

Future<void> _pumpSousVidePage(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: SousVidePage(),
    ),
  );
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ChefBase opens on home with seeded navigation', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ChefBaseApp());
    await tester.pumpAndSettle();

    expect(find.text('ChefBase'), findsOneWidget);
    expect(find.text('Recettes'), findsOneWidget);
    expect(find.text('Sous-vide'), findsOneWidget);
    expect(find.text('Techniques'), findsOneWidget);
    expect(find.text('Produits'), findsOneWidget);
  });

  testWidgets('Techniques overview opens timed detail', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: TechniquesPage(),
      ),
    );

    expect(find.text('Œuf poché parfait'), findsOneWidget);
    expect(find.text('Beurre blanc rattrapé'), findsOneWidget);
    expect(find.text('Cuisson viande parfaite'), findsOneWidget);
    expect(find.text('Minuteur'), findsNothing);
    expect(
      find.text(
          'Porter une casserole d’eau à frémissement, sans gros bouillon.'),
      findsNothing,
    );

    await tester.tap(find.text('Œuf poché parfait'));
    await tester.pumpAndSettle();

    expect(find.text('Technique'), findsOneWidget);
    expect(
      find.text(
          'Porter une casserole d’eau à frémissement, sans gros bouillon.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Minuteur'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Minuteur'), findsOneWidget);
    expect(find.text('2 min 30'), findsOneWidget);
    expect(find.text('1 min'), findsNothing);
    expect(find.text('5 min'), findsNothing);
    expect(find.text('10 min'), findsNothing);
    expect(find.text('30 min'), findsNothing);
  });

  testWidgets('Untimed technique detail hides timer', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: TechniquesPage(),
      ),
    );

    await tester.tap(find.text('Beurre blanc rattrapé'));
    await tester.pumpAndSettle();

    expect(find.text('Retirer immédiatement la casserole du feu.'),
        findsOneWidget);
    expect(find.text('Minuteur'), findsNothing);
    expect(find.text('Durée personnalisée'), findsNothing);
    expect(find.text('Lancer le minuteur'), findsNothing);
    expect(find.text('1 min'), findsNothing);
    expect(find.text('10 min'), findsNothing);
    expect(find.text('30 min'), findsNothing);
  });

  testWidgets('Sous-vide detail uses structured timer presets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SousVideDetailPage(
          item: const {
            'title': 'Filet brochet',
            'siteCategory': 'POISSONS',
            'temp': '55°C à 59°C',
            'time': '8 à 20 min',
            'timerDefaults': [
              {'label': 'Min 8 min', 'durationSeconds': 480},
              {'label': 'Max 20 min', 'durationSeconds': 1200},
            ],
          },
          isFavorite: false,
          onToggleFavorite: () {},
        ),
      ),
    );

    expect(find.text('Minuteur'), findsOneWidget);
    expect(find.text('Min 8 min'), findsOneWidget);
    expect(find.text('Max 20 min'), findsOneWidget);
    expect(find.text('1 min'), findsNothing);
    expect(find.text('5 min'), findsNothing);
    expect(find.text('10 min'), findsNothing);
    expect(find.text('30 min'), findsNothing);
  });

  testWidgets('InlineTimerCard starts a preset timer', (tester) async {
    final scheduleCalls = <_ScheduleCall>[];
    final cancelCalls = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineTimerCard(
            title: 'Œufs',
            presets: const [
              TimerPreset(label: '3 sec', duration: Duration(seconds: 3)),
            ],
            scheduleTimerNotification: ({
              required id,
              required title,
              required duration,
            }) async {
              scheduleCalls.add(
                _ScheduleCall(id: id, title: title, duration: duration),
              );
              return const TimerScheduleResult(scheduled: true, exact: true);
            },
            cancelTimerNotification: (id) async {
              cancelCalls.add(id);
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('3 sec'));
    await tester.pump();

    expect(scheduleCalls, hasLength(1));
    expect(scheduleCalls.single.title, 'Œufs');
    expect(scheduleCalls.single.duration, const Duration(seconds: 3));
    expect(cancelCalls, isEmpty);
    expect(find.text('En cours'), findsOneWidget);
    expect(find.text('00:03'), findsOneWidget);
    expect(find.text('Minuteur lancé.'), findsOneWidget);
  });

  testWidgets('InlineTimerCard rejects zero custom duration', (tester) async {
    var scheduleCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineTimerCard(
            title: 'Test',
            scheduleTimerNotification: ({
              required id,
              required title,
              required duration,
            }) async {
              scheduleCount++;
              return const TimerScheduleResult(scheduled: true, exact: true);
            },
            cancelTimerNotification: (id) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Lancer le minuteur'));
    await tester.pump();

    expect(scheduleCount, 0);
    expect(find.text('Prêt'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('Entre une durée supérieure à zéro.'), findsOneWidget);
  });

  testWidgets('InlineTimerCard normalizes custom seconds', (tester) async {
    Duration? scheduledDuration;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineTimerCard(
            title: 'Test',
            scheduleTimerNotification: ({
              required id,
              required title,
              required duration,
            }) async {
              scheduledDuration = duration;
              return const TimerScheduleResult(scheduled: true, exact: true);
            },
            cancelTimerNotification: (id) async {},
          ),
        ),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Min'), '0');
    await tester.enterText(find.widgetWithText(TextField, 'Sec'), '90');
    await tester.tap(find.text('Lancer le minuteur'));
    await tester.pump();

    expect(scheduledDuration, const Duration(seconds: 59));
    expect(find.text('00:59'), findsOneWidget);
    expect(find.text('Secondes limitées à 59.'), findsOneWidget);
  });

  testWidgets('InlineTimerCard stops and cancels active timer', (tester) async {
    final scheduleCalls = <_ScheduleCall>[];
    final cancelCalls = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineTimerCard(
            title: 'Test',
            presets: const [
              TimerPreset(label: '5 sec', duration: Duration(seconds: 5)),
            ],
            scheduleTimerNotification: ({
              required id,
              required title,
              required duration,
            }) async {
              scheduleCalls.add(
                _ScheduleCall(id: id, title: title, duration: duration),
              );
              return const TimerScheduleResult(scheduled: true, exact: true);
            },
            cancelTimerNotification: (id) async {
              cancelCalls.add(id);
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('5 sec'));
    await tester.pump();
    await tester.tap(find.text('Arrêter'));
    await tester.pump();

    expect(scheduleCalls, hasLength(1));
    expect(cancelCalls, [scheduleCalls.single.id]);
    expect(find.text('Arrêté'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('Minuteur arrêté.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('InlineTimerCard finishes countdown', (tester) async {
    final cancelCalls = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineTimerCard(
            title: 'Œufs',
            presets: const [
              TimerPreset(label: '2 sec', duration: Duration(seconds: 2)),
            ],
            scheduleTimerNotification: ({
              required id,
              required title,
              required duration,
            }) async {
              return const TimerScheduleResult(scheduled: true, exact: true);
            },
            cancelTimerNotification: (id) async {
              cancelCalls.add(id);
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('2 sec'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('00:01'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(cancelCalls, isEmpty);
    expect(find.text('Terminé'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('Minuteur terminé.'), findsOneWidget);
    expect(find.text('Œufs : minuteur terminé'), findsOneWidget);
  });

  test('Sous-vide asset has valid timer defaults', () async {
    final jsonString =
        await rootBundle.loadString('assets/data/sous_vide.json');
    final data = jsonDecode(jsonString) as List<dynamic>;

    expect(data, isNotEmpty);

    for (final entry in data) {
      final item = entry as Map<String, dynamic>;
      final title = item['title']?.toString() ?? '<missing title>';
      final timerDefaults = item['timerDefaults'];

      expect(
        timerDefaults,
        isA<List<dynamic>>(),
        reason: '$title must define timerDefaults',
      );
      expect(
        timerDefaults as List<dynamic>,
        isNotEmpty,
        reason: '$title must define at least one timer preset',
      );

      for (final preset in timerDefaults) {
        final timerPreset = preset as Map<String, dynamic>;
        final label = timerPreset['label']?.toString().trim() ?? '';
        final durationSeconds = timerPreset['durationSeconds'];

        expect(label, isNotEmpty, reason: '$title has an empty timer label');
        expect(
          durationSeconds,
          isA<num>(),
          reason: '$title has a non-numeric timer duration',
        );
        expect(
          (durationSeconds as num).toInt(),
          greaterThan(0),
          reason: '$title has a non-positive timer duration',
        );
      }
    }
  });

  test('Products asset has valid seasonal month schema', () async {
    final jsonString =
        await rootBundle.loadString('assets/data/products_data.json');
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final seasonal = data['seasonal'];

    expect(seasonal, isA<List<dynamic>>());
    expect(seasonal as List<dynamic>, isNotEmpty);

    for (final entry in seasonal) {
      final month = entry as Map<String, dynamic>;
      final title = month['title']?.toString().trim() ?? '';
      final fruits = month['fruits'];
      final vegetables = month['vegetables'];

      expect(title, isNotEmpty, reason: 'seasonal month title is required');
      expect(fruits, isA<List<dynamic>>(), reason: '$title needs fruits');
      expect(
        vegetables,
        isA<List<dynamic>>(),
        reason: '$title needs vegetables',
      );
      expect(fruits as List<dynamic>, isNotEmpty);
      expect(vegetables as List<dynamic>, isNotEmpty);

      for (final item in [...fruits, ...vegetables]) {
        expect(item, isA<String>());
        expect((item as String).trim(), isNotEmpty);
      }
    }
  });

  test('Products asset has valid details schema', () async {
    final jsonString =
        await rootBundle.loadString('assets/data/products_data.json');
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final details = data['details'];

    expect(details, isA<List<dynamic>>());
    expect(details as List<dynamic>, isNotEmpty);

    for (final entry in details) {
      final item = entry as Map<String, dynamic>;
      final name = item['name']?.toString().trim() ?? '';
      final category = item['category']?.toString().trim() ?? '';
      final notes = item['notes']?.toString().trim() ?? '';
      final bestFor = item['best_for'];

      expect(name, isNotEmpty, reason: 'detail name is required');
      expect(category, isNotEmpty, reason: '$name category is required');
      expect(notes, isNotEmpty, reason: '$name notes are required');
      expect(bestFor, isA<List<dynamic>>(), reason: '$name needs best_for');
      expect(bestFor as List<dynamic>, isNotEmpty);
    }
  });

  testWidgets('Products seasonal page supports month sections', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProductsSeasonPage(
          seasonal: [
            {
              'title': 'Avril',
              'fruits': ['fraise', 'rhubarbe'],
              'vegetables': ['asperge', 'épinard'],
              'items': ['fraise', 'rhubarbe', 'asperge', 'épinard'],
            },
          ],
        ),
      ),
    );

    expect(find.text('Avril'), findsOneWidget);
    expect(find.text('Fruits'), findsOneWidget);
    expect(find.text('Légumes'), findsOneWidget);
    expect(find.text('rhubarbe'), findsOneWidget);
    expect(find.text('asperge'), findsOneWidget);
    expect(find.text('fraise'), findsOneWidget);
  });

  testWidgets('Products seasonal page supports legacy sections',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProductsSeasonPage(
          seasonal: [
            {
              'title': 'Fruits de saison',
              'items': ['fraise', 'pomme'],
            },
            {
              'title': 'Légumes de saison',
              'items': ['asperge', 'épinard'],
            },
          ],
        ),
      ),
    );

    expect(find.text('Fruits de saison'), findsOneWidget);
    expect(find.text('Légumes de saison'), findsOneWidget);
    expect(find.text('fraise'), findsOneWidget);
    expect(find.text('épinard'), findsOneWidget);
  });

  testWidgets('Products detail search ignores accents', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProductsDetailsPage(
          details: [
            {
              'name': 'Pomme de terre farineuse',
              'category': 'légume',
              'best_for': ['purée', 'gnocchi'],
              'notes': 'Texture légère.',
            },
            {
              'name': 'Carotte',
              'category': 'légume',
              'best_for': ['glacée'],
              'notes': 'Garniture polyvalente.',
            },
          ],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'puree');
    await tester.pump();

    expect(find.text('Pomme de terre farineuse'), findsOneWidget);
    expect(find.text('Carotte'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();

    expect(
      find.text('Aucun produit ne correspond à cette recherche.'),
      findsOneWidget,
    );
  });

  testWidgets('Sous-vide search ignores accents and includes timing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await _pumpSousVidePage(tester);

    await tester.enterText(find.byType(TextField), 'creme');
    await tester.pump();

    expect(find.text('Crème Anglaise'), findsOneWidget);
    expect(find.text('Magret'), findsNothing);

    await tester.enterText(find.byType(TextField), '84');
    await tester.pump();

    expect(find.text('Crème Anglaise'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nacre');
    await tester.pump();

    expect(find.text('Filet brochet'), findsOneWidget);
  });

  testWidgets('Sous-vide favorites chip filters persisted favorites',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'chefbase_sous_vide_favorites_v1': jsonEncode(['Magret']),
    });

    await _pumpSousVidePage(tester);

    final favoritesChip = find.widgetWithText(ChoiceChip, 'Favoris');
    expect(favoritesChip, findsOneWidget);
    expect(find.text('★'), findsNothing);

    await tester.tap(favoritesChip);
    await tester.pump();

    expect(find.text('Magret'), findsOneWidget);
    expect(find.text('Crème Anglaise'), findsNothing);
  });
}
