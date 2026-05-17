import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/marketplace_ui.dart' show AppearOnMount, ShimmerBox, staggerDelay;
import '../utils/page_transitions.dart';
import 'productdet.dart';
import 'seller_profile_page.dart';

const _kPrimary = Color(0xFF2A4BA0);
const _kPrimaryDark = Color(0xFF153075);
const _kAccent = Color(0xFFF5A524);
const _kSurface = Color(0xFFF5F6FB);
const _kTextStrong = Color(0xFF111827);
const _kTextMuted = Color(0xFF6B7280);
const _kLine = Color(0xFFE8EDF6);

const String _kRecentSearchesKey = 'quickcart.recent_searches.v1';
const int _kMaxRecent = 8;

/// Dedicated full-screen search experience, modeled on Shopee/Lazada/
/// Foodpanda patterns: tap-to-open, sticky header, discovery state before
/// typing, debounced live results, skeleton loaders, persistent recent
/// searches. Lives outside the home page so the hero banner never bleeds
/// through during search.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.initialQuery, this.heroTag});

  final String? initialQuery;
  final String? heroTag;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final SupabaseClient _supabase = Supabase.instance.client;

  Timer? _debounce;
  Timer? _historyTimer;
  String _query = '';
  bool _isSearching = false; // a query is being executed
  bool _hasQuery = false; // current text is non-empty
  int _searchToken = 0; // discards stale responses

  List<Map<String, dynamic>> _resultProducts = [];
  List<Map<String, dynamic>> _resultStores = [];
  List<String> _resultCategories = [];

  // Discovery data
  bool _isLoadingDiscovery = true;
  List<Map<String, dynamic>> _trendingStores = [];
  List<String> _suggestedCategories = [];
  List<String> _recentSearches = [];

  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    final curved = CurvedAnimation(
      parent: _entryCtrl,
      curve: Curves.easeOutCubic,
    );
    _entryFade = Tween<double>(begin: 0, end: 1).animate(curved);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(curved);
    _entryCtrl.forward();

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _controller.text = initial;
      _query = initial;
      _hasQuery = true;
      _runSearch(initial);
    }

    // Discovery data + recent searches load in parallel.
    await Future.wait([
      _loadRecentSearches(),
      _loadDiscoveryData(),
    ]);

    if (mounted && initial.isEmpty) {
      // Pop the keyboard after the first frame so the Hero animation isn't
      // fighting with the keyboard slide.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _historyTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  // ── Persistence ───────────────────────────────────────────────────────

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kRecentSearchesKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        if (!mounted) return;
        setState(() {
          _recentSearches = decoded
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .take(_kMaxRecent)
              .toList();
        });
      }
    } catch (_) {
      // Corrupted prefs — ignore.
    }
  }

  Future<void> _persistRecent(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return;
    final lower = trimmed.toLowerCase();
    final next = [
      trimmed,
      ..._recentSearches.where((s) => s.toLowerCase() != lower),
    ].take(_kMaxRecent).toList();
    if (!mounted) return;
    setState(() => _recentSearches = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRecentSearchesKey, jsonEncode(next));
    } catch (_) {}
  }

  Future<void> _removeRecent(String query) async {
    final lower = query.toLowerCase();
    if (!mounted) return;
    setState(
      () => _recentSearches.removeWhere((s) => s.toLowerCase() == lower),
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRecentSearchesKey, jsonEncode(_recentSearches));
    } catch (_) {}
  }

  Future<void> _clearAllRecent() async {
    if (!mounted) return;
    setState(() => _recentSearches = []);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kRecentSearchesKey);
    } catch (_) {}
  }

  // ── Discovery data ────────────────────────────────────────────────────

  Future<void> _loadDiscoveryData() async {
    try {
      // We still pull a slice of products to derive a "Browse by category"
      // chip set — but we no longer surface a Trending-products grid here,
      // since results show up the moment the user types.
      final productsFuture = _supabase
          .from('product')
          .select('category')
          .order('id', ascending: false)
          .limit(40);

      final storesFuture = _supabase
          .from('seller_profiles')
          .select(
            'user_id, store_name, logo_url, banner_url, category, is_open, opening_time, closing_time, delivery_enabled, is_featured',
          )
          .eq('approval_status', 'approved')
          .order('is_featured', ascending: false)
          .order('created_at', ascending: false)
          .limit(8);

      final results = await Future.wait([productsFuture, storesFuture]);

      final products = results[0] as List;
      final stores = List<Map<String, dynamic>>.from(results[1]);
      final categories = <String>{};
      for (final p in products) {
        if (p is Map) {
          final c = (p['category'] ?? '').toString().trim();
          if (c.isNotEmpty) categories.add(c);
        }
      }
      final sortedCats = categories.toList()..sort();

      if (!mounted) return;
      setState(() {
        _trendingStores = stores;
        _suggestedCategories = sortedCats.take(8).toList();
        _isLoadingDiscovery = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingDiscovery = false);
    }
  }

  List<dynamic> _hideSuspendedSellerProducts(dynamic raw) {
    final list = raw is List ? raw : const <dynamic>[];
    return list.where((item) {
      if (item is! Map) return true;
      final sp = item['seller_profiles'];
      if (sp is! Map) return true;
      final status = sp['approval_status']?.toString().toLowerCase();
      return status != 'suspended' && status != 'rejected';
    }).toList();
  }

  // ── Search execution ──────────────────────────────────────────────────

  void _onChanged(String value) {
    final trimmed = value.trim();
    final hasQuery = trimmed.isNotEmpty;

    // Cancel any debounced history-save from a previous typing session.
    _historyTimer?.cancel();

    if (!hasQuery) {
      _debounce?.cancel();
      setState(() {
        _query = '';
        _hasQuery = false;
        _isSearching = false;
        _resultProducts = [];
        _resultStores = [];
        _resultCategories = [];
      });
      return;
    }

    setState(() {
      _query = trimmed;
      _hasQuery = true;
      _isSearching = true;
    });

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      _runSearch(trimmed);
    });
  }

  Future<void> _runSearch(String query) async {
    final token = ++_searchToken;
    try {
      final like = '%${query.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      final productsFuture = _supabase
          .from('product')
          .select(
            '*, seller_profiles!product_seller_id_fkey(store_name, is_open, opening_time, closing_time, delivery_enabled, logo_url, approval_status)',
          )
          .or(
            'name.ilike.$like,description.ilike.$like,category.ilike.$like',
          )
          .order('id', ascending: false)
          .limit(40);

      final storesFuture = _supabase
          .from('seller_profiles')
          .select(
            'user_id, store_name, logo_url, banner_url, category, is_open, opening_time, closing_time, delivery_enabled, is_featured',
          )
          .eq('approval_status', 'approved')
          .or('store_name.ilike.$like,category.ilike.$like')
          .limit(12);

      final results = await Future.wait([productsFuture, storesFuture]);

      if (!mounted || token != _searchToken) return;
      final rawProducts = _hideSuspendedSellerProducts(results[0]);
      final products = rawProducts
          .whereType<Map>()
          .map((p) => Map<String, dynamic>.from(p))
          .toList();
      final stores = List<Map<String, dynamic>>.from(results[1]);

      // Categories matching the query — derived from product rows we got.
      final cats = <String>{};
      for (final p in products) {
        final c = (p['category'] ?? '').toString().trim();
        if (c.isNotEmpty && c.toLowerCase().contains(query.toLowerCase())) {
          cats.add(c);
        }
      }

      setState(() {
        _resultProducts = products;
        _resultStores = stores;
        _resultCategories = cats.toList()..sort();
        _isSearching = false;
      });

      // Save to history a beat after results settle so we don't store
      // every keystroke. Only persist if the user keeps the same query.
      _historyTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted && _query == query) _persistRecent(query);
      });
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      setState(() => _isSearching = false);
    }
  }

  void _submitQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _controller.text = trimmed;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: trimmed.length),
    );
    _focusNode.unfocus();
    _onChanged(trimmed);
    // Force-save now since the user intentionally submitted.
    _persistRecent(trimmed);
  }

  void _clearInput() {
    HapticFeedback.selectionClick();
    _controller.clear();
    _onChanged('');
    _focusNode.requestFocus();
  }

  /// Responsive grid delegate sized to the actual viewport. Image area is
  /// AspectRatio(1.05) of the card width; the details strip (name + store
  /// row with logo + price row) needs ~108px, so we compute the extent
  /// proportionally instead of clamping with a fixed `mainAxisExtent` that
  /// breaks on wider phones / tablets.
  SliverGridDelegate _gridDelegateFor(double available) {
    const spacing = 12.0;
    final crossAxisCount = available >= 900
        ? 5
        : available >= 720
            ? 4
            : available >= 540
                ? 3
                : 2;
    final cardWidth =
        (available - spacing * (crossAxisCount - 1)) / crossAxisCount;
    final imageHeight = cardWidth / 1.05;
    const detailsHeight = 108.0;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: spacing,
      mainAxisSpacing: 14,
      mainAxisExtent: imageHeight + detailsHeight,
    );
  }

  // ── Navigation helpers ────────────────────────────────────────────────

  Future<void> _openProduct(Map<String, dynamic> product) async {
    await Navigator.push(
      context,
      fadeSlideRoute(
        (_) => ProductViewPage(product: Map<String, dynamic>.from(product)),
      ),
    );
  }

  void _openStore(Map<String, dynamic> store) {
    final sellerId =
        (store['user_id'] ?? store['seller_id'])?.toString() ?? '';
    if (sellerId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SellerProfilePage(
          sellerId: sellerId,
          initialStoreName: store['store_name']?.toString(),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildSearchHeader(),
            Expanded(
              child: FadeTransition(
                opacity: _entryFade,
                child: SlideTransition(
                  position: _entrySlide,
                  child: _buildBody(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_hasQuery) {
      return _buildDiscoveryView();
    }
    if (_isSearching) {
      return _buildLoadingState();
    }
    final hasAny = _resultProducts.isNotEmpty ||
        _resultStores.isNotEmpty ||
        _resultCategories.isNotEmpty;
    if (!hasAny) {
      return _buildNoResultsState();
    }
    return _buildResultsView();
  }

  // ── Search header (sticky) ────────────────────────────────────────────

  Widget _buildSearchHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: _kLine, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 12),
      child: Row(
        children: [
          _BackPill(onTap: () => Navigator.maybePop(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Hero(
              tag: widget.heroTag ?? 'quickcart-search-bar',
              flightShuttleBuilder: (_, _, _, _, _) =>
                  Material(color: Colors.transparent, child: _searchField()),
              child: Material(
                color: Colors.transparent,
                child: _searchField(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kLine),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: _kPrimary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              cursorColor: _kPrimary,
              cursorHeight: 18,
              onChanged: _onChanged,
              onSubmitted: _submitQuery,
              style: const TextStyle(
                color: _kTextStrong,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search products, stores, categories…',
                hintStyle: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: _hasQuery
                ? Material(
                    key: const ValueKey('clear'),
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _clearInput,
                      splashColor: const Color(0x222A4BA0),
                      child: Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.close_rounded,
                          color: _kTextMuted,
                          size: 18,
                        ),
                      ),
                    ),
                  )
                : const SizedBox(key: ValueKey('empty'), width: 30, height: 30),
          ),
        ],
      ),
    );
  }

  // ── Discovery view (no query yet) ─────────────────────────────────────

  Widget _buildDiscoveryView() {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (_recentSearches.isNotEmpty)
          SliverToBoxAdapter(
            child: _buildRecentSection(),
          ),
        if (_isLoadingDiscovery)
          SliverToBoxAdapter(child: _buildDiscoverySkeleton())
        else ...[
          if (_suggestedCategories.isNotEmpty)
            SliverToBoxAdapter(child: _buildCategoriesSection()),
          if (_trendingStores.isNotEmpty)
            SliverToBoxAdapter(child: _buildTrendingStoresSection()),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildRecentSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, size: 16, color: _kTextStrong),
              const SizedBox(width: 6),
              const Text(
                'Recent searches',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: _kTextStrong,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _clearAllRecent,
                style: TextButton.styleFrom(
                  foregroundColor: _kPrimary,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text(
                  'Clear all',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recentSearches
                .map((q) => _RecentChip(
                      label: q,
                      onTap: () => _submitQuery(q),
                      onRemove: () => _removeRecent(q),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.category_rounded, size: 16, color: _kPrimary),
              SizedBox(width: 6),
              Text(
                'Browse by category',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: _kTextStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestedCategories
                .map((c) => _CategoryChip(
                      label: c,
                      onTap: () => _submitQuery(c),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendingStoresSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.storefront_rounded, size: 16, color: _kPrimary),
                SizedBox(width: 6),
                Text(
                  'Trending stores',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _kTextStrong,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 108,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _trendingStores.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final store = _trendingStores[i];
                return AppearOnMount(
                  delay: staggerDelay(i, step: 55),
                  child: _TrendingStoreCard(
                    store: store,
                    onTap: () => _openStore(store),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Results view ──────────────────────────────────────────────────────

  Widget _buildResultsView() {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(child: _buildResultsSummary()),
        if (_resultCategories.isNotEmpty)
          SliverToBoxAdapter(
            child: _buildCategoryMatches(),
          ),
        if (_resultStores.isNotEmpty)
          SliverToBoxAdapter(child: _buildStoreResults()),
        if (_resultProducts.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: _sectionLabel(
                Icons.shopping_bag_outlined,
                'Products',
                _resultProducts.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) => SliverGrid.builder(
                gridDelegate:
                    _gridDelegateFor(constraints.crossAxisExtent),
                itemCount: _resultProducts.length,
                itemBuilder: (context, i) {
                  final p = _resultProducts[i];
                  return AppearOnMount(
                    delay: staggerDelay(i, step: 35),
                    child: _ProductGridCard(
                      product: p,
                      onTap: () => _openProduct(p),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResultsSummary() {
    final parts = <String>[];
    if (_resultStores.isNotEmpty) {
      parts.add(
        '${_resultStores.length} ${_resultStores.length == 1 ? "store" : "stores"}',
      );
    }
    if (_resultProducts.isNotEmpty) {
      parts.add(
        '${_resultProducts.length} ${_resultProducts.length == 1 ? "product" : "products"}',
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFD7E2FF)),
        ),
        child: Text(
          '${parts.join(' · ')} for "$_query"',
          style: const TextStyle(
            color: _kPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryMatches() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(
            Icons.category_rounded,
            'Categories',
            _resultCategories.length,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _resultCategories
                .map((c) => _CategoryChip(
                      label: c,
                      onTap: () => _submitQuery(c),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreResults() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(
            Icons.storefront_rounded,
            'Stores',
            _resultStores.length,
          ),
          const SizedBox(height: 10),
          ..._resultStores.asMap().entries.map(
                (e) => AppearOnMount(
                  delay: staggerDelay(e.key, step: 45),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _StoreResultRow(
                      store: e.value,
                      onTap: () => _openStore(e.value),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _sectionLabel(IconData icon, String label, int count) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _kPrimary),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: _kTextStrong,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: _kPrimary,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  // ── Loading / empty states ────────────────────────────────────────────

  Widget _buildLoadingState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        ShimmerBox(
          height: 32,
          width: 220,
          borderRadius: BorderRadius.circular(999),
        ),
        const SizedBox(height: 18),
        ...List.generate(
          2,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _StoreResultRow.skeleton(),
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: _gridDelegateFor(constraints.maxWidth),
            itemCount: 4,
            itemBuilder: (_, _) => _ProductGridCard.skeleton(),
          ),
        ),
      ],
    );
  }

  Widget _buildDiscoverySkeleton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBox(
            height: 14,
            width: 140,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, _) => ShimmerBox(
                height: 108,
                width: 140,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 22),
          ShimmerBox(
            height: 14,
            width: 100,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
              mainAxisExtent: 232,
            ),
            itemCount: 2,
            itemBuilder: (_, _) => _ProductGridCard.skeleton(),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
          child: Column(
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: const BoxDecoration(
                  color: Color(0xFFEEF2FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.search_off_rounded,
                  size: 48,
                  color: _kPrimary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'No matches for "$_query"',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: _kTextStrong,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _suggestedCategories.isEmpty
                    ? 'Try a different spelling.'
                    : 'Try a different spelling, or pick a category below.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: _kTextMuted,
                  height: 1.45,
                ),
              ),
              if (_suggestedCategories.isNotEmpty) ...[
                const SizedBox(height: 22),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: _suggestedCategories
                      .take(6)
                      .map((c) => _CategoryChip(
                            label: c,
                            onTap: () => _submitQuery(c),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────

class _BackPill extends StatelessWidget {
  const _BackPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        splashColor: const Color(0x222A4BA0),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: const Icon(
            Icons.arrow_back_rounded,
            color: _kTextStrong,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({
    required this.label,
    required this.onTap,
    required this.onRemove,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        splashColor: const Color(0x222A4BA0),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _kLine),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.history_rounded,
                size: 13,
                color: _kTextMuted,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _kTextStrong,
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: _kTextMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        splashColor: const Color(0x222A4BA0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFD7E2FF)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: _kPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendingStoreCard extends StatelessWidget {
  const _TrendingStoreCard({required this.store, required this.onTap});
  final Map<String, dynamic> store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = store['store_name']?.toString() ?? 'Market Stall';
    final logoUrl = store['logo_url']?.toString().trim() ?? '';
    final featured = store['is_featured'] == true;
    final isOpen = store['is_open'] == true;
    return SizedBox(
      width: 152,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          splashColor: const Color(0x222A4BA0),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kLine),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F0F172A),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE0E7FF)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: logoUrl.isNotEmpty
                          ? Image.network(
                              logoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.storefront_rounded,
                                color: _kPrimary,
                                size: 20,
                              ),
                            )
                          : const Icon(
                              Icons.storefront_rounded,
                              color: _kPrimary,
                              size: 20,
                            ),
                    ),
                    if (featured) ...[
                      const Spacer(),
                      const Icon(
                        Icons.star_rounded,
                        color: _kAccent,
                        size: 16,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: _kTextStrong,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 6,
                      color: isOpen
                          ? const Color(0xFF059669)
                          : const Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isOpen ? 'Open now' : 'Closed',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: isOpen
                            ? const Color(0xFF059669)
                            : const Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreResultRow extends StatelessWidget {
  const _StoreResultRow({required this.store, required this.onTap})
      : _skeleton = false;
  const _StoreResultRow.skeleton()
      : store = const {},
        onTap = _noop,
        _skeleton = true;

  static void _noop() {}

  final Map<String, dynamic> store;
  final VoidCallback onTap;
  final bool _skeleton;

  @override
  Widget build(BuildContext context) {
    if (_skeleton) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kLine),
        ),
        child: Row(
          children: [
            ShimmerBox(
              height: 48,
              width: 48,
              borderRadius: BorderRadius.circular(12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(
                    height: 12,
                    width: double.infinity,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  const SizedBox(height: 8),
                  ShimmerBox(
                    height: 10,
                    width: 120,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final name = store['store_name']?.toString() ?? 'Market Stall';
    final isOpen = store['is_open'] == true;
    final deliveryEnabled = store['delivery_enabled'] == true;
    final logoUrl = store['logo_url']?.toString().trim() ?? '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        splashColor: const Color(0x222A4BA0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kLine),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0E7FF)),
                ),
                clipBehavior: Clip.antiAlias,
                child: logoUrl.isNotEmpty
                    ? Image.network(
                        logoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.storefront_rounded,
                          color: _kPrimary,
                          size: 24,
                        ),
                      )
                    : const Icon(
                        Icons.storefront_rounded,
                        color: _kPrimary,
                        size: 24,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: _kTextStrong,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _statusPill(
                          label: isOpen ? 'Open now' : 'Closed',
                          color: isOpen
                              ? const Color(0xFF059669)
                              : const Color(0xFFDC2626),
                        ),
                        if (deliveryEnabled) ...[
                          const SizedBox(width: 6),
                          _statusPill(
                            label: 'Delivery',
                            color: _kPrimary,
                            icon: Icons.delivery_dining_rounded,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill({
    required String label,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ] else ...[
            Icon(Icons.circle, size: 6, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductGridCard extends StatelessWidget {
  const _ProductGridCard({required this.product, required this.onTap})
      : _skeleton = false;
  const _ProductGridCard.skeleton()
      : product = const {},
        onTap = _noop,
        _skeleton = true;

  static void _noop() {}

  final Map<String, dynamic> product;
  final VoidCallback onTap;
  final bool _skeleton;

  @override
  Widget build(BuildContext context) {
    if (_skeleton) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kLine),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.05,
              child: ShimmerBox(
                height: double.infinity,
                width: double.infinity,
                borderRadius: BorderRadius.zero,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(
                    height: 11,
                    width: double.infinity,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  const SizedBox(height: 6),
                  ShimmerBox(
                    height: 9,
                    width: 80,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  const SizedBox(height: 10),
                  ShimmerBox(
                    height: 13,
                    width: 70,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final name =
        (product['name'] ?? product['product_name'] ?? 'Fresh Item').toString();
    final imageUrl = (product['image_url'] as String?)?.trim() ?? '';
    final priceValue = product['price'];
    final unit = (product['unit_type'] ?? 'kg').toString();
    final priceText = priceValue != null ? '₱$priceValue /$unit' : '₱0';
    final sp = product['seller_profiles'];
    final storeName = sp is Map
        ? (sp['store_name']?.toString() ?? 'Market Stall')
        : 'Market Stall';
    final logoUrl = sp is Map
        ? (sp['logo_url']?.toString().trim() ?? '')
        : '';
    final categoryLabel = (product['category'] ?? '').toString().trim();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kLine),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: const Color(0x222A4BA0),
          highlightColor: const Color(0x112A4BA0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.05,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _NetworkOrPlaceholder(url: imageUrl),
                    if (categoryLabel.isNotEmpty)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            categoryLabel,
                            style: const TextStyle(
                              color: _kPrimaryDark,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: _kTextStrong,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _SellerLogoBadge(url: logoUrl, storeName: storeName),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            storeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _kTextMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            priceText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: _kPrimaryDark,
                            ),
                          ),
                        ),
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: _kPrimary,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiny rounded-square that shows the seller's real logo next to a store
/// name. Falls back to a colored initial bubble (deterministic per store
/// name) so every card has a distinct visual identity even when the seller
/// hasn't uploaded a logo.
class _SellerLogoBadge extends StatelessWidget {
  const _SellerLogoBadge({required this.url, required this.storeName});

  final String url;
  final String storeName;
  static const double size = 24;

  static const List<(Color, Color)> _palette = [
    (Color(0xFF2A4BA0), Color(0xFF153075)),
    (Color(0xFFEC4899), Color(0xFFBE185D)),
    (Color(0xFF10B981), Color(0xFF047857)),
    (Color(0xFFF59E0B), Color(0xFFB45309)),
    (Color(0xFF8B5CF6), Color(0xFF5B21B6)),
    (Color(0xFF06B6D4), Color(0xFF0E7490)),
    (Color(0xFFEF4444), Color(0xFFB91C1C)),
    (Color(0xFF14B8A6), Color(0xFF0F766E)),
  ];

  (Color, Color) _colorsFor(String name) {
    if (name.isEmpty) return _palette.first;
    var hash = 0;
    for (final code in name.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colorsFor(storeName);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg, fg],
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Text(
        _initial(storeName),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.55,
          height: 1,
        ),
      ),
    );

    if (url.isEmpty) return fallback;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: const Color(0xFFE0E7FF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

class _NetworkOrPlaceholder extends StatelessWidget {
  const _NetworkOrPlaceholder({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const _ImagePlaceholder();
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _ImagePlaceholder(),
      errorBuilder: (_, _, _) => const _ImagePlaceholder(),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF1F3F9),
      child: const Center(
        child: Icon(
          Icons.image_outlined,
          color: Color(0xFFB6BDCC),
          size: 32,
        ),
      ),
    );
  }
}
