import 'dart:convert';
import 'package:flutter/material.dart';
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
      debugPrint('[Nodisaar] Signed in anonymously — uid: ${_auth.currentUser?.uid}');
    }
    return _auth.currentUser!.uid;
  }

  // ── Ensure user doc exists, returns docId ──────────────────────────────────
  static Future<String> ensureUserDoc() async {
    await ensureAuth();
    String? docId = await AppStorage.getDocId();
    if (docId == null) {
      final uid = _auth.currentUser!.uid;
      final ref = _db.collection('Users').doc();
      await ref.set({
        'uid': uid,
        'username': await AppStorage.getUsername() ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'followedBy': [],
        'following': [],
      });
      docId = ref.id;
      await AppStorage.setDocId(docId);
      debugPrint('[Nodisaar] User doc created — docId: $docId, uid: $uid');
    } else {
      debugPrint('[Nodisaar] User doc exists — docId: $docId');
    }
    return docId;
  }

  // ── Username check (HTTP — safe public query) ──────────────────────────────
  static Future<bool> checkUsername(String username) async {
    debugPrint('[Nodisaar] Checking username availability: $username');
    final uri = Uri.parse(
        '$_base/checkUsername?username=${Uri.encodeComponent(username)}');
    final resp = await http.get(uri);
    if (resp.statusCode != 200) return false;
    final available = jsonDecode(resp.body)['available'] == true;
    debugPrint('[Nodisaar] Username "$username" available: $available');
    return available;
  }

  // ── Follow a friend via Cloud Function ────────────────────────────────────
  static Future<List<WatchItem>> followUser(String targetUsername) async {
    debugPrint('[Nodisaar] Following user: $targetUsername');
    final myDocId = await ensureUserDoc();
    final token = await _auth.currentUser!.getIdToken();

    final resp = await http.post(
      Uri.parse('$_base/followUser'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'myDocId': myDocId, 'targetUsername': targetUsername}),
    );

    debugPrint('[Nodisaar] followUser response: ${resp.statusCode}');
    if (resp.statusCode != 200) return [];

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final rawItems = (data['items'] as List? ?? []);
    final items = rawItems
        .map((e) => WatchItem.fromMap(
              Map<String, dynamic>.from(e as Map),
              friendUsername: targetUsername,
            ))
        .toList();

    await AppStorage.addFriendUsername(targetUsername);
    await AppStorage.setFriendItems(targetUsername, items);
    debugPrint('[Nodisaar] Now following $targetUsername — ${items.length} existing item(s) stored');
    return items;
  }

  // ── Save username to Firestore user doc ───────────────────────────────────
  static Future<void> saveUsername(String username) async {
    debugPrint('[Nodisaar] Saving username to Firestore: $username');
    final docId = await ensureUserDoc();
    await _db.collection('Users').doc(docId).set(
      {'username': username},
      SetOptions(merge: true),
    );
    debugPrint('[Nodisaar] Username saved — docId: $docId, username: $username');
  }

  // ── Save FCM token to Firestore ────────────────────────────────────────────
  static Future<void> saveFcmToken(String token) async {
    final docId = await AppStorage.getDocId();
    if (docId == null) {
      debugPrint('[Nodisaar] saveFcmToken: no docId yet, skipping');
      return;
    }
    await _db.collection('Users').doc(docId).update({'fcmToken': token});
    debugPrint('[Nodisaar] FCM token saved to Firestore — ${token.substring(0, 20)}…');
  }

  // ── Notify followers via Cloud Function (fire-and-forget) ─────────────────
  static Future<void> notifyFollowers(List<WatchItem> newItems) async {
    final docId = await AppStorage.getDocId();
    if (docId == null || newItems.isEmpty) return;
    debugPrint('[Nodisaar] Calling notifyFollowers with ${newItems.length} new item(s): ${newItems.map((i) => i.title).join(', ')}');
    try {
      final token = await _auth.currentUser!.getIdToken();
      final resp = await http.post(
        Uri.parse('$_base/notifyFollowers'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userId': docId,
          'items': newItems.map((i) => i.toFirestore()).toList(),
        }),
      );
      debugPrint('[Nodisaar] notifyFollowers response: ${resp.statusCode} — body: ${resp.body}');
    } catch (e) {
      debugPrint('[Nodisaar] notifyFollowers failed: $e');
    }
  }

  // ── Save own list to Firestore — returns newly added items ─────────────────
  static Future<List<WatchItem>> syncItems(List<WatchItem> localItems) async {
    debugPrint('[Nodisaar] syncItems — ${localItems.length} local item(s)');
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

    debugPrint('[Nodisaar] syncItems — ${toAdd.length} to add, ${toDelete.length} to delete');

    if (toAdd.isEmpty && toDelete.isEmpty) {
      debugPrint('[Nodisaar] syncItems — nothing to sync');
      return [];
    }

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
    debugPrint('[Nodisaar] syncItems — wrote ${toAdd.length} new item(s) to Firestore: ${toAdd.map((i) => i.title).join(', ')}');
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