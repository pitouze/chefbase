import 'package:flutter/material.dart';

String _shortenDiagnosticText(String value, {int maxLength = 80}) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return '-';
  }

  if (normalized.length <= maxLength) {
    return normalized;
  }

  return '${normalized.substring(0, maxLength - 1)}…';
}

void debugPrintRecipeNetworkImageUrl(String contextLabel, String imageUrl) {
  debugPrint(
    'Recipe image import: $contextLabel imageUrl used '
    '"${_shortenDiagnosticText(imageUrl, maxLength: 140)}"',
  );
}

void debugPrintRecipeNetworkImageError(
  String contextLabel,
  String imageUrl,
  Object error,
  StackTrace? stackTrace,
) {
  debugPrint(
    'Recipe image import: $contextLabel Image.network error '
    '${_shortenDiagnosticText(error.toString(), maxLength: 180)}',
  );
  debugPrint(
    'Recipe image import: $contextLabel failed imageUrl '
    '"${_shortenDiagnosticText(imageUrl, maxLength: 140)}"',
  );
  if (stackTrace != null) {
    debugPrintStack(
      label: 'Recipe image import: $contextLabel stack trace',
      stackTrace: stackTrace,
    );
  }
}

Widget buildRecipeNetworkImageErrorBox({
  required String imageUrl,
  required Object error,
  double? width,
  double? height,
  double titleFontSize = 11,
  double bodyFontSize = 9,
  EdgeInsetsGeometry padding = const EdgeInsets.all(6),
  IconData icon = Icons.image_not_supported_outlined,
}) {
  return Container(
    width: width,
    height: height,
    padding: padding,
    color: const Color(0xFFFFF1F2),
    alignment: Alignment.center,
    child: DefaultTextStyle(
      style: TextStyle(
        fontSize: bodyFontSize,
        height: 1.2,
        color: const Color(0xFF9F1239),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: titleFontSize + 5, color: const Color(0xFFBE123C)),
          const SizedBox(height: 4),
          Text(
            'Image URL erreur',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: titleFontSize,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF881337),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _shortenDiagnosticText(error.toString()),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            _shortenDiagnosticText(imageUrl),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}
