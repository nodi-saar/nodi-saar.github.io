import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'firebase.dart';
import 'storage.dart';

class NotificationHelper {
  /// Shows a permission dialog if the user follows at least one friend
  /// but hasn't granted notification permission yet.
  /// Safe to call any time — returns immediately if nothing to do.
  static Future<void> maybeRequest(BuildContext context) async {
    final friends = await AppStorage.getFriendUsernames();
    if (friends.isEmpty) return;

    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // Already authorized — ensure token is stored
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await FirebaseService.saveFcmToken(token);
      return;
    }

    if (!context.mounted) return;

    final granted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17171c),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Get real-time picks',
          style: TextStyle(
              color: Colors.white,
              fontFamily: 'Syne',
              fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Allow notifications to be alerted when ${friends.first}'
          '${friends.length > 1 ? ' and ${friends.length - 1} other friend${friends.length > 2 ? 's' : ''}' : ''}'
          ' add new favourites.',
          style: const TextStyle(color: Color(0xFF7a7a8c), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now',
                style: TextStyle(color: Color(0xFF7a7a8c))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow',
                style: TextStyle(
                    color: Color(0xFF00a8e1),
                    fontFamily: 'Syne',
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ) ?? false;

    if (!granted) return;

    await FirebaseMessaging.instance.requestPermission();
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await FirebaseService.saveFcmToken(token);
  }
}
