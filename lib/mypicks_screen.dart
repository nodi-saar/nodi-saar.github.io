import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'storage.dart';
import 'firebase.dart';
import 'models.dart';
import 'webview_screen.dart';
import 'platform_badge.dart';
import 'title_search_screen.dart';

class MyPicksScreen extends StatefulWidget {
  const MyPicksScreen({super.key});

  @override
  State<MyPicksScreen> createState() => MyPicksScreenState();
}

class MyPicksScreenState extends State<MyPicksScreen> {
  List<WatchItem> _items = [];
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await AppStorage.getItems();
    items.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    setState(() => _items = items);
  }

  Future<void> _openWebView(String platform) async {
    final result = await Navigator.push<WebViewResult>(
      context,
      MaterialPageRoute(builder: (_) => WebViewScreen(platform: platform)),
    );
    if (result != null && result.hasChanges) await _applyWebViewResult(result);
  }

  Future<void> _applyWebViewResult(WebViewResult result) async {
    // 1. Compute updated list and show on UI immediately
    final removeSet = result.toRemove;
    final updated = _items.where((i) => !removeSet.contains(i.href)).toList();
    for (final item in result.toAdd) {
      if (!updated.any((i) => i.href == item.href)) updated.add(item);
    }
    updated.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    setState(() => _items = updated);

    // 2. Persist to local storage
    await AppStorage.setItems(updated);

    // 3. Sync to Firestore, then notify followers and show share popup
    await _syncToFirestoreAndNotify(updated);
  }

  Future<void> _syncToFirestoreAndNotify(List<WatchItem> items) async {
    if (items.isEmpty) return;
    setState(() => _syncing = true);
    try {
      final newItems = await FirebaseService.syncItems(items);
      if (newItems.isNotEmpty) FirebaseService.notifyFollowers(newItems); // fire-and-forget
    } catch (_) {
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
    if (mounted) _showSharePrompt();
  }

  void _showSharePrompt() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17171c),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('List saved! 🎉',
                style: TextStyle(fontFamily: 'Syne',
                    fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
            const SizedBox(height: 8),
            const Text('Share your picks with friends so they can see what you\'ve been watching.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF7a7a8c), fontSize: 13)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ).copyWith(
                  backgroundColor: WidgetStateProperty.all(Colors.transparent),
                  overlayColor: WidgetStateProperty.all(Colors.white12),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  shareList();
                },
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFe50914), Color(0xFF00a8e1)]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    heightFactor: 1,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Share with Friends',
                          style: TextStyle(fontFamily: 'Syne',
                              fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Maybe later',
                  style: TextStyle(color: Color(0xFF7a7a8c), fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> shareList() async {
    String? username = await AppStorage.getUsername();
    if (username == null || username.isEmpty) {
      final entered = await _showUsernameSheet();
      if (entered == null) return;
      username = entered;
      debugPrint('[Nodisaar] Username set by user: $username');
      FirebaseService.saveUsername(username); // push username to Firestore (fire-and-forget)
    }
    final docId = await AppStorage.getDocId();
    if (docId == null) {
      debugPrint('[Nodisaar] shareList: no docId, cannot share');
      return;
    }
    final url = 'https://nodi-saar.pocha.fyi/user/$username/$docId';
    debugPrint('[Nodisaar] Sharing URL: $url');
    await Share.share(
      'Check out my OTT favourites on Nodisaar! 🍿\n$url\n\n'
      'Install the app to see my full list & add your own picks.',
    );
  }

  Future<String?> _showUsernameSheet() async {
    final ctrl = TextEditingController();
    String? err;
    bool checking = false;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF17171c),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Choose a username',
                  style: TextStyle(fontFamily: 'Syne',
                      fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
              const SizedBox(height: 6),
              const Text('Friends will see this name next to your picks.',
                  style: TextStyle(color: Color(0xFF7a7a8c), fontSize: 13)),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g. rahul_jp',
                  hintStyle: const TextStyle(color: Color(0xFF7a7a8c)),
                  filled: true,
                  fillColor: const Color(0xFF0e0e11),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF2a2a33))),
                  errorText: err,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00a8e1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: checking ? null : () async {
                    final name = ctrl.text.trim().toLowerCase();
                    if (name.isEmpty) return;
                    setBS(() { err = null; checking = true; });
                    final available = await FirebaseService.checkUsername(name);
                    if (!available) {
                      setBS(() { err = 'Username taken, try another'; checking = false; });
                      return;
                    }
                    await AppStorage.setUsername(name);
                    if (ctx.mounted) Navigator.pop(ctx, name);
                  },
                  child: checking
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Confirm',
                          style: TextStyle(fontFamily: 'Syne',
                              fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removeItem(WatchItem item) async {
    await AppStorage.removeItem(item.href);
    await _load();
    // Sync deletion to Firestore
    final items = await AppStorage.getItems();
    FirebaseService.syncItems(items);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0e0e11),
      body: _items.isEmpty
          ? _emptyState()
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: _items.length,
              itemBuilder: (_, i) => _ItemTile(
                item: _items[i],
                onRemove: () => _removeItem(_items[i]),
              ),
            ),
      floatingActionButton: _syncing
          ? const FloatingActionButton(
              onPressed: null,
              backgroundColor: Color(0xFF2a2a33),
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          : FloatingActionButton(
              backgroundColor: Colors.transparent,
              elevation: 0,
              onPressed: _showAddOptions,
              child: Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFe50914), Color(0xFF00a8e1)]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
    );
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17171c),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('Add from watch history',
                style: TextStyle(fontFamily: 'Syne',
                    fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
            const SizedBox(height: 16),
            _PlatformOption(
              label: 'Netflix',
              iconAsset: 'assets/icon/netflix-logo.png',
              color: const Color(0xFFe50914),
              onTap: () { Navigator.pop(context); _openWebView('netflix'); },
            ),
            const Divider(height: 1, color: Color(0xFF2a2a33)),
            _PlatformOption(
              label: 'Prime Video',
              iconAsset: 'assets/icon/prime-logo.png',
              color: const Color(0xFF00a8e1),
              onTap: () { Navigator.pop(context); _openWebView('prime'); },
            ),
            const Divider(height: 1, color: Color(0xFF2a2a33)),
            _PlatformOption(
              label: 'Other',
              icon: Icons.add_circle_outline,
              color: const Color(0xFF7a7a8c),
              onTap: () { Navigator.pop(context); _showManualAddSheet(); },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _showManualAddSheet() async {
    final nameCtrl = TextEditingController();
    String? selectedSource;
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF17171c),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add a pick',
                    style: TextStyle(fontFamily: 'Syne',
                        fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
                const SizedBox(height: 6),
                const Text('Add a title from any platform manually.',
                    style: TextStyle(color: Color(0xFF7a7a8c), fontSize: 13)),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () async {
                    final result = await Navigator.push<TitleSearchResult>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const TitleSearchScreen()),
                    );
                    if (result != null) {
                      nameCtrl.text = result.title;
                      setBS(() {
                        if (result.source.isNotEmpty) {
                          selectedSource = result.source;
                        }
                      });
                    }
                  },
                  child: AbsorbPointer(
                    child: TextFormField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Title',
                        labelStyle: const TextStyle(color: Color(0xFF7a7a8c)),
                        hintText: 'Tap to search titles',
                        hintStyle: const TextStyle(color: Color(0xFF7a7a8c)),
                        filled: true,
                        fillColor: const Color(0xFF0e0e11),
                        suffixIcon: const Icon(Icons.search,
                            color: Color(0xFF7a7a8c)),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFF2a2a33))),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Tap to search and select a title'
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedSource,
                  dropdownColor: const Color(0xFF17171c),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Platform',
                    labelStyle: const TextStyle(color: Color(0xFF7a7a8c)),
                    filled: true,
                    fillColor: const Color(0xFF0e0e11),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF2a2a33))),
                  ),
                  items: _kOttSources.map((s) => DropdownMenuItem(
                    value: s.id,
                    child: Row(
                      children: [
                        PlatformIcon(source: s.id, size: 24),
                        const SizedBox(width: 10),
                        Text(s.label,
                            style: const TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  )).toList(),
                  onChanged: (v) => setBS(() => selectedSource = v),
                  validator: (v) => v == null ? 'Select a platform' : null,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00a8e1),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final title = nameCtrl.text.trim();
                      final source = selectedSource!;
                      final item = WatchItem(
                        title: title,
                        href: 'manual_${DateTime.now().millisecondsSinceEpoch}',
                        source: source,
                        viewedAt: DateTime.now(),
                        addedAt: DateTime.now(),
                      );
                      await AppStorage.addItem(item);
                      debugPrint('[Nodisaar] Manual item added: $title ($source)');
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _load();
                      if (mounted) await _syncToFirestoreAndNotify(_items);
                    },
                    child: const Text('Add to my picks',
                        style: TextStyle(fontFamily: 'Syne',
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('🎬', style: TextStyle(fontSize: 48)),
        SizedBox(height: 16),
        Text('No picks yet',
            style: TextStyle(fontFamily: 'Syne',
                fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
        SizedBox(height: 8),
        Text('Tap + to add from Netflix, Prime, or any platform',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF7a7a8c), fontSize: 13)),
      ],
    ),
  );
}

// ── OTT source catalogue ───────────────────────────────────────────────────────
class _OttSource {
  final String id;
  final String label;
  const _OttSource(this.id, this.label);
}

const _kOttSources = [
  _OttSource('appletv',     'Apple TV+'),
  _OttSource('crunchyroll', 'Crunchyroll'),
  _OttSource('discovery',   'Discovery+'),
  _OttSource('hulu',        'Hulu'),
  _OttSource('jiohotstar',  'JioHotstar'),
  _OttSource('max',         'Max'),
  _OttSource('mxplayer',    'MX Player'),
  _OttSource('netflix',     'Netflix'),
  _OttSource('paramount',   'Paramount+'),
  _OttSource('prime',       'Prime Video'),
  _OttSource('sonyliv',     'SonyLIV'),
  _OttSource('youtube',     'YouTube Premium'),
  _OttSource('zee5',        'Zee5'),
];

// ── Item tile ──────────────────────────────────────────────────────────────────
class _ItemTile extends StatelessWidget {
  final WatchItem item;
  final VoidCallback onRemove;
  const _ItemTile({required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMM yyyy').format(item.viewedAt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2a2a33))),
      ),
      child: Row(
        children: [
          PlatformIcon(source: item.source),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(dateStr,
                    style: const TextStyle(
                        color: Color(0xFF7a7a8c), fontSize: 12)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Text('×',
                  style: TextStyle(color: Color(0xFF7a7a8c), fontSize: 22)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Platform option row (in add sheet) ────────────────────────────────────────
class _PlatformOption extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final String? iconAsset;
  final IconData? icon;
  const _PlatformOption({
    required this.label,
    required this.color,
    required this.onTap,
    this.iconAsset,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    Widget leading = Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(6),
      child: iconAsset != null
          ? Image.asset(iconAsset!, fit: BoxFit.contain)
          : Icon(icon ?? Icons.add, color: color, size: 22),
    );
    return ListTile(
      onTap: onTap,
      leading: leading,
      title: Text(label,
          style: const TextStyle(color: Colors.white,
              fontFamily: 'Syne', fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF7a7a8c)),
    );
  }
}