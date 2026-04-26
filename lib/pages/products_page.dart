import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/recipe_store.dart';
import '../widgets/chefbase_list_tile.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  Map<String, dynamic>? data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final jsonString =
        await rootBundle.loadString('assets/data/products_data.json');
    if (!mounted) return;
    setState(() {
      data = jsonDecode(jsonString) as Map<String, dynamic>;
    });
  }

  Widget _navCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ChefBaseListTile(
      title: title,
      subtitle: subtitle,
      leading: Icon(icon, color: const Color(0xFF8A7A6E), size: 19),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF9A9088),
        size: 20,
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produits'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _navCard(
            title: 'Produits de saison',
            subtitle: 'Fruits et légumes de saison',
            icon: Icons.eco_outlined,
            onTap: data == null
                ? () {}
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProductsSeasonPage(
                          seasonal: data!['seasonal'],
                        ),
                      ),
                    );
                  },
          ),
          _navCard(
            title: 'Variétés / spécificités',
            subtitle: 'Usages, variétés et particularités',
            icon: Icons.info_outline,
            onTap: data == null
                ? () {}
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProductsDetailsPage(
                          details: List<Map<String, dynamic>>.from(
                            data!['details'] as List,
                          ),
                        ),
                      ),
                    );
                  },
          ),
        ],
      ),
    );
  }
}

class ProductsSeasonPage extends StatelessWidget {
  final dynamic seasonal;

  const ProductsSeasonPage({
    super.key,
    required this.seasonal,
  });

  @override
  Widget build(BuildContext context) {
    final groups = currentPeriodFirstSeasonalGroups(seasonalGroups(seasonal));
    final children = groups.isEmpty
        ? const [
            Text(
              'Aucun produit de saison disponible.',
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF5A514B),
              ),
            ),
          ]
        : groups.map((group) => _SeasonalCard(group: group)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Produits de saison'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: children,
      ),
    );
  }
}

class _SeasonalCard extends StatelessWidget {
  final SeasonalGroup group;

  const _SeasonalCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final periodLabel = group.periodLabel;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: group.isCurrent
              ? const Color(0xFFD97706)
              : const Color(0xFFE9DDD0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (group.isCurrent) ...[
            Row(
              children: [
                const Icon(
                  Icons.today_outlined,
                  size: 17,
                  color: Color(0xFFD97706),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    periodLabel == null
                        ? 'En ce moment'
                        : 'En ce moment · $periodLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFD97706),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Text(
            group.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F1A17),
            ),
          ),
          const SizedBox(height: 12),
          ...group.sections.map((section) {
            return Padding(
              padding: EdgeInsets.only(
                top: section.title.isEmpty ? 0 : 2,
                bottom: 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (section.title.isNotEmpty) ...[
                    Text(
                      section.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3B332E),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: section.items.map((item) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F3EE),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          item,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF3B332E),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class SeasonalGroup {
  final String title;
  final List<SeasonalSection> sections;
  final bool isCurrent;
  final String? periodLabel;

  const SeasonalGroup({
    required this.title,
    required this.sections,
    this.isCurrent = false,
    this.periodLabel,
  });

  SeasonalGroup copyWith({
    bool? isCurrent,
    String? periodLabel,
  }) {
    return SeasonalGroup(
      title: title,
      sections: sections,
      isCurrent: isCurrent ?? this.isCurrent,
      periodLabel: periodLabel ?? this.periodLabel,
    );
  }
}

class SeasonalSection {
  final String title;
  final List<String> items;

  const SeasonalSection({
    required this.title,
    required this.items,
  });
}

List<SeasonalGroup> seasonalGroups(dynamic seasonal) {
  if (seasonal is List) {
    return seasonal
        .map(_seasonalGroupFromEntry)
        .whereType<SeasonalGroup>()
        .toList();
  }

  if (seasonal is Map) {
    final months = seasonal['months'] ?? seasonal['mois'];
    if (months is List) {
      return seasonalGroups(months);
    }

    return seasonal.entries
        .map((entry) => _seasonalGroupFromMonthEntry(entry.key, entry.value))
        .whereType<SeasonalGroup>()
        .toList();
  }

  return const [];
}

List<SeasonalGroup> currentMonthFirstSeasonalGroups(
  List<SeasonalGroup> groups,
) {
  return currentPeriodFirstSeasonalGroups(groups);
}

List<SeasonalGroup> currentPeriodFirstSeasonalGroups(
  List<SeasonalGroup> groups, {
  DateTime? now,
}) {
  if (groups.length < 2) return groups;

  final date = now ?? DateTime.now();
  final monthIndex = date.month - 1;
  const monthNames = [
    'janvier',
    'fevrier',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'aout',
    'septembre',
    'octobre',
    'novembre',
    'decembre',
  ];
  final currentMonth = monthNames[monthIndex];
  final currentMonthPosition = groups.indexWhere((group) {
    return RecipeStore.normalizeForSearch(group.title) == currentMonth;
  });

  if (currentMonthPosition == -1) return groups;

  final ordered = [
    ...groups.skip(currentMonthPosition),
    ...groups.take(currentMonthPosition),
  ];
  return [
    ordered.first.copyWith(
      isCurrent: true,
      periodLabel: _currentWeekLabel(date),
    ),
    ...ordered.skip(1),
  ];
}

String _currentWeekLabel(DateTime date) {
  final start = DateTime(date.year, date.month, date.day)
      .subtract(Duration(days: date.weekday - DateTime.monday));
  final end = start.add(const Duration(days: 6));
  return 'semaine du ${start.day} au ${end.day} ${_monthName(end.month)}';
}

String _monthName(int month) {
  const names = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];
  return names[month - 1];
}

SeasonalGroup? _seasonalGroupFromEntry(dynamic entry) {
  if (entry is Map) {
    final title = _firstString(entry, const [
          'title',
          'name',
          'label',
          'month',
          'mois',
        ]) ??
        'Produits de saison';
    final sections = _seasonalSectionsFromMap(entry);
    if (sections.isEmpty) return null;
    return SeasonalGroup(title: title, sections: sections);
  }

  final items = _stringList(entry);
  if (items.isEmpty) return null;
  return SeasonalGroup(
    title: 'Produits de saison',
    sections: [SeasonalSection(title: '', items: items)],
  );
}

SeasonalGroup? _seasonalGroupFromMonthEntry(dynamic title, dynamic value) {
  if (value is Map) {
    final sections = _seasonalSectionsFromMap(value);
    if (sections.isEmpty) return null;
    return SeasonalGroup(
      title: _displayText(title),
      sections: sections,
    );
  }

  final items = _stringList(value);
  if (items.isEmpty) return null;
  return SeasonalGroup(
    title: _displayText(title),
    sections: [SeasonalSection(title: '', items: items)],
  );
}

List<SeasonalSection> _seasonalSectionsFromMap(Map<dynamic, dynamic> source) {
  final sections = <SeasonalSection>[];
  final fruits = _stringList(_firstValue(source, const ['fruits', 'fruit']));
  final vegetables = _stringList(
    _firstValue(
      source,
      const [
        'vegetables',
        'vegetable',
        'legumes',
        'legume',
        'légumes',
        'légume'
      ],
    ),
  );

  if (fruits.isNotEmpty) {
    sections.add(SeasonalSection(title: 'Fruits', items: fruits));
  }
  if (vegetables.isNotEmpty) {
    sections.add(SeasonalSection(title: 'Légumes', items: vegetables));
  }

  final items = source['items'];
  if (items is Map) {
    for (final entry in items.entries) {
      final title = _sectionTitle(entry.key);
      final values = _stringList(entry.value);
      if (values.isNotEmpty && !_hasSection(sections, title)) {
        sections.add(SeasonalSection(title: title, items: values));
      }
    }
  } else {
    final values = _stringList(items);
    if (values.isNotEmpty && sections.isEmpty) {
      sections.add(SeasonalSection(title: '', items: values));
    }
  }

  return sections;
}

bool _hasSection(List<SeasonalSection> sections, String title) {
  final normalizedTitle = RecipeStore.normalizeForSearch(title);
  return sections.any(
    (section) =>
        RecipeStore.normalizeForSearch(section.title) == normalizedTitle,
  );
}

dynamic _firstValue(Map<dynamic, dynamic> source, List<String> keys) {
  for (final key in keys) {
    if (source.containsKey(key)) return source[key];
  }
  return null;
}

String? _firstString(Map<dynamic, dynamic> source, List<String> keys) {
  final value = _firstValue(source, keys);
  if (value == null) return null;
  final text = _displayText(value);
  return text.isEmpty ? null : text;
}

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value
        .map(_displayText)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  final text = _displayText(value);
  return text.isEmpty ? const [] : [text];
}

String _sectionTitle(dynamic value) {
  final normalized = RecipeStore.normalizeForSearch(_displayText(value));
  if (normalized == 'fruits' || normalized == 'fruit') return 'Fruits';
  if (normalized == 'vegetables' ||
      normalized == 'vegetable' ||
      normalized == 'legumes' ||
      normalized == 'legume') {
    return 'Légumes';
  }
  return _displayText(value);
}

String _displayText(dynamic value) => value?.toString().trim() ?? '';

class ProductsDetailsPage extends StatefulWidget {
  final List<Map<String, dynamic>> details;

  const ProductsDetailsPage({
    super.key,
    required this.details,
  });

  @override
  State<ProductsDetailsPage> createState() => _ProductsDetailsPageState();
}

class _ProductsDetailsPageState extends State<ProductsDetailsPage> {
  String searchQuery = '';

  List<Map<String, dynamic>> get filtered {
    final q = RecipeStore.normalizeForSearch(searchQuery);
    if (q.isEmpty) return widget.details;

    return widget.details.where((item) {
      final name =
          RecipeStore.normalizeForSearch(item['name'] as String? ?? '');
      final category = RecipeStore.normalizeForSearch(
        item['category'] as String? ?? '',
      );
      final notes = RecipeStore.normalizeForSearch(
        item['notes'] as String? ?? '',
      );
      final bestFor = RecipeStore.normalizeForSearch(
        List<String>.from(item['best_for'] as List? ?? const []).join(' '),
      );

      return name.contains(q) ||
          category.contains(q) ||
          notes.contains(q) ||
          bestFor.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Variétés / spécificités'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            onChanged: (v) => setState(() => searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Rechercher un produit...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
          const SizedBox(height: 16),
          if (list.isEmpty)
            const Text(
              'Aucun produit ne correspond à cette recherche.',
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF5A514B),
              ),
            ),
          ...list.map((item) {
            final bestFor =
                List<String>.from(item['best_for'] as List? ?? const []);
            return ChefBaseListTile(
              title: item['name'] as String? ?? '',
              subtitle: [
                item['category'] as String? ?? '',
                if (bestFor.isNotEmpty) bestFor.take(3).join(' · '),
                item['notes'] as String? ?? '',
              ].where((value) => value.trim().isNotEmpty).join(' · '),
              subtitleMaxLines: 2,
              leading: const Icon(
                Icons.eco_outlined,
                color: Color(0xFF8A7A6E),
                size: 19,
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF9A9088),
                size: 20,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductDetailPage(item: item),
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }
}

class ProductDetailPage extends StatelessWidget {
  final Map<String, dynamic> item;

  const ProductDetailPage({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final name = item['name'] as String? ?? '';
    final category = item['category'] as String? ?? '';
    final bestFor = List<String>.from(item['best_for'] as List? ?? const []);
    final notes = item['notes'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 36),
        children: [
          Text(
            name,
            style: const TextStyle(
              fontSize: 32,
              height: 1.12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F1A17),
            ),
          ),
          if (category.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              category,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A7A6E),
              ),
            ),
          ],
          if (bestFor.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Text(
              'Usages',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1F1A17),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: bestFor.map((value) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F3EE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF3B332E),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (notes.trim().isNotEmpty) ...[
            const SizedBox(height: 28),
            const Text(
              'Notes',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1F1A17),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              notes,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                color: Color(0xFF3B332E),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
