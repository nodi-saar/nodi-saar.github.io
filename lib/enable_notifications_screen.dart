import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase.dart';

class EnableNotificationsScreen extends StatefulWidget {
  /// Called when the user successfully grants permission.
  final VoidCallback onEnabled;

  const EnableNotificationsScreen({super.key, required this.onEnabled});

  @override
  State<EnableNotificationsScreen> createState() =>
      _EnableNotificationsScreenState();
}

class _EnableNotificationsScreenState
    extends State<EnableNotificationsScreen> {
  bool _requesting = false;
  bool _denied = false;

  Future<void> _onEnableTapped() async {
    setState(() { _requesting = true; _denied = false; });

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    if (granted) {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await FirebaseService.saveFcmToken(token);
      widget.onEnabled();
    } else {
      setState(() { _requesting = false; _denied = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0e0e11),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFe50914), Color(0xFF00a8e1)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.notifications_outlined,
                      color: Colors.white, size: 40),
                ),
                const SizedBox(height: 32),

                // Title
                const Text(
                  "Don't miss a thing",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Syne',
                    fontWeight: FontWeight.w800,
                    fontSize: 28,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16),

                // Body
                const Text(
                  "You're following friends on Nodisaar. "
                  "Notifications are the only way to know when they add new picks — "
                  "without them, you'll miss every update.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF7a7a8c),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 40),

                // Enable button
                SizedBox(
                  width: double.infinity,
                  child: _requesting
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF00a8e1)))
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFe50914), Color(0xFF00a8e1)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ElevatedButton(
                            onPressed: _onEnableTapped,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text(
                              'Enable Notifications',
                              style: TextStyle(
                                fontFamily: 'Syne',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                ),

                // Denied message
                if (_denied) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Notifications are blocked. Please go to your device '
                    'Settings → Nodisaar and enable notifications, '
                    'then come back and tap the button again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFe50914),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}