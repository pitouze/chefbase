import 'package:flutter/material.dart';
import '../widgets/inline_timer_card.dart';

class SousVideDetailPage extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const SousVideDetailPage({
    super.key,
    required this.item,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  Widget _infoCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F3EE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6A6058),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value.isEmpty ? '—' : value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F1A17),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9DDD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F1A17),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              height: 1.45,
              color: Color(0xFF3B332E),
            ),
          ),
        ],
      ),
    );
  }

  List<TimerPreset> _timerPresets() {
    final timerDefaults = item['timerDefaults'];
    if (timerDefaults is! List) {
      return const [];
    }

    return timerDefaults
        .whereType<Map>()
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
    final title = item['title'] as String? ?? '';
    final category = item['siteCategory'] as String? ?? '';
    final temp = item['temp'] as String? ?? '';
    final time = item['time'] as String? ?? '';
    final texture = item['texture'] as String? ?? '';
    final note = item['note'] as String? ?? '';
    final weight = item['weight'] as String? ?? '';
    final finish = item['finish'] as String? ?? '';
    final timerPresets = _timerPresets();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail sous-vide'),
        actions: [
          IconButton(
            onPressed: onToggleFavorite,
            icon: Icon(
              isFavorite ? Icons.star : Icons.star_border,
              color: isFavorite ? Colors.amber.shade700 : null,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F1A17),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F3EE),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  category,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6A6058),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _infoCard('Température', temp)),
              const SizedBox(width: 12),
              Expanded(child: _infoCard('Temps', time)),
            ],
          ),
          if (timerPresets.isNotEmpty) const SizedBox(height: 18),
          if (timerPresets.isNotEmpty)
            InlineTimerCard(
              title: title,
              presets: timerPresets,
              showCustomDuration: false,
            ),
          if (weight.trim().isNotEmpty || finish.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (weight.trim().isNotEmpty)
                  Expanded(child: _infoCard('Poids / épaisseur', weight)),
                if (weight.trim().isNotEmpty && finish.trim().isNotEmpty)
                  const SizedBox(width: 12),
                if (finish.trim().isNotEmpty)
                  Expanded(child: _infoCard('Saisir / finition', finish)),
              ],
            ),
          ],
          if (texture.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            _sectionCard('Texture', texture),
          ],
          if (note.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            _sectionCard('Note', note),
          ],
        ],
      ),
    );
  }
}
