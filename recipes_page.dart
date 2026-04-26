import 'package:flutter/material.dart';

class RecipesPage extends StatelessWidget {
  const RecipesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recettes'),
      ),
      body: const Center(
        child: Text(
          'Liste des recettes à venir...',
          style: TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}