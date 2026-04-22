import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'storage.dart';
import 'models.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => FriendsScreenState();
}

class FriendsScreenState extends State<FriendsScreen> {
  List<_MergedItem> _items = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() => _loading = true);
    try {
      final raw = await AppStorage.getAllFriendItems();
      setState(() => _items = _merge(raw));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_MergedItem> _merge(List<WatchItem> items) {
    final map = <String, _MergedItem>{};
    for (final item in items) {
      if (!map.containsKey(item.href)) {
        map[item.href] = _MergedItem(item);
      } else {
        map[item.href]!.merge(item);
      }
    }
    return map.values.toList()
      ..sort((a, b) => b.latestViewedAt.compareTo(a.latestViewedAt));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF00a8e1)));
    }

    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('👥', style: TextStyle(fontSize: 48)),
              SizedBox(height: 16),
              Text("You're not following anyone",
                  style: TextStyle(fontFamily: 'Syne',
                      fontWeight: FontWeight.w700,
                      fontSize: 18, color: Colors.white)),
              SizedBox(height: 8),
              Text(
                "When a friend shares their Nodisaar link with you, "
                "open it to see their favourites here.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF7a7a8c), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF00a8e1),
      onRefresh: reload,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: _items.length,
        itemBuilder: (_, i) => _FriendItemTile(item: _items[i]),
      ),
    );
  }
}

// ── Merged item (same title across multiple friends) ──────────────────────────
class _MergedItem {
  final String title;
  final String href;
  final String source;
  final List<String> friendUsernames = [];
  DateTime latestViewedAt;

  _MergedItem(WatchItem w)
      : title = w.title,
        href = w.href,
        source = w.source,
        latestViewedAt = w.viewedAt {
    if (w.friendUsername != null) friendUsernames.add(w.friendUsername!);
  }

  void merge(WatchItem w) {
    if (w.friendUsername != null && !friendUsernames.contains(w.friendUsername)) {
      friendUsernames.add(w.friendUsername!);
    }
    if (w.viewedAt.isAfter(latestViewedAt)) latestViewedAt = w.viewedAt;
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────
class _FriendItemTile extends StatelessWidget {
  final _MergedItem item;
  const _FriendItemTile({required this.item});

  static Color _colorForSource(String source) {
    const map = {
      'netflix':     Color(0xFFe50914),
      'prime':       Color(0xFF00a8e1),
      'jiohotstar':  Color(0xFF0f62ac),
      'appletv':     Color(0xFF555555),
      'max':         Color(0xFF002be7),
      'hulu':        Color(0xFF1ce783),
      'sonyliv':     Color(0xFF0033ff),
      'zee5':        Color(0xFF7b2d8b),
      'crunchyroll': Color(0xFFf47521),
      'paramount':   Color(0xFF0064ff),
      'mxplayer':    Color(0xFF00c3ff),
      'youtube':     Color(0xFFff0000),
      'discovery':   Color(0xFF0077c8),
    };
    return map[source] ?? const Color(0xFF7a7a8c);
  }

  static String? _assetForSource(String source) {
    const map = {
      'netflix':     'assets/icon/netflix-logo.png',
      'prime':       'assets/icon/prime-logo.png',
      'jiohotstar':  'assets/icon/jiohotstar-logo.png',
      'appletv':     'assets/icon/appletv-logo.png',
      'max':         'assets/icon/max-logo.png',
      'hulu':        'assets/icon/hulu-logo.png',
      'sonyliv':     'assets/icon/sonyliv-logo.png',
      'zee5':        'assets/icon/zee5-logo.png',
      'crunchyroll': 'assets/icon/crunchyroll-logo.png',
      'paramount':   'assets/icon/paramount-logo.png',
      'mxplayer':    'assets/icon/mxplayer-logo.png',
      'youtube':     'assets/icon/youtube-logo.png',
      'discovery':   'assets/icon/discovery-logo.png',
    };
    return map[source];
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForSource(item.source);
    final asset = _assetForSource(item.source);
    final dateStr = DateFormat('d MMM yyyy').format(item.latestViewedAt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2a2a33))),
      ),
      child: Row(
        children: [
          // Platform logo
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(3),
            child: asset != null
                ? Image.asset(asset, fit: BoxFit.contain)
                : Icon(Icons.tv, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          // Title + friend names
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(item.friendUsernames.join(', '),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF7a7a8c), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Latest viewed date
          Text(dateStr,
              style: const TextStyle(
                  color: Color(0xFF7a7a8c), fontSize: 12)),
        ],
      ),
    );
  }
}
