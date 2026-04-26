import 'package:flutter/material.dart';
import '../widgets/inline_timer_card.dart';
import '../widgets/chefbase_list_tile.dart';

class TechniquesPage extends StatelessWidget {
  const TechniquesPage({super.key});

  static const List<Map<String, dynamic>> techniques = [
    {
      'title': 'Œuf poché parfait',
      'description': 'Blanc bien tenu, jaune coulant à tous les coups.',
      'category': 'Œufs',
      'time': '3 min',
      'difficulty': 'Facile',
      'steps': [
        'Porter une casserole d’eau à frémissement, sans gros bouillon.',
        'Ajouter un trait de vinaigre blanc pour aider le blanc à se tenir.',
        'Casser l’œuf dans un petit bol, puis créer un léger tourbillon.',
        'Glisser l’œuf au centre et cuire jusqu’à obtenir un blanc pris.',
        'Égoutter sur papier absorbant, puis assaisonner juste avant service.',
      ],
      'checkpoints': [
        'L’eau doit frémir doucement, pas bouillir fort.',
        'Le blanc enveloppe le jaune sans se disperser dans la casserole.',
        'Le jaune reste souple quand on touche l’œuf avec une cuillère.',
      ],
      'tips': [
        'Utiliser un œuf très frais change vraiment le résultat.',
        'Préparer un bol d’eau tiède si les œufs doivent attendre une minute.',
      ],
      'timerDefaults': [
        {'label': '2 min 30', 'durationSeconds': 150},
        {'label': '3 min', 'durationSeconds': 180},
      ],
    },
    {
      'title': 'Beurre blanc rattrapé',
      'description': 'Technique simple pour sauver une sauce tranchée.',
      'category': 'Sauces',
      'time': '5 min',
      'difficulty': 'Intermédiaire',
      'steps': [
        'Retirer immédiatement la casserole du feu.',
        'Verser une cuillère d’eau froide dans un bol propre.',
        'Ajouter la sauce tranchée petit à petit en fouettant vivement.',
        'Reprendre l’émulsion avec quelques dés de beurre froid si besoin.',
        'Remettre à température très douce, sans laisser bouillir.',
      ],
      'checkpoints': [
        'La sauce redevient brillante et nappante.',
        'Aucune poche de gras ne flotte en surface.',
        'Le fouet laisse une trace courte avant que la sauce se referme.',
      ],
      'tips': [
        'Toujours repartir dans un récipient propre et froid.',
        'Si la sauce chauffe trop, arrêter avant de corriger.',
      ],
    },
    {
      'title': 'Cuisson viande parfaite',
      'description': 'Base propre pour une cuisson régulière et maîtrisée.',
      'category': 'Viandes',
      'time': '20 min',
      'difficulty': 'Facile',
      'steps': [
        'Sortir la viande du réfrigérateur 20 à 30 minutes avant cuisson.',
        'Sécher la surface avec du papier absorbant.',
        'Assaisonner, puis marquer dans une poêle bien chaude.',
        'Baisser le feu pour finir la cuisson sans brûler les sucs.',
        'Laisser reposer avant de trancher pour garder le jus.',
      ],
      'checkpoints': [
        'La surface est bien sèche avant de toucher la poêle.',
        'La coloration est uniforme et franchement dorée.',
        'Le repos dure au moins la moitié du temps de cuisson.',
      ],
      'tips': [
        'Ne pas remplir la poêle, sinon la viande rend de l’eau.',
        'Trancher contre les fibres pour une texture plus tendre.',
      ],
      'timerDefaults': [
        {'label': 'Repos 5 min', 'durationSeconds': 300},
        {'label': 'Repos 10 min', 'durationSeconds': 600},
      ],
    },
    {
      'title': 'Légumes verts croquants',
      'description': 'Une cuisson nette avec couleur vive et texture précise.',
      'category': 'Légumes',
      'time': '6 min',
      'difficulty': 'Facile',
      'steps': [
        'Porter un grand volume d’eau salée à ébullition.',
        'Préparer un saladier d’eau froide avec des glaçons.',
        'Cuire les légumes jusqu’à ce qu’ils soient juste tendres.',
        'Refroidir aussitôt dans l’eau glacée pour fixer la couleur.',
        'Égoutter, puis réchauffer rapidement au beurre ou à l’huile d’olive.',
      ],
      'checkpoints': [
        'La couleur devient plus vive après la cuisson.',
        'Le cœur reste légèrement ferme sous la dent.',
        'Les légumes sont bien égouttés avant d’être réchauffés.',
      ],
      'tips': [
        'Saler l’eau franchement pour assaisonner dès la cuisson.',
        'Couper les morceaux à taille régulière pour une cuisson homogène.',
      ],
      'timerDefaults': [
        {'label': 'Haricots 4 min', 'durationSeconds': 240},
        {'label': 'Brocoli 3 min', 'durationSeconds': 180},
      ],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Techniques'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: techniques.map((technique) {
          return _TechniqueOverviewCard(
              technique: technique,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TechniqueDetailPage(technique: technique),
                  ),
                );
              });
        }).toList(),
      ),
    );
  }
}

class _TechniqueOverviewCard extends StatelessWidget {
  final Map<String, dynamic> technique;
  final VoidCallback onTap;

  const _TechniqueOverviewCard({
    required this.technique,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = technique['title'] as String? ?? '';
    final description = technique['description'] as String? ?? '';
    final category = technique['category'] as String? ?? '';
    final time = technique['time'] as String? ?? '';
    final difficulty = technique['difficulty'] as String? ?? '';

    return ChefBaseListTile(
      title: title,
      subtitle: [
        category,
        time,
        difficulty,
        description,
      ].where((value) => value.trim().isNotEmpty).join(' · '),
      subtitleMaxLines: 2,
      leading: const Icon(
        Icons.restaurant_menu_outlined,
        color: Color(0xFF8A7A6E),
        size: 19,
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF9A9088),
        size: 20,
      ),
      onTap: onTap,
    );
  }
}

class TechniqueDetailPage extends StatelessWidget {
  final Map<String, dynamic> technique;

  const TechniqueDetailPage({
    super.key,
    required this.technique,
  });

  List<TimerPreset> _timerPresets() {
    final timerDefaults = technique['timerDefaults'];
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

  List<String> _stringList(String key) {
    final value = technique[key];
    if (value is! List) {
      return const [];
    }

    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final title = technique['title'] as String? ?? '';
    final description = technique['description'] as String? ?? '';
    final category = technique['category'] as String? ?? '';
    final time = technique['time'] as String? ?? '';
    final difficulty = technique['difficulty'] as String? ?? '';
    final steps = _stringList('steps');
    final checkpoints = _stringList('checkpoints');
    final tips = _stringList('tips');
    final timerPresets = _timerPresets();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Technique'),
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
          Text(
            description,
            style: const TextStyle(
              fontSize: 16,
              height: 1.45,
              color: Color(0xFF3B332E),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TechniqueMetaChip(label: category, icon: Icons.category),
              _TechniqueMetaChip(label: time, icon: Icons.schedule),
              _TechniqueMetaChip(
                label: difficulty,
                icon: Icons.signal_cellular_alt,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _TechniqueSection(
            title: 'Étapes',
            children: steps.asMap().entries.map((entry) {
              return _TechniqueStep(
                number: entry.key + 1,
                text: entry.value,
              );
            }).toList(),
          ),
          if (timerPresets.isNotEmpty) ...[
            const SizedBox(height: 20),
            InlineTimerCard(
              title: title,
              presets: timerPresets,
              showCustomDuration: false,
            ),
          ],
          if (checkpoints.isNotEmpty) ...[
            const SizedBox(height: 20),
            _TechniqueSection(
              title: 'Points de contrôle',
              children: checkpoints.map(_TechniqueBullet.new).toList(),
            ),
          ],
          if (tips.isNotEmpty) ...[
            const SizedBox(height: 20),
            _TechniqueSection(
              title: 'Astuces',
              children: tips.map(_TechniqueBullet.new).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _TechniqueMetaChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _TechniqueMetaChip({
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F3EE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: const Color(0xFFD97706),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6A6058),
            ),
          ),
        ],
      ),
    );
  }
}

class _TechniqueSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _TechniqueSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE9DDD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F1A17),
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _TechniqueStep extends StatelessWidget {
  final int number;
  final String text;

  const _TechniqueStep({
    required this.number,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFF4E4C8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFD97706),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Color(0xFF3B332E),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TechniqueBullet extends StatelessWidget {
  final String text;

  const _TechniqueBullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 7),
            decoration: const BoxDecoration(
              color: Color(0xFFE3A13A),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                color: Color(0xFF3B332E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
