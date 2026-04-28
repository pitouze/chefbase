import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/recipe_image_source.dart';
import '../services/recipe_store.dart';
import '../widgets/recipe_network_image_diagnostics.dart';
import 'recipe_detail_page.dart';
import 'add_recipe_page.dart';

class RecipesPage extends StatefulWidget {
  const RecipesPage({super.key});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> recipes = [];
  String selectedCategory = 'toutes';
  String searchQuery = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecipes();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _saveRecipes() async {
    await RecipeStore.saveRecipes(recipes);
  }

  Future<void> _loadRecipes() async {
    final loadedRecipes = await RecipeStore.loadRecipes();
    if (!mounted) return;
    setState(() {
      recipes = loadedRecipes;
      isLoading = false;
    });
  }

  Future<void> _addRecipe() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddRecipePage(),
      ),
    );

    if (result != null) {
      setState(() {
        recipes.insert(0, result);
      });
      await _saveRecipes();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recette ajoutée')),
      );
    }
  }

  Future<void> _editRecipe(int indexInRecipes) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => AddRecipePage(initialRecipe: recipes[indexInRecipes]),
      ),
    );

    if (result != null) {
      setState(() {
        recipes[indexInRecipes] = result;
      });
      await _saveRecipes();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recette modifiée')),
      );
    }
  }

  Future<void> _deleteRecipe(int indexInRecipes) async {
    final recipeTitle =
        recipes[indexInRecipes]['title'] as String? ?? 'cette recette';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Supprimer la recette'),
          content: Text('Voulez-vous vraiment supprimer "$recipeTitle" ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() {
        recipes.removeAt(indexInRecipes);
      });
      await _saveRecipes();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recette supprimée')),
      );
    }
  }

  Future<void> _toggleFavorite(int indexInRecipes) async {
    setState(() {
      recipes[indexInRecipes]['isFavorite'] =
          !(recipes[indexInRecipes]['isFavorite'] as bool? ?? false);
    });
    await _saveRecipes();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      searchQuery = '';
    });
  }

  List<String> _allCategories() {
    final values = <String>{'toutes', 'favoris'};
    for (final recipe in recipes) {
      final cats = List<String>.from(recipe['categories'] as List? ?? []);
      values.addAll(cats);
    }
    final result = values.toList();
    result.sort((a, b) {
      if (a == 'toutes') return -1;
      if (b == 'toutes') return 1;
      if (a == 'favoris') return -1;
      if (b == 'favoris') return 1;
      return a.compareTo(b);
    });
    return result;
  }

  List<Map<String, dynamic>> _filteredAndSortedRecipes() {
    final indexed = recipes.asMap().entries.map((entry) {
      return {
        'index': entry.key,
        'recipe': entry.value,
      };
    }).toList();

    final filtered = indexed.where((item) {
      final recipe = item['recipe'] as Map<String, dynamic>;
      final isFavorite = recipe['isFavorite'] as bool? ?? false;
      final categories = List<String>.from(recipe['categories'] as List? ?? []);
      final title =
          RecipeStore.normalizeForSearch(recipe['title'] as String? ?? '');
      final description = RecipeStore.normalizeForSearch(
        recipe['description'] as String? ?? '',
      );
      final notes =
          RecipeStore.normalizeForSearch(recipe['notes'] as String? ?? '');
      final ingredients = RecipeStore.normalizeForSearch(
        List<Map<String, dynamic>>.from(recipe['ingredients'] as List? ?? [])
            .map((ingredient) => ingredient['name']?.toString() ?? '')
            .join(' '),
      );
      final categoryText = RecipeStore.normalizeForSearch(categories.join(' '));
      final query = RecipeStore.normalizeForSearch(searchQuery);

      final matchesCategory = selectedCategory == 'toutes'
          ? true
          : selectedCategory == 'favoris'
              ? isFavorite
              : categories.contains(selectedCategory);

      final matchesSearch = query.isEmpty
          ? true
          : title.contains(query) ||
              description.contains(query) ||
              notes.contains(query) ||
              ingredients.contains(query) ||
              categoryText.contains(query);

      return matchesCategory && matchesSearch;
    }).toList();

    filtered.sort((a, b) {
      final recipeA = a['recipe'] as Map<String, dynamic>;
      final recipeB = b['recipe'] as Map<String, dynamic>;
      final createdAtA = recipeA['createdAt'] as int? ?? 0;
      final createdAtB = recipeB['createdAt'] as int? ?? 0;
      return createdAtB.compareTo(createdAtA);
    });

    return filtered;
  }

  Widget _titleWithAdd() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Recettes',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          onPressed: _addRecipe,
          tooltip: 'Ajouter une recette',
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFF7A4A12),
            minimumSize: const Size.square(32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(
            Icons.add_rounded,
            size: 20,
          ),
        ),
      ],
    );
  }

  Widget _categoryChip(String category) {
    final isSelected = selectedCategory == category;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(category),
        selected: isSelected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        onSelected: (_) {
          setState(() {
            selectedCategory = category;
          });
        },
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) {
        setState(() {
          searchQuery = value;
        });
      },
      decoration: InputDecoration(
        hintText: 'Rechercher une recette...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: searchQuery.isEmpty
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

  Widget _recipeCard(Map<String, dynamic> recipe, int realIndex) {
    final categories = List<String>.from(recipe['categories'] as List? ?? []);
    final isFavorite = recipe['isFavorite'] as bool? ?? false;
    final imageUrl = recipe['imageUrl'] as String? ?? '';
    final imageData = recipe['imageData'] as String? ?? '';

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFEDE7E1)),
        ),
      ),
      child: InkWell(
        onTap: () async {
          await RecipeStore.markRecipeOpened(recipe);
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecipeDetailPage(
                title: recipe['title'] as String,
                description: recipe['description'] as String,
                imageUrl: imageUrl,
                imageData: imageData,
                ingredients: List<Map<String, dynamic>>.from(
                  recipe['ingredients'] as List,
                ),
                instructions: List<String>.from(
                  recipe['instructions'] as List,
                ),
                prepTime: recipe['prepTime'] as String,
                cookTime: recipe['cookTime'] as String,
                servings: recipe['servings'] as int,
                categories: categories,
                isFavorite: isFavorite,
                notes: recipe['notes'] as String? ?? '',
                timerDefaults: List<Map<String, dynamic>>.from(
                  recipe['timerDefaults'] as List? ?? [],
                ),
                onFavoriteChanged: (value) async {
                  if (!mounted || realIndex >= recipes.length) return;

                  setState(() {
                    recipes[realIndex]['isFavorite'] = value;
                  });

                  await _saveRecipes();
                },
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              RecipeListThumbnail(imageUrl: imageUrl, imageData: imageData),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe['title'] as String? ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F1A17),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${recipe['prepTime']} • ${recipe['cookTime']} • ${recipe['servings']} portions',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6A6058),
                      ),
                    ),
                    if (categories.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        categories.take(3).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8A7A6E),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _toggleFavorite(realIndex),
                    tooltip: isFavorite ? 'Retirer des favoris' : 'Favori',
                    style: IconButton.styleFrom(
                      foregroundColor: isFavorite
                          ? const Color(0xFFB45309)
                          : const Color(0xFF9A9088),
                      minimumSize: const Size.square(34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(
                      isFavorite ? Icons.star_rounded : Icons.star_border,
                      size: 19,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Actions',
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      size: 20,
                      color: Color(0xFF8A7A6E),
                    ),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editRecipe(realIndex);
                      } else if (value == 'delete') {
                        _deleteRecipe(realIndex);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('Modifier'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Supprimer'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = _allCategories();
    final visibleRecipes = _filteredAndSortedRecipes();
    final hasActiveFilter =
        searchQuery.trim().isNotEmpty || selectedCategory != 'toutes';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        centerTitle: true,
        title: _titleWithAdd(),
        backgroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _searchField(),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: categories.map(_categoryChip).toList(),
            ),
          ),
          const SizedBox(height: 10),
          _RecipeListSummary(
            visibleCount: visibleRecipes.length,
            totalCount: recipes.length,
            hasActiveFilter: hasActiveFilter,
          ),
          const SizedBox(height: 6),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 22),
              child: Text(
                'Préparation de la liste...',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8A7A6E),
                ),
              ),
            )
          else if (visibleRecipes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Text(
                hasActiveFilter
                    ? 'Aucune recette ne correspond.'
                    : 'Aucune recette pour le moment.',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6A6058),
                ),
              ),
            )
          else
            ...visibleRecipes.map((item) {
              final recipe = item['recipe'] as Map<String, dynamic>;
              final realIndex = item['index'] as int;
              return _recipeCard(recipe, realIndex);
            }),
        ],
      ),
    );
  }
}

class RecipeListThumbnail extends StatelessWidget {
  const RecipeListThumbnail({
    super.key,
    required this.imageUrl,
    required this.imageData,
  });

  final String imageUrl;
  final String imageData;

  Widget _placeholderThumb() {
    return Container(
      width: 48,
      height: 48,
      color: const Color(0xFFF6F1EB),
      child: const Icon(
        Icons.menu_book_outlined,
        size: 18,
        color: Color(0xFF8A7A6E),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = imageUrl.trim();
    final data = imageData.trim();
    final imageSource = resolveRecipeImageSource(path, data);

    debugPrint('Recipe image import: list imageUrl loaded "$imageUrl"');

    final child = switch (imageSource) {
      RecipeImageSource.network => _buildNetworkImage(path),
      RecipeImageSource.memory => _buildMemoryImage(data),
      RecipeImageSource.placeholder => _placeholderThumb(),
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 48,
        height: 48,
        child: child,
      ),
    );
  }

  Widget _buildNetworkImage(String path) {
    debugPrintRecipeNetworkImageUrl('list', path);
    return Image.network(
      path,
      key: ValueKey(path),
      width: 48,
      height: 48,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        debugPrintRecipeNetworkImageError('list', path, error, stackTrace);
        return buildRecipeNetworkImageErrorBox(
          imageUrl: path,
          error: error,
          width: 48,
          height: 48,
          titleFontSize: 7,
          bodyFontSize: 6,
          padding: const EdgeInsets.all(3),
          icon: Icons.error_outline,
        );
      },
    );
  }

  Widget _buildMemoryImage(String data) {
    try {
      final bytes = base64Decode(data);
      debugPrint(
        'Recipe image import: list image decoded length=${bytes.length}',
      );
      return Image.memory(
        Uint8List.fromList(bytes),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame != null || wasSynchronouslyLoaded) {
            debugPrint('Recipe image import: list image displayed');
          }
          return child;
        },
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Recipe image import: list image display failed $error');
          debugPrintStack(stackTrace: stackTrace);
          return _placeholderThumb();
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Recipe image import: list image decode failed $error');
      debugPrintStack(stackTrace: stackTrace);
      return _placeholderThumb();
    }
  }
}

class _RecipeListSummary extends StatelessWidget {
  const _RecipeListSummary({
    required this.visibleCount,
    required this.totalCount,
    required this.hasActiveFilter,
  });

  final int visibleCount;
  final int totalCount;
  final bool hasActiveFilter;

  @override
  Widget build(BuildContext context) {
    final label = hasActiveFilter
        ? '$visibleCount résultat${visibleCount > 1 ? 's' : ''}'
        : '$totalCount recette${totalCount > 1 ? 's' : ''}';

    return Row(
      children: [
        const Icon(
          Icons.tune_rounded,
          size: 16,
          color: Color(0xFF8A7A6E),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6A6058),
          ),
        ),
      ],
    );
  }
}
