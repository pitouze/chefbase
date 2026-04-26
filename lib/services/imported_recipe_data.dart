class ImportedRecipeData {
  final String? title;
  final String? description;
  final List<Map<String, dynamic>> ingredients;
  final List<String> instructions;
  final String? prepTime;
  final String? cookTime;
  final int? servings;
  final String? imageUrl;
  final String? notes;
  final List<String> categories;

  const ImportedRecipeData({
    this.title,
    this.description,
    this.ingredients = const [],
    this.instructions = const [],
    this.prepTime,
    this.cookTime,
    this.servings,
    this.imageUrl,
    this.notes,
    this.categories = const [],
  });

  bool get hasAnyValue =>
      (title?.isNotEmpty ?? false) ||
      (description?.isNotEmpty ?? false) ||
      ingredients.isNotEmpty ||
      instructions.isNotEmpty ||
      (prepTime?.isNotEmpty ?? false) ||
      (cookTime?.isNotEmpty ?? false) ||
      servings != null ||
      (imageUrl?.isNotEmpty ?? false) ||
      (notes?.isNotEmpty ?? false) ||
      categories.isNotEmpty;

  ImportedRecipeData merge(ImportedRecipeData other) {
    return ImportedRecipeData(
      title: title ?? other.title,
      description: description ?? other.description,
      ingredients: ingredients.isNotEmpty ? ingredients : other.ingredients,
      instructions: instructions.isNotEmpty ? instructions : other.instructions,
      prepTime: prepTime ?? other.prepTime,
      cookTime: cookTime ?? other.cookTime,
      servings: servings ?? other.servings,
      imageUrl: imageUrl ?? other.imageUrl,
      notes: notes ?? other.notes,
      categories: categories.isNotEmpty ? categories : other.categories,
    );
  }
}
