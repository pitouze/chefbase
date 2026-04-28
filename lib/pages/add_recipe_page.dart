import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/backend_recipe_importer.dart';
import '../services/recipe_image_source.dart';
import '../services/recipe_url_importer.dart';
import '../widgets/recipe_network_image_diagnostics.dart';

class AddRecipePage extends StatefulWidget {
  final Map<String, dynamic>? initialRecipe;
  final RecipeUrlImporter? recipeUrlImporter;
  final BackendRecipeImporter? backendRecipeImporter;

  const AddRecipePage({
    super.key,
    this.initialRecipe,
    this.recipeUrlImporter,
    this.backendRecipeImporter,
  });

  @override
  State<AddRecipePage> createState() => _AddRecipePageState();
}

class _AddRecipePageState extends State<AddRecipePage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _notesController;
  late final TextEditingController _prepTimeController;
  late final TextEditingController _cookTimeController;
  late final TextEditingController _servingsController;
  late final TextEditingController _importUrlController;
  late final TextEditingController _imageUrlController;

  final List<Map<String, TextEditingController>> ingredientControllers = [];
  final List<TextEditingController> instructionControllers = [];

  bool isFavorite = false;
  String imageBase64 = '';
  bool _debugLoggedPreviewFrame = false;
  String _lastImageUrlValue = '';
  bool _isImportingFromUrl = false;
  bool _hasImportedRecipe = false;
  String? _urlImportMessage;

  late final BackendRecipeImporter _backendRecipeImporter;

  final List<String> availableCategories = [
    'entrée',
    'plat',
    'dessert',
    'poisson',
    'viande',
    'volaille',
    'légumes',
    'pain',
    'biscuit',
    'tarte',
    'accompagnement',
    'sauce',
    'pâte',
    'brunch',
    'apéritif',
    'snack',
  ];

  final Set<String> selectedCategories = {};

  @override
  void initState() {
    super.initState();

    _backendRecipeImporter =
        widget.backendRecipeImporter ?? BackendRecipeImporter();

    final recipe = widget.initialRecipe;

    _titleController =
        TextEditingController(text: recipe?['title'] as String? ?? '');
    _descriptionController =
        TextEditingController(text: recipe?['description'] as String? ?? '');
    _notesController =
        TextEditingController(text: recipe?['notes'] as String? ?? '');
    _prepTimeController =
        TextEditingController(text: recipe?['prepTime'] as String? ?? '');
    _cookTimeController =
        TextEditingController(text: recipe?['cookTime'] as String? ?? '');
    _servingsController = TextEditingController(
      text: ((recipe?['servings'] as int?) ?? 4).toString(),
    );
    _importUrlController = TextEditingController();
    _imageUrlController = TextEditingController(
      text: recipe?['imageUrl'] as String? ?? '',
    );
    _lastImageUrlValue = _imageUrlController.text.trim();
    _imageUrlController.addListener(_handleImageUrlChanged);

    imageBase64 = recipe?['imageData'] as String? ?? '';

    final ingredients =
        List<Map<String, dynamic>>.from(recipe?['ingredients'] as List? ?? []);
    if (ingredients.isEmpty) {
      _addIngredientRow();
    } else {
      for (final ingredient in ingredients) {
        _addIngredientRow(
          name: ingredient['name'] as String? ?? '',
          quantity: '${ingredient['quantity'] ?? ''}',
          unit: ingredient['unit'] as String? ?? '',
        );
      }
    }

    final instructions =
        List<String>.from(recipe?['instructions'] as List? ?? []);
    if (instructions.isEmpty) {
      _addInstructionRow();
    } else {
      for (final step in instructions) {
        _addInstructionRow(text: step);
      }
    }

    isFavorite = recipe?['isFavorite'] as bool? ?? false;

    final categories =
        List<String>.from(recipe?['categories'] as List? ?? ['plat']);
    selectedCategories.addAll(categories);
    if (selectedCategories.isEmpty) {
      selectedCategories.add('plat');
    }
  }

  void _addIngredientRow({
    String name = '',
    String quantity = '',
    String unit = '',
  }) {
    ingredientControllers.add({
      'name': TextEditingController(text: name),
      'quantity': TextEditingController(text: quantity),
      'unit': TextEditingController(text: unit),
    });
  }

  void _removeIngredientRow(int index) {
    final row = ingredientControllers[index];
    row['name']?.dispose();
    row['quantity']?.dispose();
    row['unit']?.dispose();
    ingredientControllers.removeAt(index);
  }

  void _addInstructionRow({String text = ''}) {
    instructionControllers.add(TextEditingController(text: text));
  }

  void _removeInstructionRow(int index) {
    instructionControllers[index].dispose();
    instructionControllers.removeAt(index);
  }

  String get _rawImageUrl => _imageUrlController.text;
  String get _normalizedImageUrl => _imageUrlController.text.trim();

  void _handleImageUrlChanged() {
    final rawValue = _rawImageUrl;
    final nextValue = rawValue.trim();
    final previousValue = _lastImageUrlValue;
    final changed = rawValue != previousValue;
    final shouldClearStoredImage =
        nextValue.isNotEmpty && changed && imageBase64.isNotEmpty;

    _lastImageUrlValue = rawValue;

    debugPrint('Recipe image import: imageUrl entered "$rawValue"');

    if (!changed && !shouldClearStoredImage) {
      return;
    }

    if (!mounted) return;

    setState(() {
      if (shouldClearStoredImage) {
        imageBase64 = '';
      }
      _debugLoggedPreviewFrame = false;
    });
  }

  bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _pickImageForOtherPlatforms() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'images',
            extensions: ['jpg', 'jpeg', 'png', 'heic', 'heif', 'webp'],
            uniformTypeIdentifiers: ['public.image'],
          ),
        ],
      );
      if (file == null) {
        debugPrint('Recipe image import: picker closed without selection');
        return;
      }

      final bytes = file.path.isNotEmpty
          ? await File(file.path).readAsBytes()
          : await file.readAsBytes();
      if (bytes.isEmpty) {
        debugPrint('Recipe image import: selected image had no bytes');
        return;
      }

      final encoded = base64Encode(bytes);
      debugPrint(
        'Recipe image import: image saved to form bytes=${bytes.length} '
        'base64Length=${encoded.length}',
      );

      setState(() {
        imageBase64 = encoded;
        _imageUrlController.clear();
        _debugLoggedPreviewFrame = false;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Recipe image import: failed exactException=${error.runtimeType}: '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'importer cette image.")),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _prepTimeController.dispose();
    _cookTimeController.dispose();
    _servingsController.dispose();
    _importUrlController.dispose();
    _imageUrlController.removeListener(_handleImageUrlChanged);
    _imageUrlController.dispose();

    for (final row in ingredientControllers) {
      row['name']?.dispose();
      row['quantity']?.dispose();
      row['unit']?.dispose();
    }

    for (final controller in instructionControllers) {
      controller.dispose();
    }

    super.dispose();
  }

  List<Map<String, dynamic>> _buildIngredients() {
    return ingredientControllers
        .map((row) {
          final name = row['name']!.text.trim();
          final quantityRaw = row['quantity']!.text.trim();
          final unit = row['unit']!.text.trim();

          if (name.isEmpty && quantityRaw.isEmpty && unit.isEmpty) {
            return null;
          }

          return {
            'name': name,
            'quantity': double.tryParse(quantityRaw.replaceAll(',', '.')) ?? 0,
            'unit': unit,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<String> _buildInstructions() {
    return instructionControllers
        .map((controller) => controller.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final createdAt = widget.initialRecipe?['createdAt'] ??
        DateTime.now().millisecondsSinceEpoch;
    final imageUrl = _rawImageUrl;

    final recipe = {
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'notes': _notesController.text.trim(),
      'imageUrl': imageUrl,
      'imageData': imageBase64,
      'ingredients': _buildIngredients(),
      'instructions': _buildInstructions(),
      'prepTime': _prepTimeController.text.trim().isEmpty
          ? '-'
          : _prepTimeController.text.trim(),
      'cookTime': _cookTimeController.text.trim().isEmpty
          ? '-'
          : _cookTimeController.text.trim(),
      'servings': int.tryParse(_servingsController.text.trim()) ?? 1,
      'categories': selectedCategories.isEmpty
          ? <String>['plat']
          : selectedCategories.toList(),
      'isFavorite': isFavorite,
      'createdAt': createdAt,
    };

    debugPrint(
      'Recipe image import: imageUrl saved "$imageUrl" '
      'hasImage=${imageBase64.isNotEmpty} base64Length=${imageBase64.length}',
    );
    if (_hasImportedRecipe) {
      debugPrint(
        'saved imported recipe imageUrl: '
        '${imageUrl.trim().isNotEmpty ? 'present' : 'absent'}',
      );
    }

    Navigator.pop(context, recipe);
  }

  Future<void> _importFromUrl() async {
    final url = _importUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoute une URL avant l’import.')),
      );
      return;
    }

    setState(() {
      _isImportingFromUrl = true;
      _urlImportMessage = null;
    });

    try {
      final imported = await _importRecipeFromUrl(url);
      if (!mounted) return;

      _applyImportedRecipe(imported);
      setState(() {
        _urlImportMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recette importée. Vérifie puis enregistre.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = 'Backend erreur: $error';
      setState(() {
        _urlImportMessage = '$message\nL’URL reste en place pour continuer.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isImportingFromUrl = false;
      });
    }
  }

  Future<ImportedRecipeData> _importRecipeFromUrl(String url) async {
    return _backendRecipeImporter.importFromUrl(url);
  }

  void _applyImportedRecipe(ImportedRecipeData imported) {
    _titleController.text = imported.title ?? _titleController.text;
    _descriptionController.text =
        imported.description ?? _descriptionController.text;
    _notesController.text = imported.notes ?? _notesController.text;
    _prepTimeController.text = imported.prepTime ?? _prepTimeController.text;
    _cookTimeController.text = imported.cookTime ?? _cookTimeController.text;

    if (imported.servings != null) {
      _servingsController.text = imported.servings!.toString();
    }

    _hasImportedRecipe = true;

    if ((imported.imageUrl?.isNotEmpty ?? false)) {
      _imageUrlController.text = imported.imageUrl!;
      imageBase64 = '';
    }

    if (imported.ingredients.isNotEmpty) {
      for (final row in ingredientControllers) {
        row['name']?.dispose();
        row['quantity']?.dispose();
        row['unit']?.dispose();
      }
      ingredientControllers.clear();
      for (final ingredient in imported.ingredients) {
        _addIngredientRow(
          name: ingredient['name']?.toString() ?? '',
          quantity: _formatImportedQuantity(ingredient['quantity']),
          unit: ingredient['unit']?.toString() ?? '',
        );
      }
    }

    if (imported.instructions.isNotEmpty) {
      for (final controller in instructionControllers) {
        controller.dispose();
      }
      instructionControllers.clear();
      for (final step in imported.instructions) {
        _addInstructionRow(text: step);
      }
    }

    if (imported.categories.isNotEmpty) {
      selectedCategories
        ..clear()
        ..addAll(imported.categories);
    }

    setState(() {
      _debugLoggedPreviewFrame = false;
    });
  }

  String _formatImportedQuantity(dynamic value) {
    if (value is num && value > 0) {
      if (value == value.roundToDouble()) {
        return value.toInt().toString();
      }
      return value.toString();
    }
    return '';
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE9DDD0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE9DDD0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFD97706)),
          ),
        ),
      ),
    );
  }

  Widget _categorySelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Catégories',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: availableCategories.map((category) {
              final isSelected = selectedCategories.contains(category);

              return FilterChip(
                label: Text(category),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      selectedCategories.add(category);
                    } else {
                      selectedCategories.remove(category);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _urlImportSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF6),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFEFD9BF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Importer depuis URL',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Colle un lien de recette pour préremplir le formulaire avant enregistrement.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6A6058),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            _field(
              'URL recette',
              _importUrlController,
              hint: 'https://exemple.com/recette',
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isImportingFromUrl ? null : _importFromUrl,
                icon: _isImportingFromUrl
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded),
                label: Text(
                  _isImportingFromUrl
                      ? 'Import en cours… le serveur peut mettre quelques secondes à se réveiller.'
                      : 'Importer depuis URL',
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Backend: configurable avec CHEFBASE_BACKEND_URL',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF6A6058),
                height: 1.3,
              ),
            ),
            if (_urlImportMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF3D3A1)),
                ),
                child: Text(
                  _urlImportMessage!,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Color(0xFF7C4A03),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _imageSection() {
    final imageUrl = _normalizedImageUrl;
    final hasAnyImage = imageBase64.isNotEmpty || imageUrl.isNotEmpty;
    final imageSource = resolveRecipeImageSource(imageUrl, imageBase64);

    Uint8List? selectedImageBytes;
    if (imageSource == RecipeImageSource.memory) {
      try {
        selectedImageBytes = Uint8List.fromList(base64Decode(imageBase64));
        debugPrint(
          'Recipe image import: preview bytes decoded '
          'length=${selectedImageBytes.length}',
        );
      } catch (error, stackTrace) {
        debugPrint('Recipe image import: preview decode failed $error');
        debugPrintStack(stackTrace: stackTrace);
        selectedImageBytes = null;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Image',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (!_isIos)
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _pickImageForOtherPlatforms,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choisir une image'),
                ),
                const SizedBox(width: 10),
                if (hasAnyImage)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        imageBase64 = '';
                        _imageUrlController.clear();
                        _debugLoggedPreviewFrame = false;
                      });
                    },
                    child: const Text('Retirer'),
                  ),
              ],
            ),
          if (_isIos)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF3D3A1)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: Color(0xFFB45309),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Ajout photo iPhone en cours d’amélioration. Utilisez une URL d’image pour le moment.",
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Color(0xFF7C4A03),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!_isIos) const SizedBox(height: 10),
          if (imageSource == RecipeImageSource.network)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Builder(
                  builder: (context) {
                    debugPrintRecipeNetworkImageUrl('preview', imageUrl);
                    return Image.network(
                      imageUrl,
                      key: ValueKey(imageUrl),
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      frameBuilder:
                          (context, child, frame, wasSynchronouslyLoaded) {
                        if ((frame != null || wasSynchronouslyLoaded) &&
                            !_debugLoggedPreviewFrame) {
                          _debugLoggedPreviewFrame = true;
                          debugPrint(
                              'Recipe image import: image URL displayed');
                        }
                        return child;
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) {
                          return child;
                        }

                        return Container(
                          height: 150,
                          width: double.infinity,
                          color: const Color(0xFFF6F1EB),
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        debugPrintRecipeNetworkImageError(
                          'preview',
                          imageUrl,
                          error,
                          stackTrace,
                        );
                        return buildRecipeNetworkImageErrorBox(
                          imageUrl: imageUrl,
                          error: error,
                          width: double.infinity,
                          height: 150,
                          titleFontSize: 12,
                          bodyFontSize: 10,
                          padding: const EdgeInsets.all(10),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          if (selectedImageBytes != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  selectedImageBytes,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                    if ((frame != null || wasSynchronouslyLoaded) &&
                        !_debugLoggedPreviewFrame) {
                      _debugLoggedPreviewFrame = true;
                      debugPrint('Recipe image import: image displayed');
                    }
                    return child;
                  },
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint(
                      'Recipe image import: preview display failed $error',
                    );
                    debugPrintStack(stackTrace: stackTrace);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          _field(
            'Image URL',
            _imageUrlController,
            hint: _isIos ? 'https://exemple.com/image.jpg' : 'Optionnel',
          ),
          if (_isIos && hasAnyImage)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    imageBase64 = '';
                    _imageUrlController.clear();
                    _debugLoggedPreviewFrame = false;
                  });
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Retirer l’image'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF8A7D72),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ingredientSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Ingrédients',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _addIngredientRow();
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('Ajouter'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...List.generate(ingredientControllers.length, (index) {
            final row = ingredientControllers[index];

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE9DDD0)),
              ),
              child: Column(
                children: [
                  _field(
                    'Nom',
                    row['name']!,
                    hint: 'ex: beurre',
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          'Quantité',
                          row['quantity']!,
                          hint: 'ex: 120',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(
                          'Unité',
                          row['unit']!,
                          hint: 'ex: g',
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: ingredientControllers.length > 1
                          ? () {
                              setState(() {
                                _removeIngredientRow(index);
                              });
                            }
                          : null,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Supprimer'),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _instructionSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Étapes',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _addInstructionRow();
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('Ajouter'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...List.generate(instructionControllers.length, (index) {
            final controller = instructionControllers[index];

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE9DDD0)),
              ),
              child: Column(
                children: [
                  TextFormField(
                    controller: controller,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Étape ${index + 1}',
                      hintText: 'Décris cette étape',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFFE9DDD0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFFE9DDD0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFFD97706)),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: instructionControllers.length > 1
                          ? () {
                              setState(() {
                                _removeInstructionRow(index);
                              });
                            }
                          : null,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Supprimer'),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialRecipe != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Modifier la recette' : 'Ajouter une recette'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!isEditing) _urlImportSection(),
            _field(
              'Titre',
              _titleController,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Titre obligatoire' : null,
            ),
            _field(
              'Description',
              _descriptionController,
              maxLines: 3,
              hint: 'Optionnel',
            ),
            _field(
              'Notes chef',
              _notesController,
              maxLines: 4,
              hint:
                  'Ex: à servir très chaud, monter un peu plus au beurre, cuisson testée à 170°C...',
            ),
            Row(
              children: [
                Expanded(
                  child: _field(
                    'Préparation',
                    _prepTimeController,
                    hint: 'Optionnel',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    'Cuisson',
                    _cookTimeController,
                    hint: 'Optionnel',
                  ),
                ),
              ],
            ),
            _field(
              'Portions',
              _servingsController,
              keyboardType: TextInputType.number,
              hint: 'Optionnel',
            ),
            _imageSection(),
            _categorySelector(),
            _ingredientSection(),
            _instructionSection(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: isFavorite,
              onChanged: (value) {
                setState(() {
                  isFavorite = value;
                });
              },
              title: const Text('Ajouter aux favoris'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              key: const ValueKey('saveRecipeButton'),
              onPressed: _submit,
              icon: const Icon(Icons.save),
              label: Text(isEditing
                  ? 'Enregistrer les modifications'
                  : 'Enregistrer la recette'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
