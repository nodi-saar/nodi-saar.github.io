import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models.dart';
import 'storage.dart';
import 'package:http/http.dart' as http;


class FirebaseService {
  static const _base = 'https://asia-south1-nodi-saar.cloudfunctions.net';
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  // ── Anonymous auth ─────────────────────────────────────────────────────────
  static Future<String> ensureAuth() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
    return _auth.currentUser!.uid;
  }

  // ── Ensure user doc exists, returns docId ──────────────────────────────────
  static Future<String> ensureUserDoc() async {
    await ensureAuth();
    String? docId = await AppStorage.getDocId();
    if (docId == null) {
      final ref = _db.collection('Users').doc();
      await ref.set({
        'username': await AppStorage.getUsername() ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'followedBy': [],
      });
      docId = ref.id;
      await AppStorage.setDocId(docId);
    }
    return docId;
  }

  // ── Username check (HTTP — safe public query) ──────────────────────────────
  static Future<bool> checkUsername(String username) async {
    final uri = Uri.parse(
        '$_base/checkUsername?username=${Uri.encodeComponent(username)}');
    final resp = await http.get(uri);
    if (resp.statusCode != 200) return false;
    return jsonDecode(resp.body)['available'] == true;
  }

  // ── Follow a friend: register followedBy, fetch + store their items ────────
  static Future<List<WatchItem>> followUser(String targetUsername) async {
    final myDocId = await ensureUserDoc();

    final snap = await _db.collection('Users')
        .where('username', isEqualTo: targetUsername)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return [];

    final targetDocId = snap.docs.first.id;

    // Register B's docId in A's followedBy (arrayUnion prevents duplicates)
    await _db.collection('Users').doc(targetDocId).update({
      'followedBy': FieldValue.arrayUnion([myDocId]),
    });

    // Fetch A's current items
    final itemsSnap = await _db
        .collection('Users')
        .doc(targetDocId)
        .collection('WatchItems')
        .orderBy('viewedAt', descending: true)
        .get();

    final items = itemsSnap.docs
        .map((d) => WatchItem.fromMap(
              Map<String, dynamic>.from(d.data()),
              friendUsername: targetUsername,
            ))
        .toList();

    await AppStorage.addFriendUsername(targetUsername);
    await AppStorage.setFriendItems(targetUsername, items);
    return items;
  }

  // ── Save FCM token to Firestore ────────────────────────────────────────────
  static Future<void> saveFcmToken(String token) async {
    final docId = await AppStorage.getDocId();
    if (docId == null) return;
    await _db.collection('Users').doc(docId).update({'fcmToken': token});
  }

  // ── Notify followers via Cloud Function (fire-and-forget) ─────────────────
  static Future<void> notifyFollowers(List<WatchItem> newItems) async {
    final docId = await AppStorage.getDocId();
    if (docId == null || newItems.isEmpty) return;
    try {
      await http.post(
        Uri.parse('$_base/notifyFollowers'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': docId,
          'items': newItems.map((i) => i.toFirestore()).toList(),
        }),
      );
    } catch (_) {}
  }

  // ── Save own list to Firestore — returns newly added items ─────────────────
  static Future<List<WatchItem>> syncItems(List<WatchItem> localItems) async {
    final docId = await ensureUserDoc();
    final username = await AppStorage.getUsername();

    if (username != null) {
      await _db.collection('Users').doc(docId).set(
        {'username': username},
        SetOptions(merge: true),
      );
    }

    final colRef = _db.collection('Users').doc(docId).collection('WatchItems');

    final snap = await colRef.get();
    final remoteIds = snap.docs.map((d) => d.id).toSet();
    final localIds  = localItems.map((i) => i.id).toSet();

    final toAdd    = localItems.where((i) => !remoteIds.contains(i.id)).toList();
    final toDelete = remoteIds.difference(localIds);

    if (toAdd.isEmpty && toDelete.isEmpty) return [];

    const chunkSize = 400;
    final allOps = <Future>[];

    for (var i = 0; i < toAdd.length; i += chunkSize) {
      final chunk = toAdd.sublist(i, (i + chunkSize).clamp(0, toAdd.length));
      final batch = _db.batch();
      for (final item in chunk) {
        batch.set(colRef.doc(item.id), {
          ...item.toFirestore(),
          'addedBy': username ?? '',
        });
      }
      allOps.add(batch.commit());
    }

    if (toDelete.isNotEmpty) {
      final batch = _db.batch();
      for (final id in toDelete) {
        batch.delete(colRef.doc(id));
      }
      allOps.add(batch.commit());
    }

    await Future.wait(allOps);
    return toAdd;
  }

  // ── Check delta: local vs remote ───────────────────────────────────────────
  static Future<bool> hasPendingChanges(List<WatchItem> localItems) async {
    final docId = await AppStorage.getDocId();
    if (docId == null) return localItems.isNotEmpty;

    final snap = await _db
        .collection('Users')
        .doc(docId)
        .collection('WatchItems')
        .get();

    final remoteIds = snap.docs.map((d) => d.id).toSet();
    final localIds  = localItems.map((i) => i.id).toSet();

    return localIds.difference(remoteIds).isNotEmpty ||
           remoteIds.difference(localIds).isNotEmpty;
  }
}
