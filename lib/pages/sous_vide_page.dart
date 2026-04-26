import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/recipe_store.dart';
import '../widgets/chefbase_list_tile.dart';
import 'sous_vide_detail_page.dart';

class SousVidePage extends StatefulWidget {
  const SousVidePage({super.key});

  @override
  State<SousVidePage> createState() => _SousVidePageState();
}

class _SousVidePageState extends State<SousVidePage> {
  static const String _customKey = 'chefbase_sous_vide_custom_v1';
  static const String _favoritesKey = 'chefbase_sous_vide_favorites_v1';

  final List<String> siteCategories = const [
    'BOEUF',
    'VEAU',
    'PORC',
    'AGNEAU',
    'POULET, PINTADE',
    'CANARD',
    'VOLAILLES AUTRES',
    'CERF',
    'CHEVREUIL',
    'LAPIN',
    'POISSONS D’EAU DOUCE SANS PEAU',
    'POISSONS D’EAU DOUCE AVEC PEAU',
    'POISSONS DE MER SANS PEAU',
    'POISSONS DE MER AVEC PEAU',
    'CRUSTACES',
    'COQUILLAGES',
    'CEPHALOPODES',
    'OEUFS',
    'LEGUMES BRUTS, PARES, NETTOYES',
    'LEGUMES DIVERS',
    'FRUITS',
    'DIVERS',
    'FOIE GRAS',
  ];

  final List<String> cuissonOrder = const [
    'bleu',
    'saignant',
    'rosé',
    'à point',
    'bien cuit',
    'mi-cuit',
    'confit',
    'nacré',
    'crémeux',
    'fondant',
    'autre',
  ];

  List<Map<String, dynamic>> defaultEntries = [];
  List<Map<String, dynamic>> customEntries = [];
  Set<String> favoris = {};

  String searchQuery = '';
  String selectedCategory = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAll();
    });
  }

  Future<void> _loadAll() async {
    final jsonString =
        await rootBundle.loadString('assets/data/sous_vide.json');
    final List data = jsonDecode(jsonString);

    List<Map<String, dynamic>> loadedCustomEntries = [];
    Set<String> loadedFavoris = {};

    try {
      final prefs = await SharedPreferences.getInstance();
      final customRaw = prefs.getString(_customKey);
      final favRaw = prefs.getString(_favoritesKey);

      if (customRaw != null && customRaw.isNotEmpty) {
        final List decoded = jsonDecode(customRaw);
        loadedCustomEntries =
            decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      if (favRaw != null && favRaw.isNotEmpty) {
        final List decoded = jsonDecode(favRaw);
        loadedFavoris = decoded.map((e) => e.toString()).toSet();
      }
    } catch (_) {
      loadedCustomEntries = [];
      loadedFavoris = {};
    }

    if (!mounted) return;
    setState(() {
      defaultEntries = data.map((e) => Map<String, dynamic>.from(e)).toList();
      customEntries = loadedCustomEntries;
      favoris = loadedFavoris;
    });
  }

  Future<void> _saveCustomEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_customKey, jsonEncode(customEntries));
    } catch (_) {}
  }

  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_favoritesKey, jsonEncode(favoris.toList()));
    } catch (_) {}
  }

  Future<void> _toggleFav(String title) async {
    setState(() {
      if (favoris.contains(title)) {
        favoris.remove(title);
      } else {
        favoris.add(title);
      }
    });
    await _saveFavorites();
  }

  String _normalizeTexture(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return 'autre';
    if (v.contains('bleu')) return 'bleu';
    if (v.contains('saignant')) return 'saignant';
    if (v.contains('rosé') || v.contains('rose')) return 'rosé';
    if (v.contains('à point') || v.contains('a point')) return 'à point';
    if (v.contains('bien cuit')) return 'bien cuit';
    if (v.contains('mi-cuit')) return 'mi-cuit';
    if (v.contains('confit')) return 'confit';
    if (v.contains('nacré') || v.contains('nacre')) return 'nacré';
    if (v.contains('crémeux') || v.contains('cremeux')) return 'crémeux';
    if (v.contains('fondant')) return 'fondant';
    return 'autre';
  }

  int _cuissonRank(String value) {
    final normalized = _normalizeTexture(value);
    final idx = cuissonOrder.indexOf(normalized);
    return idx == -1 ? cuissonOrder.length : idx;
  }

  double? _tempNumber(String value) {
    final match = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(value);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.replaceAll(',', '.'));
  }

  String _formatTemp(double value) {
    if (value == value.roundToDouble()) {
      return '${value.toInt()}°C';
    }
    return '${value.toStringAsFixed(1)}°C';
  }

  List<Map<String, dynamic>> get _allEntries {
    final merged = <Map<String, dynamic>>[];

    for (var i = 0; i < customEntries.length; i++) {
      merged.add({
        ...customEntries[i],
        'isCustom': true,
        '_customIndex': i,
        '_sortOrder': -1000 + i,
      });
    }

    for (var i = 0; i < defaultEntries.length; i++) {
      merged.add({
        ...defaultEntries[i],
        'isCustom': false,
        '_sortOrder': i,
      });
    }

    return merged;
  }

  List<Map<String, dynamic>> get displayEntries {
    final merged = _allEntries;
    final query = RecipeStore.normalizeForSearch(searchQuery);

    final filtered = merged.where((e) {
      final searchText = RecipeStore.normalizeForSearch(
        [
          e['title'],
          e['siteCategory'],
          e['texture'],
          e['note'],
          e['temp'],
          e['time'],
        ].map((value) => value?.toString() ?? '').join(' '),
      );
      final isFav = favoris.contains(e['title']);

      final matchSearch = query.isEmpty ? true : searchText.contains(query);

      final matchCategory = selectedCategory == 'all'
          ? true
          : selectedCategory == 'favoris'
              ? isFav
              : e['siteCategory'] == selectedCategory;

      return matchSearch && matchCategory;
    }).toList();

    filtered.sort((a, b) {
      final aCat = a['siteCategory'] as String? ?? '';
      final bCat = b['siteCategory'] as String? ?? '';

      if (selectedCategory == 'all' || selectedCategory == 'favoris') {
        final aCatRank = siteCategories.indexOf(aCat);
        final bCatRank = siteCategories.indexOf(bCat);
        if (aCatRank != bCatRank) {
          return aCatRank.compareTo(bCatRank);
        }
      }

      final aCuisson = _cuissonRank(a['texture'] as String? ?? '');
      final bCuisson = _cuissonRank(b['texture'] as String? ?? '');
      if (aCuisson != bCuisson) {
        return aCuisson.compareTo(bCuisson);
      }

      final aOrder = a['_sortOrder'] as int? ?? 0;
      final bOrder = b['_sortOrder'] as int? ?? 0;
      if (aOrder != bOrder) {
        return aOrder.compareTo(bOrder);
      }

      final aTitle = a['title'] as String? ?? '';
      final bTitle = b['title'] as String? ?? '';
      return aTitle.compareTo(bTitle);
    });

    return filtered;
  }

  List<String> get _visibleSiteCategories {
    final categoriesWithEntries = _allEntries
        .map((entry) => entry['siteCategory']?.toString() ?? '')
        .where((category) => category.isNotEmpty)
        .toSet();

    return siteCategories
        .where((category) => categoriesWithEntries.contains(category))
        .toList();
  }

  List<Map<String, String>> _cuissonSummaryForSelectedCategory() {
    if (selectedCategory == 'all' || selectedCategory == 'favoris') {
      return [];
    }

    final entries = _allEntries.where((e) {
      return e['siteCategory'] == selectedCategory;
    }).toList();

    final Map<String, List<double>> values = {};
    for (final e in entries) {
      final cuisson = _normalizeTexture(e['texture'] as String? ?? '');
      final temp = _tempNumber(e['temp'] as String? ?? '');
      if (temp == null) continue;
      values.putIfAbsent(cuisson, () => []).add(temp);
    }

    final result = <Map<String, String>>[];
    for (final cuisson in cuissonOrder) {
      final temps = values[cuisson];
      if (temps == null || temps.isEmpty) continue;
      temps.sort();
      final label = temps.first == temps.last
          ? _formatTemp(temps.first)
          : '${_formatTemp(temps.first)} → ${_formatTemp(temps.last)}';
      result.add({
        'cuisson': cuisson,
        'temp': label,
      });
    }
    return result;
  }

  Future<void> _deleteCustomProtocol(int index) async {
    final title = customEntries[index]['title'] as String? ?? 'ce protocole';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Supprimer le protocole'),
          content: Text('Voulez-vous vraiment supprimer "$title" ?'),
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
      final removedTitle = customEntries[index]['title'] as String? ?? '';
      setState(() {
        customEntries.removeAt(index);
        favoris.remove(removedTitle);
      });
      await _saveCustomEntries();
      await _saveFavorites();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Protocole supprimé')),
      );
    }
  }

  Future<void> _openProtocolForm({
    Map<String, dynamic>? initialProtocol,
    int? customIndex,
  }) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SousVideProtocolFormPage(
          siteCategories: siteCategories,
          initialProtocol: initialProtocol,
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      if (customIndex != null) {
        customEntries[customIndex] = result;
      } else {
        customEntries.insert(0, result);
      }
    });

    await _saveCustomEntries();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          customIndex != null ? 'Protocole modifié' : 'Protocole ajouté',
        ),
      ),
    );
  }

  Widget _titleWithAdd() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Sous-vide'),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _openProtocolForm(),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.orange.shade200,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add, size: 18),
          ),
        ),
      ],
    );
  }

  String _chipLabel(String label) {
    switch (label) {
      case 'favoris':
        return 'Favoris';
      case 'all':
        return 'all';
      default:
        return label;
    }
  }

  Widget _categoryChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          _chipLabel(label),
          overflow: TextOverflow.ellipsis,
        ),
        selected: selected,
        onSelected: (_) => onTap(),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _cuissonTempBanner() {
    final rows = _cuissonSummaryForSelectedCategory();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE9DDD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            selectedCategory,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F1A17),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: rows.map((row) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE9DDD0)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      row['cuisson'] ?? '',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6A6058),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      row['temp'] ?? '',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F1A17),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _entryCard(Map<String, dynamic> e) {
    final isFav = favoris.contains(e['title']);
    final isCustom = e['isCustom'] as bool? ?? false;
    final customIndex = isCustom ? (e['_customIndex'] as int?) : null;
    final texture = (e['texture'] as String? ?? '').trim();
    final note = (e['note'] as String? ?? '').trim();
    final siteCategory = e['siteCategory'] as String? ?? '';

    return ChefBaseListTile(
      title: e['title'] as String? ?? '',
      subtitle: [
        siteCategory,
        e['temp'] as String? ?? '',
        e['time'] as String? ?? '',
        if (texture.isNotEmpty) texture,
        if (note.isNotEmpty) note,
        if (isCustom) 'perso',
      ].where((value) => value.trim().isNotEmpty).join(' · '),
      titleMaxLines: 1,
      subtitleMaxLines: 2,
      leading: Icon(
        Icons.thermostat_outlined,
        color: isFav ? const Color(0xFFB45309) : const Color(0xFF8A7A6E),
        size: 19,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => _toggleFav(e['title']),
            tooltip: isFav ? 'Retirer des favoris' : 'Favori',
            style: IconButton.styleFrom(
              foregroundColor:
                  isFav ? const Color(0xFFB45309) : const Color(0xFF9A9088),
              minimumSize: const Size.square(34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon:
                Icon(isFav ? Icons.star_rounded : Icons.star_border, size: 19),
          ),
          if (isCustom && customIndex != null)
            PopupMenuButton<String>(
              tooltip: 'Actions',
              icon: const Icon(
                Icons.more_horiz_rounded,
                size: 20,
                color: Color(0xFF8A7A6E),
              ),
              onSelected: (value) {
                if (value == 'edit') {
                  _openProtocolForm(
                    initialProtocol: {
                      'title': e['title'],
                      'siteCategory': e['siteCategory'],
                      'temp': e['temp'],
                      'time': e['time'],
                      'texture': e['texture'],
                      'note': e['note'],
                    },
                    customIndex: customIndex,
                  );
                } else if (value == 'delete') {
                  _deleteCustomProtocol(customIndex);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Modifier')),
                PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            )
          else
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF9A9088),
              size: 20,
            ),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SousVideDetailPage(
              item: e,
              isFavorite: isFav,
              onToggleFavorite: () => _toggleFav(e['title']),
            ),
          ),
        ).then((_) {
          if (mounted) {
            setState(() {});
          }
        });
      },
    );
  }

  Widget _categoriesBar() {
    final labels = ['all', 'favoris', ..._visibleSiteCategories];

    return SizedBox(
      height: 76,
      child: Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: labels
                  .map(
                    (cat) => _categoryChip(
                      cat,
                      selectedCategory == cat,
                      () => setState(() => selectedCategory = cat),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = displayEntries;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: _titleWithAdd(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            onChanged: (v) => setState(() => searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Rechercher une cuisson...',
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
          const SizedBox(height: 14),
          _categoriesBar(),
          const SizedBox(height: 18),
          _cuissonTempBanner(),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text('Aucun repère trouvé'),
              ),
            ),
          ...list.map(_entryCard),
        ],
      ),
    );
  }
}

class SousVideProtocolFormPage extends StatefulWidget {
  final List<String> siteCategories;
  final Map<String, dynamic>? initialProtocol;

  const SousVideProtocolFormPage({
    super.key,
    required this.siteCategories,
    this.initialProtocol,
  });

  @override
  State<SousVideProtocolFormPage> createState() =>
      _SousVideProtocolFormPageState();
}

class _SousVideProtocolFormPageState extends State<SousVideProtocolFormPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _tempController;
  late final TextEditingController _timeController;
  late final TextEditingController _textureController;
  late final TextEditingController _noteController;

  late String selectedSiteCategory;

  @override
  void initState() {
    super.initState();

    final item = widget.initialProtocol;

    _titleController =
        TextEditingController(text: item?['title'] as String? ?? '');
    _tempController =
        TextEditingController(text: item?['temp'] as String? ?? '');
    _timeController =
        TextEditingController(text: item?['time'] as String? ?? '');
    _textureController =
        TextEditingController(text: item?['texture'] as String? ?? '');
    _noteController =
        TextEditingController(text: item?['note'] as String? ?? '');
    selectedSiteCategory =
        item?['siteCategory'] as String? ?? widget.siteCategories.first;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tempController.dispose();
    _timeController.dispose();
    _textureController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(context, {
      'title': _titleController.text.trim(),
      'siteCategory': selectedSiteCategory,
      'temp': _tempController.text.trim(),
      'time': _timeController.text.trim(),
      'texture': _textureController.text.trim(),
      'note': _noteController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialProtocol != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Modifier protocole' : 'Ajouter protocole'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(
              'Nom',
              _titleController,
              hint: 'Ex: Magret canard',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nom obligatoire' : null,
            ),
            DropdownButtonFormField<String>(
              initialValue: selectedSiteCategory,
              items: widget.siteCategories
                  .map(
                    (g) => DropdownMenuItem<String>(
                      value: g,
                      child: Text(g),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  selectedSiteCategory = value ?? widget.siteCategories.first;
                });
              },
              decoration: InputDecoration(
                labelText: 'Catégorie du site',
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
            const SizedBox(height: 14),
            _field(
              'Température',
              _tempController,
              hint: 'Ex: 54°C',
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Température obligatoire'
                  : null,
            ),
            _field(
              'Temps',
              _timeController,
              hint: 'Ex: 1 h 30',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Temps obligatoire' : null,
            ),
            _field(
              'Texture',
              _textureController,
              hint: 'Ex: rosé, fondant, nacré...',
            ),
            _field(
              'Note',
              _noteController,
              hint: 'Optionnel',
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save),
              label: Text(
                isEditing
                    ? 'Enregistrer les modifications'
                    : 'Enregistrer le protocole',
              ),
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
