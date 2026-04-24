import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'mypicks_screen.dart';
import 'friends_screen.dart';
import 'top_picks_screen.dart';

class HomeScreen extends StatefulWidget {
  final String? incomingFriendUsername;
  final bool openFriendsTab;
  const HomeScreen({super.key, this.incomingFriendUsername, this.openFriendsTab = false});

  // Notifier for triggering Friends tab refresh (FCM foreground message)
  static final friendsTabNotifier = _SimpleNotifier();

  // Called from main.dart when a notification tap should open Friends tab
  static final _goFriendsTabNotifier = ValueNotifier(false);
  static void goFriendsTab() {
    _goFriendsTabNotifier.value = !_goFriendsTabNotifier.value;
  }

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _SimpleNotifier extends ChangeNotifier {
  void notifyListeners() => super.notifyListeners();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _myPicksKey = GlobalKey<MyPicksScreenState>();
  final _friendsKey = GlobalKey<FriendsScreenState>();
  final _topPicksKey = GlobalKey<TopPicksScreenState>();
  String _version = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    PackageInfo.fromPlatform().then(
      (info) { if (mounted) setState(() => _version = info.version); },
    );

    if (widget.incomingFriendUsername != null || widget.openFriendsTab) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _tabController.animateTo(1),
      );
    }

    _tabController.addListener(_onTabChanged);
    HomeScreen._goFriendsTabNotifier.addListener(_onGoFriendsTab);
    HomeScreen.friendsTabNotifier.addListener(_onFriendPicksReceived);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    HomeScreen._goFriendsTabNotifier.removeListener(_onGoFriendsTab);
    HomeScreen.friendsTabNotifier.removeListener(_onFriendPicksReceived);
    _tabController.dispose();
    super.dispose();
  }

  bool _pendingFriendsReload = false;

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 1 && _pendingFriendsReload) {
      _pendingFriendsReload = false;
      _friendsKey.currentState?.reload();
    }
    if (_tabController.index == 2) {
      _topPicksKey.currentState?.reload();
    }
  }

  void _onGoFriendsTab() {
    _tabController.animateTo(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _friendsKey.currentState?.reload();
    });
  }

  void _onFriendPicksReceived() {
    if (_friendsKey.currentState != null) {
      _friendsKey.currentState!.reload();
    } else {
      _pendingFriendsReload = true;
    }
  }

  Future<void> _onShareTapped() async {
    await _myPicksKey.currentState?.shareList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0e0e11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0e0e11),
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFFe50914), Color(0xFF00a8e1)],
              ).createShader(bounds),
              child: const Text('Nodisaar',
                  style: TextStyle(
                      fontFamily: 'Syne',
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: Colors.white)),
            ),
            if (_version.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text('v$_version',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF7a7a8c),
                      fontWeight: FontWeight.w500)),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Color(0xFF7a7a8c)),
            tooltip: 'Share my picks',
            onPressed: _onShareTapped,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF00a8e1),
          unselectedLabelColor: const Color(0xFF7a7a8c),
          indicatorColor: const Color(0xFF00a8e1),
          labelStyle: const TextStyle(
              fontFamily: 'Syne', fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'My Picks'),
            Tab(text: "Friends' Picks"),
            Tab(text: 'Top Picks'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          MyPicksScreen(key: _myPicksKey),
          FriendsScreen(key: _friendsKey, incomingUsername: widget.incomingFriendUsername),
          TopPicksScreen(key: _topPicksKey),
        ],
      ),
    );
  }
}