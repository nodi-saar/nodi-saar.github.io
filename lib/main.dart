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
  await _storeFriendPicks(message);
}

Future<void> _storeFriendPicks(RemoteMessage message) async {
  if (message.data['type'] != 'friend_picks') return;
  final fromUsername = message.data['fromUsername'] as String?;
  final itemsJson    = message.data['items'] as String?;
  if (fromUsername == null || itemsJson == null) return;
  final items = (jsonDecode(itemsJson) as List)
      .map((m) => WatchItem.fromMap(Map<String, dynamic>.from(m),
            friendUsername: fromUsername))
      .toList();
  await AppStorage.appendFriendItems(fromUsername, items);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await FirebaseAuth.instance.signInAnonymously();
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
      if (username != null && mounted) {
        setState(() => _incomingFriend = username);
      }
    });

    final initial = await _appLinks.getInitialLink();
    if (initial != null) {
      final username = _extractUsername(initial);
      if (username != null) setState(() => _incomingFriend = username);
    }
  }

  Future<void> _initFcm() async {
    // Foreground: store picks silently, refresh Friends tab
    FirebaseMessaging.onMessage.listen((msg) async {
      await _storeFriendPicks(msg);
      HomeScreen.friendsTabNotifier.notifyListeners();
    });

    // Notification tap while app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      if (msg.data['type'] == 'friend_picks') {
        HomeScreen.goFriendsTab();
      }
    });

    // Notification tap from terminated state
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial?.data['type'] == 'friend_picks') {
      HomeScreen.goFriendsTab();
    }

    // Keep FCM token fresh
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      // ignore if no user doc yet — saveFcmToken is a no-op when docId is null
      // (token will be saved after permission dialog)
    });
  }

  String? _extractUsername(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments[segments.length - 2] == 'user') {
      return segments.last;
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
