import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/recipe_image_source.dart';
import '../widgets/inline_timer_card.dart';
import '../widgets/recipe_network_image_diagnostics.dart';

class RecipeDetailPage extends StatefulWidget {
  final String title;
  final String description;
  final String imageUrl;
  final String imageData;
  final List<Map<String, dynamic>> ingredients;
  final List<String> instructions;
  final String prepTime;
  final String cookTime;
  final int servings;
  final List<String> categories;
  final bool isFavorite;
  final String notes;
  final List<Map<String, dynamic>> timerDefaults;
  final ValueChanged<bool>? onFavoriteChanged;

  const RecipeDetailPage({
    super.key,
    required this.title,
    required this.description,
    required this.imageUrl,
    this.imageData = '',
    required this.ingredients,
    required this.instructions,
    required this.prepTime,
    required this.cookTime,
    required this.servings,
    this.categories = const [],
    this.isFavorite = false,
    this.notes = '',
    this.timerDefaults = const [],
    this.onFavoriteChanged,
  });

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  late int currentServings;
  late bool isFavorite;

  @override
  void initState() {
    super.initState();
    currentServings = widget.servings;
    isFavorite = widget.isFavorite;
    debugPrint(
      'Recipe image import: detail imageUrl loaded "${widget.imageUrl}"',
    );
  }

  double _scaledQuantity(num baseQuantity) {
    final baseServings = widget.servings <= 0 ? 1 : widget.servings;
    return baseQuantity * currentServings / baseServings;
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    if ((value * 10).roundToDouble() == value * 10) {
      return value.toStringAsFixed(1);
    }

    return value.toStringAsFixed(2);
  }

  String _formatIngredientAmount(num baseQuantity, String unit) {
    final scaled = _scaledQuantity(baseQuantity);
    final normalizedUnit = _normalizeIngredientUnit(unit);

    if (normalizedUnit == 'g' && scaled >= 1000) {
      final kg = scaled / 1000;
      return '${_formatNumber(kg)} kg';
    }

    if (normalizedUnit == 'ml' && scaled >= 1000) {
      final liters = scaled / 1000;
      return '${_formatNumber(liters)} l';
    }

    return '${_formatNumber(scaled)} $normalizedUnit'.trim();
  }

  String _formatIngredientLine(Map<String, dynamic> ingredient) {
    final name = ingredient['name'] as String? ?? '';
    final quantity = ingredient['quantity'] as num? ?? 0;
    final unit = ingredient['unit'] as String? ?? '';

    if (quantity <= 0) {
      return name;
    }

    return '${_formatIngredientAmount(quantity, unit)} $name'.trim();
  }

  String _normalizeIngredientUnit(String unit) {
    final normalized = unit.trim().toLowerCase();
    final comparable = normalized
        .replaceAll(RegExp(r'[àáâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e');

    if (RegExp(r'^cuilleres?(?: a soupe)?$').hasMatch(comparable) ||
        comparable == 'cas') {
      return 'càs';
    }

    if (RegExp(r'^cuilleres? a cafe$').hasMatch(comparable) ||
        comparable == 'cac') {
      return 'càc';
    }

    if (RegExp(r'^grammes?$').hasMatch(comparable)) {
      return 'g';
    }

    return unit.trim();
  }

  Widget _metadataItem(IconData icon, String label, String value) {
    final displayValue = value.trim().isEmpty ? '—' : value.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F5F1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE9DDD0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF8A7D72)),
          const SizedBox(width: 7),
          Text(
            '$label ',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF8A7D72),
            ),
          ),
          Text(
            displayValue,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF3B332E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(String category) {
    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF5F0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        category,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF526B57),
        ),
      ),
    );
  }

  Widget _favoriteBadge() {
    if (!isFavorite) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.star,
            size: 16,
            color: Colors.amber,
          ),
          SizedBox(width: 6),
          Text(
            'Favori',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF6A6058),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleFavorite() {
    final nextValue = !isFavorite;

    setState(() {
      isFavorite = nextValue;
    });

    widget.onFavoriteChanged?.call(nextValue);
  }

  Widget _buildRecipeImage() {
    final data = widget.imageData.trim();
    final url = widget.imageUrl.trim();
    final imageSource = resolveRecipeImageSource(url, data);

    if (imageSource == RecipeImageSource.network) {
      debugPrintRecipeNetworkImageUrl('detail', url);
      return Image.network(
        url,
        key: ValueKey(url),
        height: 260,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrintRecipeNetworkImageError('detail', url, error, stackTrace);
          return buildRecipeNetworkImageErrorBox(
            imageUrl: url,
            error: error,
            height: 260,
            titleFontSize: 12,
            bodyFontSize: 10,
            padding: const EdgeInsets.all(10),
            icon: Icons.image_not_supported,
          );
        },
      );
    }

    if (imageSource == RecipeImageSource.memory) {
      try {
        final bytes = base64Decode(data);
        debugPrint(
          'Recipe image import: detail image decoded length=${bytes.length}',
        );
        return Image.memory(
          Uint8List.fromList(bytes),
          height: 260,
          width: double.infinity,
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null || wasSynchronouslyLoaded) {
              debugPrint('Recipe image import: detail image displayed');
            }
            return child;
          },
          errorBuilder: (context, error, stackTrace) {
            debugPrint(
              'Recipe image import: detail image display failed $error',
            );
            debugPrintStack(stackTrace: stackTrace);
            return Container(
              height: 260,
              width: double.infinity,
              color: const Color(0xFFF4E4C8),
              child: const Icon(Icons.image_not_supported),
            );
          },
        );
      } catch (error, stackTrace) {
        debugPrint('Recipe image import: detail image decode failed $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    return Container(
      height: 260,
      width: double.infinity,
      color: const Color(0xFFF4E4C8),
      child: const Icon(Icons.image_not_supported),
    );
  }

  Widget _sectionDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 22),
      child: Divider(height: 1, color: Color(0xFFE9DDD0)),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: Color(0xFF1F1A17),
      ),
    );
  }

  Widget _ingredientLine(String line) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 9),
            child: SizedBox(
              width: 6,
              height: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFD97706),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              line,
              style: const TextStyle(
                fontSize: 16,
                height: 1.45,
                color: Color(0xFF3B332E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _servingsControl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Portions',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3B332E),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: currentServings > 1
                  ? () {
                      setState(() {
                        currentServings--;
                      });
                    }
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 34,
              child: Text(
                '$currentServings',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() {
                  currentServings++;
                });
              },
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          children: [
            _portionQuickButton(1),
            _portionQuickButton(2),
            _portionQuickButton(4),
            _portionQuickButton(8),
            _portionQuickButton(12),
            _portionQuickButton(20),
          ],
        ),
      ],
    );
  }

  Widget _portionQuickButton(int value) {
    final isSelected = currentServings == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            currentServings = value;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFD97706) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFD97706)
                  : const Color(0xFFE9DDD0),
            ),
          ),
          child: Text(
            '$value',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : const Color(0xFF6A6058),
            ),
          ),
        ),
      ),
    );
  }

  List<TimerPreset> _timerPresets() {
    return widget.timerDefaults
        .map((timerDefault) {
          final label = timerDefault['label']?.toString().trim() ?? '';
          final durationSeconds = timerDefault['durationSeconds'];
          final seconds = durationSeconds is num
              ? durationSeconds.toInt()
              : int.tryParse(durationSeconds?.toString() ?? '');

          if (label.isEmpty || seconds == null || seconds <= 0) {
            return null;
          }

          return TimerPreset(
            label: label,
            duration: Duration(seconds: seconds),
          );
        })
        .whereType<TimerPreset>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedDescription = widget.description.trim();
    final normalizedNotes = widget.notes.trim();

    final hasDescription = normalizedDescription.isNotEmpty &&
        normalizedDescription.toLowerCase() != 'pas encore de description.';

    final hasNotes = normalizedNotes.isNotEmpty;
    final hasIngredients = widget.ingredients.isNotEmpty;
    final hasInstructions = widget.instructions.isNotEmpty;
    final timerPresets = _timerPresets();
    final hasImage =
        widget.imageData.trim().isNotEmpty || widget.imageUrl.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recette'),
        actions: [
          IconButton(
            tooltip: isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
            onPressed: _toggleFavorite,
            icon: Icon(
              isFavorite ? Icons.star : Icons.star_border,
              color: isFavorite ? Colors.amber.shade700 : null,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildRecipeImage(),
                    ),
                  if (hasImage) const SizedBox(height: 20),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 34,
                      height: 1.12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F1A17),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _favoriteBadge(),
                      if (widget.categories.isNotEmpty)
                        ...widget.categories.map(_categoryChip),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _metadataItem(Icons.schedule_outlined, 'Préparation',
                          widget.prepTime),
                      _metadataItem(Icons.local_fire_department_outlined,
                          'Cuisson', widget.cookTime),
                      _metadataItem(
                          Icons.people_outline, 'Portions', '$currentServings'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (hasDescription)
                    Text(
                      normalizedDescription,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: Color(0xFF3B332E),
                      ),
                    ),
                  const SizedBox(height: 20),
                  _servingsControl(),
                  if (hasIngredients) _sectionDivider(),
                  if (hasIngredients) _sectionTitle('Ingrédients'),
                  if (hasIngredients) const SizedBox(height: 16),
                  ...widget.ingredients.map((ingredient) =>
                      _ingredientLine(_formatIngredientLine(ingredient))),
                  if (hasInstructions) _sectionDivider(),
                  if (hasInstructions) _sectionTitle('Préparation'),
                  if (hasInstructions) const SizedBox(height: 16),
                  ...widget.instructions.asMap().entries.map((entry) {
                    final index = entry.key + 1;
                    final step = entry.value;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 22),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 34,
                            child: Text(
                              '$index.',
                              style: const TextStyle(
                                fontSize: 17,
                                height: 1.55,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFD97706),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              step,
                              style: const TextStyle(
                                fontSize: 17,
                                height: 1.55,
                                color: Color(0xFF2B2521),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (hasNotes) _sectionDivider(),
                  if (hasNotes) _sectionTitle('Notes'),
                  if (hasNotes) const SizedBox(height: 12),
                  if (hasNotes)
                    Text(
                      normalizedNotes,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.55,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF6A6058),
                      ),
                    ),
                  if (timerPresets.isNotEmpty) _sectionDivider(),
                  if (timerPresets.isNotEmpty) _sectionTitle('Minuteur'),
                  if (timerPresets.isNotEmpty) const SizedBox(height: 12),
                  if (timerPresets.isNotEmpty)
                    InlineTimerCard(
                      title: widget.title,
                      presets: timerPresets,
                      showCustomDuration: false,
                      compact: true,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
