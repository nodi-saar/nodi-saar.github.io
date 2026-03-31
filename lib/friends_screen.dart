import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'storage.dart';
import 'firebase.dart';
import 'models.dart';

class FriendsScreen extends StatefulWidget {
  final String? incomingFriend;
  const FriendsScreen({super.key, this.incomingFriend});

  @override
  State<FriendsScreen> createState() => FriendsScreenState();
}

class FriendsScreenState extends State<FriendsScreen> {
  List<WatchItem> _items = [];
  bool _loading = false;

 @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.incomingFriend != null) {
      await AppStorage.addFriendUsername(widget.incomingFriend!);
    }
    _load();
  }

  Future<void> _load() async {
    final friends = await AppStorage.getFriendUsernames();
    if (friends.isEmpty) {
      setState(() => _items = []);
      return;
    }

    setState(() => _loading = true);
    try {
      final results = await Future.wait(
        friends.map((u) => FirebaseService.fetchFriendItems(u)),
      );
      final merged = results.expand((list) => list).toList();
      merged.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
      setState(() => _items = merged);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: _items.length,
        itemBuilder: (_, i) => _FriendItemTile(item: _items[i]),
      ),
    );
  }
}

// ── Friend item tile ───────────────────────────────────────────────────────────
class _FriendItemTile extends StatelessWidget {
  final WatchItem item;
  const _FriendItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final isNetflix = item.source == 'netflix';
    final dateStr = DateFormat('d MMM yyyy').format(item.viewedAt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2a2a33))),
      ),
      child: Row(
        children: [
          // Platform indicator
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: isNetflix
                  ? const Color(0xFFe50914).withOpacity(0.15)
                  : const Color(0xFF00a8e1).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Image.asset(
                isNetflix ? 'assets/icon/netflix-logo.png' : 'assets/icon/prime-logo.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Title + date
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
          // Friend username badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF00a8e1).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFF00a8e1).withOpacity(0.3)),
            ),
            child: Text(
              item.friendUsername ?? '',
              style: const TextStyle(
                  color: Color(0xFF00a8e1),
                  fontSize: 11,
                  fontFamily: 'Syne',
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}