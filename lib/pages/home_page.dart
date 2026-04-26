import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/recipe_store.dart';
import '../widgets/chefbase_list_tile.dart';
import 'products_page.dart';
import 'recipe_detail_page.dart';
import 'sous_vide_detail_page.dart';
import 'techniques_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _latestRecipesLimit = 5;
  static const int _searchResultsLimit = 8;

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _recipes = [];
  List<Map<String, dynamic>> _latestRecipes = [];
  List<Map<String, dynamic>> _sousVideEntries = [];
  Map<String, dynamic>? _productsData;
  int _recipeCount = 0;
  int _favoriteCount = 0;
  bool _latestRecipesLoaded = false;
  bool _searchDataLoading = false;
  String _searchQuery = '';

  final List<_HomeNavigationItem> _navigationItems = const [
    _HomeNavigationItem(
      title: 'Recettes',
      subtitle: 'Fiches, ingrédients et étapes',
      icon: Icons.menu_book_rounded,
      route: '/recipes',
    ),
    _HomeNavigationItem(
      title: 'Sous-vide',
      subtitle: 'Temps et températures',
      icon: Icons.thermostat_rounded,
      route: '/sous-vide',
    ),
    _HomeNavigationItem(
      title: 'Techniques',
      subtitle: 'Gestes et bases culinaires',
      icon: Icons.restaurant_menu_rounded,
      route: '/techniques',
    ),
    _HomeNavigationItem(
      title: 'Produits',
      subtitle: 'Saisons et repères utiles',
      icon: Icons.eco_rounded,
      route: '/products',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHomeRecipes();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHomeRecipes() async {
    try {
      final recipes = await RecipeStore.loadRecipes();

      if (!mounted) return;
      setState(() {
        _recipes = recipes;
        _latestRecipes = RecipeStore.latestOpenedRecipes(
          recipes,
          limit: _latestRecipesLimit,
        );
        _updateRecipeMetrics(recipes);
        _latestRecipesLoaded = true;
      });
    } catch (error, stackTrace) {
      debugPrint('HomePage: home data load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _latestRecipesLoaded = true;
      });
    }
  }

  Future<void> _ensureSearchData() async {
    if (_searchDataLoading ||
        (_sousVideEntries.isNotEmpty && _productsData != null)) {
      return;
    }

    _searchDataLoading = true;
    try {
      final sousVideFuture =
          rootBundle.loadString('assets/data/sous_vide.json');
      final productsFuture =
          rootBundle.loadString('assets/data/products_data.json');

      List<Map<String, dynamic>> sousVideEntries = [];
      Map<String, dynamic>? productsData;

      try {
        final List decodedSousVide = jsonDecode(await sousVideFuture);
        sousVideEntries = decodedSousVide
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();
      } catch (_) {}

      try {
        productsData =
            Map<String, dynamic>.from(jsonDecode(await productsFuture) as Map);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _sousVideEntries = sousVideEntries;
        _productsData = productsData;
      });
    } finally {
      _searchDataLoading = false;
    }
  }

  void _updateRecipeMetrics(List<Map<String, dynamic>> recipes) {
    _recipeCount = recipes.length;
    _favoriteCount = recipes
        .where((recipe) => recipe['isFavorite'] as bool? ?? false)
        .length;
  }

  Future<void> _setRecipeFavorite(
    Map<String, dynamic> recipe,
    bool isFavorite,
  ) async {
    final createdAt = recipe['createdAt'];
    final title = RecipeStore.normalizeForSearch(
      recipe['title']?.toString() ?? '',
    );
    final index = _recipes.indexWhere((candidate) {
      final candidateTitle = RecipeStore.normalizeForSearch(
        candidate['title']?.toString() ?? '',
      );
      return identical(candidate, recipe) ||
          (candidateTitle == title && candidate['createdAt'] == createdAt);
    });

    if (index == -1) return;

    setState(() {
      _recipes[index]['isFavorite'] = isFavorite;
      _latestRecipes = RecipeStore.latestOpenedRecipes(
        _recipes,
        limit: _latestRecipesLimit,
      );
      _updateRecipeMetrics(_recipes);
    });

    await RecipeStore.saveRecipes(_recipes);
  }

  Future<void> _openRecipe(Map<String, dynamic> recipe) async {
    final updatedRecipes = await RecipeStore.markRecipeOpened(recipe);
    if (!mounted) return;
    setState(() {
      _recipes = updatedRecipes;
      _latestRecipes = RecipeStore.latestOpenedRecipes(
        updatedRecipes,
        limit: _latestRecipesLimit,
      );
      _updateRecipeMetrics(updatedRecipes);
    });

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailPage(
          title: recipe['title'] as String? ?? '',
          description: recipe['description'] as String? ?? '',
          imageUrl: recipe['imageUrl'] as String? ?? '',
          imageData: recipe['imageData'] as String? ?? '',
          ingredients: List<Map<String, dynamic>>.from(
            recipe['ingredients'] as List? ?? [],
          ),
          instructions: List<String>.from(
            recipe['instructions'] as List? ?? [],
          ),
          prepTime: recipe['prepTime'] as String? ?? '-',
          cookTime: recipe['cookTime'] as String? ?? '-',
          servings: recipe['servings'] as int? ?? 1,
          categories: List<String>.from(recipe['categories'] as List? ?? []),
          isFavorite: recipe['isFavorite'] as bool? ?? false,
          notes: recipe['notes'] as String? ?? '',
          timerDefaults: List<Map<String, dynamic>>.from(
            recipe['timerDefaults'] as List? ?? [],
          ),
          onFavoriteChanged: (value) => _setRecipeFavorite(recipe, value),
        ),
      ),
    );

    if (!mounted) return;
    await _loadHomeRecipes();
  }

  Future<void> _openRecipes() async {
    await Navigator.pushNamed(context, '/recipes');
    if (!mounted) return;
    await _loadHomeRecipes();
  }

  Future<void> _openNavigationItem(_HomeNavigationItem item) async {
    if (item.route == '/recipes') {
      await _openRecipes();
      return;
    }

    await Navigator.pushNamed(context, item.route);
  }

  List<_HomeSearchResult> _searchResults() {
    final query = RecipeStore.normalizeForSearch(_searchQuery);
    if (query.isEmpty) return const [];

    final results = <_HomeSearchResult>[];

    for (final recipe in _recipes) {
      final categories = List<String>.from(recipe['categories'] as List? ?? []);
      final text = RecipeStore.normalizeForSearch([
        recipe['title'],
        recipe['description'],
        recipe['notes'],
        categories.join(' '),
        List<Map<String, dynamic>>.from(recipe['ingredients'] as List? ?? [])
            .map((ingredient) => ingredient['name']?.toString() ?? '')
            .join(' '),
      ].map((value) => value?.toString() ?? '').join(' '));
      if (!text.contains(query)) continue;

      results.add(
        _HomeSearchResult(
          title: recipe['title'] as String? ?? '',
          subtitle: categories.isEmpty
              ? 'Recette'
              : 'Recette · ${categories.join(' · ')}',
          icon: Icons.menu_book_outlined,
          onTap: () => _openRecipe(recipe),
        ),
      );
    }

    for (final entry in _sousVideEntries) {
      final text = RecipeStore.normalizeForSearch([
        entry['title'],
        entry['siteCategory'],
        entry['texture'],
        entry['note'],
        entry['temp'],
        entry['time'],
      ].map((value) => value?.toString() ?? '').join(' '));
      if (!text.contains(query)) continue;

      results.add(
        _HomeSearchResult(
          title: entry['title'] as String? ?? '',
          subtitle:
              'Sous-vide · ${entry['temp'] ?? ''} · ${entry['time'] ?? ''}',
          icon: Icons.thermostat_outlined,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SousVideDetailPage(
                  item: entry,
                  isFavorite: false,
                  onToggleFavorite: () {},
                ),
              ),
            );
          },
        ),
      );
    }

    for (final technique in TechniquesPage.techniques) {
      final text = RecipeStore.normalizeForSearch([
        technique['title'],
        technique['description'],
        technique['category'],
        technique['time'],
        technique['difficulty'],
      ].map((value) => value?.toString() ?? '').join(' '));
      if (!text.contains(query)) continue;

      results.add(
        _HomeSearchResult(
          title: technique['title'] as String? ?? '',
          subtitle:
              'Technique · ${technique['category'] ?? ''} · ${technique['time'] ?? ''}',
          icon: Icons.restaurant_menu_outlined,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TechniqueDetailPage(technique: technique),
              ),
            );
          },
        ),
      );
    }

    final productsData = _productsData;
    if (productsData != null) {
      final details = List<Map<String, dynamic>>.from(
        productsData['details'] as List? ?? const [],
      );
      for (final item in details) {
        final text = RecipeStore.normalizeForSearch([
          item['name'],
          item['category'],
          item['notes'],
          List<String>.from(item['best_for'] as List? ?? const []).join(' '),
        ].map((value) => value?.toString() ?? '').join(' '));
        if (!text.contains(query)) continue;

        results.add(
          _HomeSearchResult(
            title: item['name'] as String? ?? '',
            subtitle: 'Produit · ${item['category'] ?? ''}',
            icon: Icons.eco_outlined,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProductDetailPage(item: item),
                ),
              );
            },
          ),
        );
      }

      for (final group in seasonalGroups(productsData['seasonal'])) {
        for (final section in group.sections) {
          for (final item in section.items) {
            final text = RecipeStore.normalizeForSearch(
              '$item ${group.title} ${section.title}',
            );
            if (!text.contains(query)) continue;

            results.add(
              _HomeSearchResult(
                title: item,
                subtitle: 'Produit de saison · ${group.title}',
                icon: Icons.eco_outlined,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProductsSeasonPage(
                        seasonal: productsData['seasonal'],
                      ),
                    ),
                  );
                },
              ),
            );
          }
        }
      }
    }

    return results.take(_searchResultsLimit).toList();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
    });
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
        });
        if (value.trim().isNotEmpty) {
          _ensureSearchData();
        }
      },
      decoration: InputDecoration(
        hintText: 'Rechercher recettes, cuissons, techniques, produits...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Effacer',
                onPressed: _clearSearch,
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE6E0DA)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE6E0DA)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFB45309)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchResults = _searchResults();
    final hasSearch = _searchQuery.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ChefBase',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1F1A17),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Carnet de cuisine, repères techniques et produits de saison.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6A6058),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HomeMetricChip(
                    label: 'recettes',
                    value: _latestRecipesLoaded ? _recipeCount.toString() : '-',
                  ),
                  _HomeMetricChip(
                    label: 'favoris',
                    value:
                        _latestRecipesLoaded ? _favoriteCount.toString() : '-',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _searchField(),
              if (hasSearch) ...[
                const SizedBox(height: 12),
                if (searchResults.isEmpty)
                  Text(
                    'Aucun résultat.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6A6058),
                    ),
                  )
                else
                  ...searchResults.map(
                    (result) => ChefBaseListTile(
                      title: result.title,
                      subtitle: result.subtitle,
                      leading: Icon(
                        result.icon,
                        color: const Color(0xFF8A7A6E),
                        size: 19,
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF9A9088),
                        size: 20,
                      ),
                      onTap: result.onTap,
                    ),
                  ),
              ],
              const SizedBox(height: 34),
              _SectionHeader(
                title: 'Explorer',
                actionLabel: 'Tout voir',
                onAction: _openRecipes,
              ),
              const SizedBox(height: 6),
              ..._navigationItems.map(
                (item) => _HomeNavRow(
                  item: item,
                  onTap: () => _openNavigationItem(item),
                ),
              ),
              const SizedBox(height: 34),
              _SectionHeader(
                title: 'Dernières recettes',
                actionLabel: 'Recettes',
                onAction: _openRecipes,
              ),
              const SizedBox(height: 6),
              if (_latestRecipes.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _latestRecipesLoaded
                        ? 'Aucune recette ouverte récemment.'
                        : 'Chargement des recettes...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6A6058),
                    ),
                  ),
                )
              else
                ..._latestRecipes.map((recipe) {
                  final categories = List<String>.from(
                    recipe['categories'] as List? ?? [],
                  );
                  final subtitle = categories.isEmpty
                      ? (recipe['description'] as String? ?? '')
                      : categories.join(' · ');

                  return Padding(
                    padding: EdgeInsets.zero,
                    child: _LatestRecipeTile(
                      title: recipe['title'] as String? ?? '',
                      subtitle: subtitle,
                      onTap: () => _openRecipe(recipe),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeSearchResult {
  const _HomeSearchResult({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1F1A17),
            ),
          ),
        ),
        IconButton(
          onPressed: onAction,
          tooltip: actionLabel,
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFFD97706),
            minimumSize: const Size.square(36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.arrow_forward_rounded, size: 20),
        ),
      ],
    );
  }
}

class _HomeMetricChip extends StatelessWidget {
  const _HomeMetricChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6F3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$value $label',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF5A514B),
        ),
      ),
    );
  }
}

class _HomeNavRow extends StatelessWidget {
  const _HomeNavRow({
    required this.item,
    required this.onTap,
  });

  final _HomeNavigationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFEDE7E1)),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              children: [
                Icon(item.icon, color: const Color(0xFF8A7A6E), size: 19),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F1A17),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          color: Color(0xFF6A6058),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF9A9088),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LatestRecipeTile extends StatelessWidget {
  const _LatestRecipeTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFEDE7E1)),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              children: [
                const Icon(
                  Icons.menu_book_outlined,
                  color: Color(0xFF8A7A6E),
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F1A17),
                        ),
                      ),
                      if (subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6A6058),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF9A9088),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeNavigationItem {
  const _HomeNavigationItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
}
