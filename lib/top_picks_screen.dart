import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'platform_badge.dart';

class _TopPickItem {
  final String title;
  final String source;
  final int watchCount;
  const _TopPickItem(this.title, this.source, this.watchCount);
}

class TopPicksScreen extends StatefulWidget {
  const TopPicksScreen({super.key});

  @override
  State<TopPicksScreen> createState() => TopPicksScreenState();
}

class TopPicksScreenState extends State<TopPicksScreen> {
  static const _cacheKey = 'toppicks_cache';
  static const _baseUrl =
      'https://storage.googleapis.com/nodi-saar.firebasestorage.app/toppicks.json';

  List<_TopPickItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      _parse(cached);
      if (mounted) setState(() => _loading = false);
      _fetch(prefs); // background refresh
    } else {
      await _fetch(prefs);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetch(SharedPreferences prefs) async {
    try {
      final url = '$_baseUrl?v=${DateTime.now().millisecondsSinceEpoch}';
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        await prefs.setString(_cacheKey, resp.body);
        _parse(resp.body);
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  // Called by HomeScreen on tab switch and by pull-to-refresh
  Future<void> reload() async {
    final prefs = await SharedPreferences.getInstance();
    await _fetch(prefs);
  }

  void _parse(String json) {
    final list = jsonDecode(json) as List;
    _items = list
        .map((m) => _TopPickItem(
              m['title'] as String? ?? '',
              m['source'] as String? ?? '',
              (m['watchCount'] as num?)?.toInt() ?? 0,
            ))
        .where((p) => p.title.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00a8e1)),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🍿', style: TextStyle(fontSize: 48)),
              SizedBox(height: 16),
              Text('No picks yet',
                  style: TextStyle(
                      fontFamily: 'Syne',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: Colors.white)),
              SizedBox(height: 8),
              Text(
                'Be the first to add your favourites!',
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
        itemBuilder: (_, i) => _TopPickTile(item: _items[i], rank: i + 1),
      ),
    );
  }
}

class _TopPickTile extends StatelessWidget {
  final _TopPickItem item;
  final int rank;
  const _TopPickTile({required this.item, required this.rank});

  @override
  Widget build(BuildContext context) {
    final picksLabel =
        '${item.watchCount} ${item.watchCount == 1 ? 'pick' : 'picks'}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2a2a33))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('$rank',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF7a7a8c),
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          PlatformIcon(source: item.source),
          const SizedBox(width: 12),
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
                Text(labelForSource(item.source),
                    style: const TextStyle(
                        color: Color(0xFF7a7a8c), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(picksLabel,
              style: const TextStyle(
                  color: Color(0xFF00a8e1),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
