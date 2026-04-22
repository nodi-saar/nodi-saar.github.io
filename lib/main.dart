import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_links/app_links.dart';
import 'home_screen.dart';
import 'storage.dart';
import 'models.dart';

// Top-level handler for background/terminated FCM messages
@pragma('vm:entry-point')
Future<void> _bgMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[Nodisaar] FCM background/terminated message received — type: ${message.data['type']}, from: ${message.data['fromUsername']}');
  await _storeFriendPicks(message);
}

Future<void> _storeFriendPicks(RemoteMessage message) async {
  if (message.data['type'] != 'friend_picks') return;
  final fromUsername = message.data['fromUsername'] as String?;
  final itemsJson    = message.data['items'] as String?;
  if (fromUsername == null || itemsJson == null) {
    debugPrint('[Nodisaar] FCM friend_picks message missing fromUsername or items');
    return;
  }
  final items = (jsonDecode(itemsJson) as List)
      .map((m) => WatchItem.fromMap(Map<String, dynamic>.from(m),
            friendUsername: fromUsername))
      .toList();
  await AppStorage.appendFriendItems(fromUsername, items);
  debugPrint('[Nodisaar] Stored ${items.length} FCM pick(s) from $fromUsername into local storage');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await FirebaseAuth.instance.signInAnonymously();
  debugPrint('[Nodisaar] Signed in anonymously — uid: ${FirebaseAuth.instance.currentUser?.uid}');
  FirebaseMessaging.onBackgroundMessage(_bgMessageHandler);
  runApp(const NodisaarApp());
}

class NodisaarApp extends StatefulWidget {
  const NodisaarApp({super.key});

  @override
  State<NodisaarApp> createState() => _NodisaarAppState();
}

class _NodisaarAppState extends State<NodisaarApp> {
  final _appLinks = AppLinks();
  String? _incomingFriend;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    _initFcm();
  }

  Future<void> _initDeepLinks() async {
    _appLinks.uriLinkStream.listen((uri) {
      final username = _extractUsername(uri);
      debugPrint('[Nodisaar] Deep link received (stream): $uri → username: $username');
      if (username != null && mounted) {
        setState(() => _incomingFriend = username);
      }
    });

    final initial = await _appLinks.getInitialLink();
    if (initial != null) {
      final username = _extractUsername(initial);
      debugPrint('[Nodisaar] Deep link received (initial): $initial → username: $username');
      if (username != null) setState(() => _incomingFriend = username);
    }
  }

  Future<void> _initFcm() async {
    // Foreground: store picks silently, refresh Friends tab
    FirebaseMessaging.onMessage.listen((msg) async {
      debugPrint('[Nodisaar] FCM foreground message — type: ${msg.data['type']}, from: ${msg.data['fromUsername']}');
      await _storeFriendPicks(msg);
      HomeScreen.friendsTabNotifier.notifyListeners();
    });

    // Notification tap while app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      debugPrint('[Nodisaar] FCM notification tapped (background) — type: ${msg.data['type']}');
      if (msg.data['type'] == 'friend_picks') {
        HomeScreen.goFriendsTab();
      }
    });

    // Notification tap from terminated state
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      debugPrint('[Nodisaar] FCM notification tapped (terminated) — type: ${initial.data['type']}');
      if (initial.data['type'] == 'friend_picks') {
        HomeScreen.goFriendsTab();
      }
    }

    // Keep FCM token fresh
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      debugPrint('[Nodisaar] FCM token refreshed: ${token.substring(0, 20)}…');
    });
  }

  String? _extractUsername(Uri uri) {
    final segments = uri.pathSegments;
    // Handles /user/<username> and /user/<username>/<docId>
    if (segments.length >= 2 && segments[0] == 'user') {
      return segments[1];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nodisaar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0e0e11),
        fontFamily: 'DM Sans',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00a8e1),
          secondary: Color(0xFFe50914),
        ),
      ),
      home: HomeScreen(
        key: ValueKey(_incomingFriend),
        incomingFriendUsername: _incomingFriend,
      ),
    );
  }
}