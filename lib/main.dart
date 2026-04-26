import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'pages/recipes_page.dart';
import 'pages/sous_vide_page.dart';
import 'pages/techniques_page.dart';
import 'pages/products_page.dart';

void main() {
  runApp(const ChefBaseApp());
}

class ChefBaseApp extends StatelessWidget {
  const ChefBaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFD97706),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF7F3EE),
    );

    return MaterialApp(
      title: 'ChefBase',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFFF7F3EE),
          foregroundColor: Color(0xFF1F1A17),
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1F1A17),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE9DDD0)),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white,
          selectedColor: const Color(0xFFF4E4C8),
          disabledColor: Colors.white,
          secondarySelectedColor: const Color(0xFFF4E4C8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          labelStyle: const TextStyle(
            fontSize: 12,
            color: Color(0xFF6A6058),
          ),
          secondaryLabelStyle: const TextStyle(
            fontSize: 12,
            color: Color(0xFF6A6058),
          ),
          brightness: Brightness.light,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE9DDD0)),
          ),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1F1A17),
          ),
          titleLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1F1A17),
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            height: 1.5,
            color: Color(0xFF3B332E),
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: Color(0xFF5A514B),
          ),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomePage(),
        '/recipes': (context) => const RecipesPage(),
        '/sous-vide': (context) => const SousVidePage(),
        '/techniques': (context) => const TechniquesPage(),
        '/products': (context) => const ProductsPage(),
      },
    );
  }
}
