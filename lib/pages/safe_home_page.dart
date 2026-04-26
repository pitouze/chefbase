import 'package:flutter/material.dart';

class SafeHomePage extends StatelessWidget {
  const SafeHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ChefBase OK',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Startup safe mode',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  _SafeNavButton(
                    label: 'Recettes',
                    routeName: '/recipes',
                  ),
                  const SizedBox(height: 12),
                  _SafeNavButton(
                    label: 'Sous-vide',
                    routeName: '/sous-vide',
                  ),
                  const SizedBox(height: 12),
                  _SafeNavButton(
                    label: 'Techniques',
                    routeName: '/techniques',
                  ),
                  const SizedBox(height: 12),
                  _SafeNavButton(
                    label: 'Produits',
                    routeName: '/products',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SafeNavButton extends StatelessWidget {
  const _SafeNavButton({
    required this.label,
    required this.routeName,
  });

  final String label;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: () => Navigator.pushNamed(context, routeName),
      child: Text(label),
    );
  }
}
