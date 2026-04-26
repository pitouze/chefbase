enum RecipeImageSource {
  network,
  memory,
  placeholder,
}

bool hasHttpImageUrl(String value) {
  final normalized = value.trim();
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return false;
  }

  return uri.scheme == 'http' || uri.scheme == 'https';
}

RecipeImageSource resolveRecipeImageSource(String imageUrl, String imageData) {
  if (hasHttpImageUrl(imageUrl)) {
    return RecipeImageSource.network;
  }

  if (imageUrl.trim().isEmpty && imageData.trim().isNotEmpty) {
    return RecipeImageSource.memory;
  }

  return RecipeImageSource.placeholder;
}
