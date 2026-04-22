import 'package:flutter/material.dart';
import 'firebase.dart';
import 'notifications.dart';
import 'mypicks_screen.dart';
import 'friends_screen.dart';

class HomeScreen extends StatefulWidget {
  final String? incomingFriendUsername;
  const HomeScreen({super.key, this.incomingFriendUsername});

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    if (widget.incomingFriendUsername != null) {
      _handleIncomingFriend(widget.incomingFriendUsername!);
    }

    // Navigate to Friends tab when notification is tapped
    HomeScreen._goFriendsTabNotifier.addListener(_onGoFriendsTab);

    // Refresh Friends tab on foreground FCM message
    HomeScreen.friendsTabNotifier.addListener(_onFriendPicksReceived);

    // Check notification permission on startup (no-op if no friends)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) NotificationHelper.maybeRequest(context);
    });
  }

  @override
  void dispose() {
    HomeScreen._goFriendsTabNotifier.removeListener(_onGoFriendsTab);
    HomeScreen.friendsTabNotifier.removeListener(_onFriendPicksReceived);
    _tabController.dispose();
    super.dispose();
  }

  void _onGoFriendsTab() {
    _tabController.animateTo(1);
  }

  void _onFriendPicksReceived() {
    _friendsKey.currentState?.reload();
  }

  Future<void> _handleIncomingFriend(String username) async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _tabController.animateTo(1);
      await FirebaseService.followUser(username);
      _friendsKey.currentState?.reload();
      if (mounted) await NotificationHelper.maybeRequest(context);
    });
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
        title: ShaderMask(
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
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          MyPicksScreen(key: _myPicksKey),
          FriendsScreen(key: _friendsKey),
        ],
      ),
    );
  }
}
