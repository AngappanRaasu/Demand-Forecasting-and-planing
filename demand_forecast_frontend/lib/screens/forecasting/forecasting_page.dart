import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../main_layout.dart';

// ─── Color Palette ──────────────────────────────────────────────────
class _C {
  static const primary = Color(0xFF2563EB);
  static const primaryLight = Color(0xFFEFF6FF);
  static const pageBg = Color(0xFFF0F4F8);
  static const panelBg = Color(0xFFFFFFFF);
  static const headerBg = Color(0xFF1E3A5F);
  static const border = Color(0xFFE2E8F0);
  static const textPrimary = Color(0xFF1E293B);
  static const textSecondary = Color(0xFF64748B);
  static const success = Color(0xFF059669);
}

// ─── Models ─────────────────────────────────────────────────────────
class _Category {
  final String id, name;
  final List<_Item> items;
  const _Category({required this.id, required this.name, required this.items});
  bool matches(String q) {
    final lq = q.toLowerCase();
    return id.toLowerCase().contains(lq) ||
        name.toLowerCase().contains(lq) ||
        displayId.toLowerCase().contains(lq);
  }

  String get displayId => 'CAT${id.padLeft(2, '0')}';
}

class _Item {
  final String id;        // real ITEMNO from DB (used for forecast)
  final String name;      // display name
  final String categoryId;
  final String uniqueKey; // unique per loaded row (for independent selection)
  final int catIndex;     // 1-based category position in _allCats
  final int itemIndex;    // 1-based position within the category
  const _Item({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.uniqueKey,
    required this.catIndex,
    required this.itemIndex,
  });
  bool matches(String q) {
    final lq = q.toLowerCase();
    return id.toLowerCase().contains(lq) ||
        name.toLowerCase().contains(lq) ||
        displayId.toLowerCase().contains(lq);
  }

  /// e.g. ITEMC1_01, ITEMC3_12
  String get displayId {
    final catPart = 'C$catIndex';
    final itemPart = itemIndex.toString().padLeft(2, '0');
    return 'ITEM${catPart}_$itemPart';
  }
}

// ─── Page ───────────────────────────────────────────────────────────
class ForecastingPage extends StatefulWidget {
  const ForecastingPage({super.key});
  @override
  State<ForecastingPage> createState() => _ForecastingPageState();
}

class _ForecastingPageState extends State<ForecastingPage> {
  // Filter bar
  String? _industry, _company, _lookback, _model, _period;
  List<String> _industries = [],
      _companies = [],
      _lookbacks = [],
      _models = [],
      _periods = [];
  bool _loadingFilters = true;
  final _jobNameCtrl = TextEditingController();
  String _jobName = '';

  // Dataset
  List<_Category> _allCats = [];
  bool _dataLoaded = false;
  bool _isApplying = false;

  // Categories scroll
  final ScrollController _scrollController = ScrollController();
  final ScrollController _itemGridScrollController = ScrollController();

  // Per-category item data (lazy loaded from backend)
  final Map<String, List<_Item>> _itemsByCategory = {};
  final Map<String, bool> _categoryItemsFullyLoaded = {};
  final Map<String, int> _categoryItemOffset = {}; // raw number of items already loaded
  final Map<String, int> _categoryItemTotalCount = {};
  final Map<String, bool> _categoryItemLoading = {};

  // Currently browsed category (only ONE at a time)
  String? _activeCatId;

  // Selection (checkboxes — for forecast, independent of which category is focused)
  final Set<String> _checkedCatIds = {};
  final Set<String> _selectedItemIds = {};

  // Search
  final _catSearchCtrl = TextEditingController();
  final _itemSearchCtrl = TextEditingController();
  String _catQ = '', _itemQ = '';

  // Actions
  bool _runForecastLoading = false;

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  @override
  void dispose() {
    _catSearchCtrl.dispose();
    _itemSearchCtrl.dispose();
    _jobNameCtrl.dispose();
    _scrollController.dispose();
    _itemGridScrollController.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────

  Future<void> _loadFilters() async {
    try {
      final res = await ApiService().getFilters();
      setState(() {
        _industries = List<String>.from(res['industries'] ?? []);
        _companies = List<String>.from(res['companies'] ?? []);
        _lookbacks = List<String>.from(res['lookbackOptions'] ?? []);
        _models = List<String>.from(res['modelOptions'] ?? []);
        _periods = List<String>.from(res['periodOptions'] ?? []);
        _loadingFilters = false;
      });
    } catch (e) {
      setState(() => _loadingFilters = false);
      _snack('Could not load filters: $e');
    }
  }

  Future<void> _apply() async {
    if ([
      _industry,
      _company,
      _lookback,
      _model,
      _period,
    ].any((v) => v == null)) {
      _snack('Please select all filter options.');
      return;
    }
    setState(() {
      _isApplying = true;
      _dataLoaded = false;
      _allCats.clear();
      _activeCatId = null;
      _checkedCatIds.clear();
      _selectedItemIds.clear();
      _itemsByCategory.clear();
      _categoryItemOffset.clear();
      _categoryItemsFullyLoaded.clear();
      _categoryItemLoading.clear();
      _categoryItemTotalCount.clear();
    });
    try {
      // Load ALL categories in one go — no category-level pagination
      final res = await ApiService().loadForecastData(
        industry: _industry!,
        company: _company!,
        lookback: _lookback!,
        model: _model!,
        period: _period!,
        page: 1,
        pageSize: 9999, // fetch all categories at once
        searchQuery: _catQ,
      );
      if (res['success'] == true) {
        final List<dynamic> cats = res['categories'] ?? [];
        setState(() {
          _allCats = cats
              .map(
                (c) => _Category(
                  id: c['id'] ?? '',
                  name: c['name'] ?? '',
                  items: const [],
                ),
              )
              .toList();
          _dataLoaded = true;
        });
      } else {
        _snack('Apply failed: ${res['message']}');
      }
    } catch (e) {
      _snack('Error: $e');
    } finally {
      setState(() => _isApplying = false);
    }
  }


  Future<void> _runForecast() async {
    if (_selectedItemIds.isEmpty) {
      _snack('Select at least one item.');
      return;
    }
    
    final submitJobName = _jobName.trim().isEmpty 
        ? 'Forecast ${DateTime.now().toIso8601String().substring(0, 10)}' 
        : _jobName.trim();

    setState(() => _runForecastLoading = true);
    try {
      // Collect all selected item IDs across ALL loaded categories
      final allSelectedItems = <String>{};
      for (final items in _itemsByCategory.values) {
        for (final item in items) {
          if (_selectedItemIds.contains(item.uniqueKey)) {
            allSelectedItems.add(item.id);
          }
        }
      }
      final res = await ApiService().runForecast(
        itemIds: allSelectedItems.toList(),
        model: _model!,
        lookback: _lookback!,
        period: _period!,
        jobName: submitJobName,
      );
      if (res['success'] == true) {
        final jobId = res['jobId'] ?? '';
        if (mounted) {
          _snack(
            'Job created: $jobId — Check Dashboard for status.',
            color: _C.success,
          );
          // Clear job name for next run
          _jobNameCtrl.clear();
          setState(() => _jobName = '');
        }
      } else {
        _snack('Failed to create job: ${res['message']}');
      }
    } catch (e) {
      _snack('Error: $e');
    } finally {
      setState(() => _runForecastLoading = false);
    }
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ── Category helpers ─────────────────────────────────────────────

  List<_Category> get _filteredCats => _catQ.isEmpty
      ? _allCats
      : _allCats.where((c) => c.matches(_catQ)).toList();

  /// Items shown in the grid:
  /// 1. All currently selected items (from any category) afloat at the top.
  /// 2. Unselected items from the currently active category below.
  List<_Item> get _visibleItems {
    final all = <_Item>[];

    // 1. Add ALL selected items from ALL loaded categories
    for (final entry in _itemsByCategory.entries) {
      all.addAll(entry.value.where((i) => _selectedItemIds.contains(i.uniqueKey)));
    }

    // 2. Add UNSELECTED items from the CURRENTLY ACTIVE category
    if (_activeCatId != null && _itemsByCategory.containsKey(_activeCatId)) {
      final activeItems = _itemsByCategory[_activeCatId]!;
      all.addAll(activeItems.where((i) => !_selectedItemIds.contains(i.uniqueKey)));
    }

    return _itemQ.isEmpty
        ? all
        : all.where((i) => i.matches(_itemQ)).toList();
  }

  /// Clicking a category row: switch the browse view to that category.
  /// Always shows a fresh load for the selected category (instant spinner, no stale items).
  void _toggleCat(String id) {
    // If already on this category, do nothing
    if (_activeCatId == id) return;

    final alreadyLoaded = _itemsByCategory.containsKey(id) &&
        (_itemsByCategory[id]?.isNotEmpty ?? false);

    setState(() {
      _activeCatId = id;
      if (!alreadyLoaded) {
        // First time clicking: mark as loading immediately
        _categoryItemLoading[id] = true;
        _itemsByCategory[id] = [];
      }
      // else: already loaded — items will show instantly from cache
    });

    if (!alreadyLoaded) {
      _loadItemsForCategory(id);
    }
  }

  Future<void> _loadItemsForCategory(String catId, {bool loadMore = false}) async {
    // Guard: if already loading or fully loaded (for loadMore)
    if (loadMore && _categoryItemLoading[catId] == true) return;
    if (loadMore && _categoryItemsFullyLoaded[catId] == true) return;

    // Every load (first + subsequent) fetches 40 items at a time
    const pageSize = 40;

    if (!loadMore) {
      // For first load: reset state. Loading flag already set by _toggleCat for instant spinner.
      setState(() {
        _categoryItemOffset[catId] = 0;
        _itemsByCategory[catId] = [];
        _categoryItemsFullyLoaded[catId] = false;
        _categoryItemLoading[catId] = true; // ensure loading is true
      });
    } else {
      setState(() => _categoryItemLoading[catId] = true);
    }

    try {
      final skip = _categoryItemOffset[catId] ?? 0;
      final res = await ApiService().loadCategoryItems(
        categoryId: catId,
        skip: skip,
        pageSize: pageSize,
        searchQuery: _itemQ,
      );
      if (res['success'] == true) {
        final List<dynamic> rawItems = res['items'] ?? [];
        final totalCount = res['totalCount'] ?? 0;
        // Resolve 1-based category index from _allCats order
        final catIdx = _allCats.indexWhere((c) => c.id == catId) + 1;
        final existingCountBeforeAdd = (_itemsByCategory[catId] ?? []).length;
        final newItems = rawItems.asMap().entries
            .map((e) => _Item(
                  id: e.value['id'] ?? '',
                  name: e.value['name'] ?? '',
                  categoryId: e.value['categoryId'] ?? '',
                  uniqueKey: '${catId}_${existingCountBeforeAdd + e.key}',
                  catIndex: catIdx,
                  itemIndex: existingCountBeforeAdd + e.key + 1, // 1-based within category
                ))
            .toList();

        setState(() {
          final existing = _itemsByCategory[catId] ?? [];
          existing.addAll(newItems);
          _itemsByCategory[catId] = existing;
          _categoryItemTotalCount[catId] = totalCount;

          if (_checkedCatIds.contains(catId)) {
            _selectedItemIds.addAll(newItems.map((i) => i.uniqueKey));
          }

          final loaded = existing.length;
          _categoryItemsFullyLoaded[catId] = loaded >= totalCount;
          _categoryItemOffset[catId] = loaded; // update offset to items loaded so far
        });
      }
    } catch (e) {
      _snack('Error loading items for $catId: $e');
    } finally {
      setState(() => _categoryItemLoading[catId] = false);
    }
  }

  void _checkCat(String id, bool? v) {
    if (v == true) {
      final needsLoad = !_itemsByCategory.containsKey(id);
      setState(() {
        _checkedCatIds.add(id);
        _activeCatId = id;
        final items = _itemsByCategory[id] ?? [];
        _selectedItemIds.addAll(items.map((i) => i.uniqueKey));
        if (needsLoad) {
          _categoryItemLoading[id] = true;
          _itemsByCategory[id] = [];
        }
      });
      if (needsLoad) {
        _loadItemsForCategory(id);
      }
    } else {
      setState(() {
        _checkedCatIds.remove(id);
        final items = _itemsByCategory[id] ?? [];
        _selectedItemIds.removeAll(items.map((i) => i.uniqueKey));
      });
    }
  }

  void _toggleItem(String uniqueKey) => setState(
        () => _selectedItemIds.contains(uniqueKey)
            ? _selectedItemIds.remove(uniqueKey)
            : _selectedItemIds.add(uniqueKey),
      );

  bool get _allVisibleItemsSelected {
    if (_visibleItems.isEmpty) return false;
    return _visibleItems.every((i) => _selectedItemIds.contains(i.uniqueKey));
  }

  void _toggleAllVisibleItems() {
    setState(() {
      if (_allVisibleItemsSelected) {
        _selectedItemIds.removeAll(_visibleItems.map((e) => e.uniqueKey));
      } else {
        _selectedItemIds.addAll(_visibleItems.map((e) => e.uniqueKey));
      }
    });
  }

  bool get _allCatsChecked {
    if (_allCats.isEmpty) return false;
    return _allCats.every((c) => _checkedCatIds.contains(c.id));
  }

  void _toggleAllCats() {
    setState(() {
      if (_allCatsChecked) {
        for (var c in _allCats) {
          _checkedCatIds.remove(c.id);
          final items = _itemsByCategory[c.id] ?? [];
          _selectedItemIds.removeAll(items.map((i) => i.id));
        }
      } else {
        for (var c in _allCats) {
          _checkedCatIds.add(c.id);
          if (!_itemsByCategory.containsKey(c.id)) {
            _loadItemsForCategory(c.id);
          } else {
            final items = _itemsByCategory[c.id] ?? [];
            _selectedItemIds.addAll(items.map((i) => i.id));
          }
        }
        if (_allCats.isNotEmpty && _activeCatId == null) {
          _activeCatId = _allCats.first.id;
        }
      }
    });
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.pageBg,
      body: Column(
        children: [
          _buildHeader(),
          _buildFilterBar(),
          Expanded(child: _buildBody()),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: const BoxDecoration(color: _C.headerBg),
    child: const Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Demand Forecasting',
        style: TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );

  Widget _buildFilterBar() {
    if (_loadingFilters) {
      return const LinearProgressIndicator();
    }
    return Container(
      color: _C.panelBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: _dd(
              'Industry',
              _industry,
              _industries,
              (v) => setState(() => _industry = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _dd(
              'Company',
              _company,
              _companies,
              (v) => setState(() => _company = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _dd(
              'Lookback',
              _lookback,
              _lookbacks,
              (v) => setState(() => _lookback = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _dd(
              'Model',
              _model,
              _models,
              (v) => setState(() => _model = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _dd(
              'Period',
              _period,
              _periods,
              (v) => setState(() => _period = v),
            ),
          ),
          const SizedBox(width: 8),
          // ── Job Name (optional) ────────────────────────────────────
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 3, 8, 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _C.border,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Job Name',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _C.textSecondary,
                    ),
                  ),
                  TextField(
                    controller: _jobNameCtrl,
                    onChanged: (v) => setState(() => _jobName = v),
                    style: const TextStyle(fontSize: 12, color: _C.textPrimary),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: 'e.g. Q1 Forecast',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        color: _C.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: ElevatedButton(
              onPressed: _isApplying ? null : _apply,
              style: ElevatedButton.styleFrom(
                backgroundColor: _C.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: _isApplying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Apply',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Thin wrapper — keeps call sites identical
  Widget _dd(
    String hint,
    String? val,
    List<String> items,
    ValueChanged<String?> onChange,
  ) =>
      _FilterDropdown(hint: hint, value: val, items: items, onChange: onChange);

  Widget _buildBody() {
    if (!_dataLoaded) {
      return Center(
        child: _isApplying
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.filter_alt_outlined,
                    size: 48,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Select filters and click Apply to load data.',
                    style: TextStyle(color: _C.textSecondary, fontSize: 14),
                  ),
                ],
              ),
      );
    }
    return Row(
      children: [
        _buildCatPanel(),
        Expanded(child: _buildItemsPanel()),
      ],
    );
  }

  // ── Category Panel ───────────────────────────────────────────────

  Widget _buildCatPanel() {
    const double w = 250;
    return Container(
      width: w,
      decoration: const BoxDecoration(
        color: _C.panelBg,
        border: Border(right: BorderSide(color: _C.border)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
            decoration: const BoxDecoration(
              color: _C.panelBg,
              border: Border(bottom: BorderSide(color: _C.border)),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _allCatsChecked,
                  activeColor: _C.primary,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => _toggleAllCats(),
                ),
                const Text(
                  'Select All',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _C.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _catSearchCtrl,
                    onChanged: (q) {
                      setState(() => _catQ = q);
                      // Adding a simple delay (debounce logic could be better, but this handles simple reset)
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (mounted && _catQ == q) {
                          _apply();
                        }
                      });
                    },
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Search category & id',
                      hintStyle: const TextStyle(
                        fontSize: 11,
                        color: _C.textSecondary,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 16,
                        color: _C.textSecondary,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: _C.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: _C.border),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _filteredCats.length,
              itemBuilder: (_, i) => _catRow(_filteredCats[i], i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _catRow(_Category cat, int index) {
    final isPaginating = _activeCatId == cat.id;
    final checked = _checkedCatIds.contains(cat.id);
    final loadedCount = _itemsByCategory[cat.id]?.length ?? 0;
    final total = _categoryItemTotalCount[cat.id] ?? 0;
    // Generate clean sequential ID: CAT_01, CAT_02 …
    final catDisplayId = 'CAT_${(index + 1).toString().padLeft(2, '0')}';
    return InkWell(
      onTap: () => _toggleCat(cat.id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        decoration: BoxDecoration(
          color: isPaginating ? _C.primaryLight : Colors.transparent,
          border: isPaginating
              ? const Border(left: BorderSide(color: _C.primary, width: 3))
              : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Checkbox(
                value: checked,
                activeColor: _C.primary,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => _checkCat(cat.id, v),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cat.name, // real ITEMDESC value
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isPaginating ? FontWeight.w600 : FontWeight.normal,
                      color: isPaginating ? _C.primary : _C.textPrimary,
                    ),
                  ),
                  if (total > 0)
                    Text(
                      '$loadedCount / $total loaded',
                      style: TextStyle(
                        fontSize: 9,
                        color: isPaginating
                            ? _C.primary.withValues(alpha: 0.8)
                            : _C.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            // CAT_01 style ID
            SizedBox(
              width: 50,
              child: Text(
                catDisplayId,
                style: TextStyle(
                  fontSize: 10,
                  color: isPaginating ? _C.primary : _C.textSecondary,
                  fontWeight: isPaginating ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Items Panel ──────────────────────────────────────────────────

  Widget _buildItemsPanel() {
    return Container(
      color: _C.pageBg,
      child: Column(
        children: [
          _buildItemPanelHeader(),
          Expanded(child: _buildItemGrid()),
        ],
      ),
    );
  }

  Widget _buildItemPanelHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: const BoxDecoration(
        color: _C.panelBg,
        border: Border(bottom: BorderSide(color: _C.border)),
      ),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _allVisibleItemsSelected,
                activeColor: _C.primary,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => _toggleAllVisibleItems(),
              ),
              const Text(
                'Select All',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _C.textPrimary,
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_selectedItemIds.length} selected',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _C.success,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: 180,
            child: TextField(
              controller: _itemSearchCtrl,
              onChanged: (q) => setState(() => _itemQ = q),
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search items…',
                hintStyle: const TextStyle(
                  fontSize: 11,
                  color: _C.textSecondary,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 16,
                  color: _C.textSecondary,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: _C.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: _C.border),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemGrid() {
    if (_activeCatId == null && _selectedItemIds.isEmpty) {
      return const Center(
        child: Text(
          'Tap a category to view its items.',
          style: TextStyle(color: _C.textSecondary, fontSize: 13),
        ),
      );
    }

    // State based on the currently browsed category
    final bool isLoading = _activeCatId != null &&
        _categoryItemLoading[_activeCatId!] == true;

    final bool hasMore = _activeCatId != null &&
        (_categoryItemsFullyLoaded[_activeCatId!] == false) &&
        (_itemsByCategory[_activeCatId!]?.isNotEmpty ?? false);

    // Counts for the active (browsed) category only
    final int loadedCount = _activeCatId != null
        ? (_itemsByCategory[_activeCatId!]?.length ?? 0)
        : 0;
    final int totalCount = _activeCatId != null
        ? (_categoryItemTotalCount[_activeCatId!] ?? 0)
        : 0;

    Widget grid;
    if (_visibleItems.isEmpty && isLoading) {
      // First page is still being fetched
      grid = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(height: 12),
            Text(
              'Loading items...',
              style: TextStyle(color: _C.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    } else if (_visibleItems.isEmpty) {
      grid = const Center(
        child: Text(
          'No items found.',
          style: TextStyle(color: _C.textSecondary, fontSize: 13),
        ),
      );
    } else {
      grid = GridView.builder(
        controller: _itemGridScrollController,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 60,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _visibleItems.length,
        itemBuilder: (context, i) {
          final item = _visibleItems[i];
          final selected = _selectedItemIds.contains(item.uniqueKey);
          return InkWell(
            onTap: () => _toggleItem(item.uniqueKey),
            borderRadius: BorderRadius.circular(6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? _C.primary : _C.panelBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected ? const Color(0xFF1E40AF) : _C.border,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : _C.textPrimary,
                          ),
                        ),
                      ),
                      if (selected)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.displayId,
                    style: TextStyle(
                      fontSize: 10,
                      color: selected
                          ? Colors.white.withOpacity(0.8)
                          : _C.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    // Bottom strip: clickable ↓ Load more products or all-loaded label
    return Column(
      children: [
        Expanded(child: grid),
        // ── slim progress bar while loading more ─────────────────────
        if (isLoading && _visibleItems.isNotEmpty)
          const LinearProgressIndicator(minHeight: 3),
        // ── bottom strip ─────────────────────────────────────────────
        if (_visibleItems.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            decoration: const BoxDecoration(
              color: _C.panelBg,
              border: Border(top: BorderSide(color: _C.border)),
            ),
            child: Center(
              child: GestureDetector(
                onTap: (isLoading || !hasMore)
                    ? null
                    : () {
                        if (_activeCatId != null) {
                          _loadItemsForCategory(
                            _activeCatId!,
                            loadMore: true,
                          );
                        }
                      },
                child: MouseRegion(
                  cursor: (!isLoading && hasMore)
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLoading)
                        const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _C.primary,
                          ),
                        )
                      else
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: hasMore ? _C.primary : _C.textSecondary,
                        ),
                      const SizedBox(width: 4),
                      Text(
                        isLoading
                            ? 'Loading...'
                            : hasMore
                                ? '$loadedCount items loaded  ·  tap to load more'
                                : 'All $totalCount items loaded',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasMore ? _C.primary : _C.textSecondary,
                          fontWeight: hasMore ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Bottom Bar ───────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _C.panelBg,
        border: Border(top: BorderSide(color: _C.border)),
      ),
      child: Row(
        children: [
          // Back button
          OutlinedButton.icon(
            onPressed: () => MainLayoutScope.of(context).switchPage(0),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Back'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _C.textSecondary,
              side: const BorderSide(color: _C.border),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          const Spacer(),
          // Run Forecast button — returns immediately, job tracked on Dashboard
          ElevatedButton.icon(
            onPressed: _runForecastLoading ? null : _runForecast,
            icon: _runForecastLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow, size: 16),
            label: Text(_runForecastLoading ? 'Creating Job...' : 'Run Forecast'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Custom filter dropdown ─────────────────────────────────────────────────
// Uses showMenu() anchored strictly BELOW the button so the label is NEVER
// hidden when the menu is open.
class _FilterDropdown extends StatefulWidget {
  final String hint;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChange;

  const _FilterDropdown({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChange,
  });

  @override
  State<_FilterDropdown> createState() => _FilterDropdownState();
}

class _FilterDropdownState extends State<_FilterDropdown> {
  final _key = GlobalKey();
  bool _isOpen = false;

  Future<void> _open() async {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    // Compute a rect that sits directly below the button
    final topLeft = box.localToGlobal(Offset.zero);
    final size = box.size;
    final rect = RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + size.height, // 0px gap below the button
      topLeft.dx + size.width,
      topLeft.dy + size.height,
    );

    setState(() => _isOpen = true);

    final selected = await showMenu<String>(
      context: context,
      position: rect,
      initialValue: widget.value,
      elevation: 4,
      constraints: BoxConstraints(minWidth: size.width, maxWidth: size.width),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: widget.items
          .map(
            (e) => PopupMenuItem<String>(
              value: e,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                e,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: e == widget.value
                      ? FontWeight.w700
                      : FontWeight.normal,
                ),
              ),
            ),
          )
          .toList(),
    );

    if (!mounted) return;
    setState(() => _isOpen = false);
    if (selected != null) widget.onChange(selected);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = widget.value != null && widget.value!.isNotEmpty;
    return GestureDetector(
      onTap: _open,
      child: Container(
        key: _key,
        padding: const EdgeInsets.fromLTRB(10, 3, 8, 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _isOpen ? _C.primary : _C.border,
            width: _isOpen ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.hint,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _isOpen ? _C.primary : _C.textSecondary,
                    ),
                  ),
                  if (hasValue) ...[
                    const SizedBox(height: 1),
                    Text(
                      widget.value!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _C.textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            AnimatedRotation(
              turns: _isOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: _C.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
