const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {logger} = require("firebase-functions");
const admin = require("firebase-admin");
const {getMessaging} = require("firebase-admin/messaging");

admin.initializeApp();
const db = admin.firestore();
const bucket = admin.storage().bucket("nodi-saar.firebasestorage.app");

// ── Auth helper ───────────────────────────────────────────────────────────────
async function verifyToken(req, res) {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith("Bearer ")) {
    logger.warn("[Nodisaar] verifyToken: missing or malformed Authorization header");
    res.status(401).json({error: "Unauthorized"});
    return null;
  }
  try {
    const decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
    logger.info(`[Nodisaar] verifyToken: OK — uid: ${decoded.uid}`);
    return decoded;
  } catch (e) {
    logger.warn(`[Nodisaar] verifyToken: invalid token — ${e.message}`);
    res.status(401).json({error: "Invalid token"});
    return null;
  }
}

// ── CORS ───────────────────────────────────────────────────────────────────────
function setCorsHeaders(req, res) {
  const origin = req.headers.origin || "";
  if (origin.startsWith("chrome-extension://") || origin === "") {
    res.set("Access-Control-Allow-Origin", origin || "*");
  }
  res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");
}

// ── GET /checkUsername?username=x ─────────────────────────────────────────────
exports.checkUsername = onRequest({invoker: "public", region: "asia-south1"}, async (req, res) => {
  setCorsHeaders(req, res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "GET") return res.status(405).send("Method Not Allowed");

  const {username} = req.query;
  if (!username) return res.status(400).json({error: "username required"});

  logger.info(`[Nodisaar] checkUsername: checking "${username}"`);
  const snap = await db.collection("Users")
    .where("username", "==", username.trim().toLowerCase())
    .limit(1)
    .get();

  const available = snap.empty;
  logger.info(`[Nodisaar] checkUsername: "${username}" available: ${available}`);
  return res.status(200).json({available});
});

// ── POST /followUser ──────────────────────────────────────────────────────────
exports.followUser = onRequest({invoker: "public", region: "asia-south1"}, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

  const decoded = await verifyToken(req, res);
  if (!decoded) return;

  const {myDocId, targetUsername} = req.body;
  if (!myDocId || !targetUsername) {
    logger.warn("[Nodisaar] followUser: missing myDocId or targetUsername");
    return res.status(400).json({error: "myDocId and targetUsername required"});
  }

  logger.info(`[Nodisaar] followUser: uid ${decoded.uid} (docId: ${myDocId}) → "${targetUsername}"`);

  // Verify caller owns myDocId
  const myDoc = await db.collection("Users").doc(myDocId).get();
  if (!myDoc.exists || myDoc.data().uid !== decoded.uid) {
    logger.warn(`[Nodisaar] followUser: forbidden — doc uid mismatch`);
    return res.status(403).json({error: "Forbidden"});
  }

  // Find target user by username
  const targetSnap = await db.collection("Users")
    .where("username", "==", targetUsername.trim().toLowerCase())
    .limit(1)
    .get();
  if (targetSnap.empty) {
    logger.warn(`[Nodisaar] followUser: target user "${targetUsername}" not found`);
    return res.status(404).json({error: "User not found"});
  }

  const targetDocId = targetSnap.docs[0].id;
  logger.info(`[Nodisaar] followUser: target docId: ${targetDocId}`);

  // Write A's docId to B's following; write B's auth UID to A's followedBy
  await Promise.all([
    db.collection("Users").doc(myDocId).update({
      following: admin.firestore.FieldValue.arrayUnion(targetDocId),
    }),
    db.collection("Users").doc(targetDocId).update({
      followedBy: admin.firestore.FieldValue.arrayUnion(decoded.uid),
    }),
  ]);
  logger.info(`[Nodisaar] followUser: follow relationship written`);

  // Fetch target's current WatchItems for immediate local storage
  const itemsSnap = await db.collection("Users").doc(targetDocId)
    .collection("WatchItems")
    .orderBy("viewedAt", "desc")
    .get();

  const items = itemsSnap.docs.map((d) => ({id: d.id, ...d.data()}));
  logger.info(`[Nodisaar] followUser: returning ${items.length} existing item(s) to caller`);
  return res.status(200).json({items});
});

// ── POST /notifyFollowers ─────────────────────────────────────────────────────
exports.notifyFollowers = onRequest({invoker: "public", region: "asia-south1"}, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

  const decoded = await verifyToken(req, res);
  if (!decoded) return;

  const {userId, items} = req.body;
  if (!userId || !Array.isArray(items) || !items.length) {
    logger.warn("[Nodisaar] notifyFollowers: missing userId or items");
    return res.status(400).json({error: "userId and items required"});
  }

  logger.info(`[Nodisaar] notifyFollowers: userId=${userId}, ${items.length} item(s): ${items.map((i) => i.title).join(", ")}`);

  // Verify caller owns userId
  const userDoc = await db.collection("Users").doc(userId).get();
  if (!userDoc.exists || userDoc.data().uid !== decoded.uid) {
    logger.warn("[Nodisaar] notifyFollowers: forbidden — doc uid mismatch");
    return res.status(403).json({error: "Forbidden"});
  }

  const {followedBy = [], username = "Someone"} = userDoc.data();
  logger.info(`[Nodisaar] notifyFollowers: sender="${username}", ${followedBy.length} follower(s)`);
  if (!followedBy.length) return res.status(200).json({sent: 0});

  // followedBy stores Auth UIDs — query each to get their FCM token
  const tokenSnaps = await Promise.all(
    followedBy.map((uid) =>
      db.collection("Users").where("uid", "==", uid).limit(1).get()
    )
  );
  const tokens = tokenSnaps
    .map((snap) => snap.docs[0]?.data()?.fcmToken)
    .filter(Boolean);

  logger.info(`[Nodisaar] notifyFollowers: found ${tokens.length} FCM token(s) out of ${followedBy.length} follower(s)`);
  if (!tokens.length) return res.status(200).json({sent: 0});

  const first = items[0];
  const others = items.length - 1;
  const body = others > 0
    ? `${username} added ${first.title} & ${others} other${others > 1 ? "s" : ""} to their watchlist`
    : `${username} added ${first.title} to their watchlist`;

  logger.info(`[Nodisaar] notifyFollowers: sending FCM — "${body}"`);

  const messages = tokens.map((token) => ({
    token,
    notification: {title: "New picks from a friend", body},
    data: {
      type: "friend_picks",
      fromUsername: username,
      items: JSON.stringify(items.slice(0, 20)),
    },
    android: {notification: {channelId: "friend_picks"}},
    apns: {payload: {aps: {sound: "default"}}},
  }));

  const result = await getMessaging().sendEach(messages);
  logger.info(`[Nodisaar] notifyFollowers: sent ${result.successCount}/${tokens.length}, failed ${result.failureCount}`);
  if (result.failureCount > 0) {
    result.responses.forEach((r, i) => {
      if (!r.success) logger.warn(`[Nodisaar] notifyFollowers: token[${i}] failed — ${r.error?.message}`);
    });
  }
  return res.status(200).json({sent: result.successCount});
});

// ── Firestore trigger: Users/{docId}/WatchItems/{watchItemId} ──────────────────
exports.onWatchItemWritten = onDocumentWritten(
  {document: "Users/{docId}/WatchItems/{watchItemId}", region: "asia-south1"},
  async (event) => {
    const {docId, watchItemId} = event.params;
    const before = event.data?.before?.data();
    const after  = event.data?.after?.data();
    const globalRef = db.collection("WatchItems").doc(watchItemId);

    if (!before && after) {
      logger.info(`[Nodisaar] onWatchItemWritten: ADD "${after.title}" (${watchItemId}) by user ${docId}`);
      await globalRef.set({
        title:      after.title,
        href:       after.href,
        source:     after.source,
        watchCount: admin.firestore.FieldValue.increment(1),
        addedBy:    after.addedBy || "",
      }, {merge: true});
    } else if (before && !after) {
      logger.info(`[Nodisaar] onWatchItemWritten: DELETE "${before.title}" (${watchItemId}) by user ${docId}`);
      const snap = await globalRef.get();
      if (snap.exists) {
        const count = (snap.data().watchCount || 1) - 1;
        if (count <= 0) {
          await globalRef.delete();
          logger.info(`[Nodisaar] onWatchItemWritten: global entry removed (watchCount reached 0)`);
        } else {
          await globalRef.update({watchCount: admin.firestore.FieldValue.increment(-1)});
        }
      }
    } else {
      logger.info(`[Nodisaar] onWatchItemWritten: UPDATE "${after?.title}" (${watchItemId}) — no global count change`);
    }

    logger.info("[Nodisaar] onWatchItemWritten: regenerating toppicks.json");
    await generateTopPicksJSON();
    logger.info("[Nodisaar] onWatchItemWritten: toppicks.json updated");
  }
);

// ── GET /rebuildTopPicks ──────────────────────────────────────────────────────
exports.rebuildTopPicks = onRequest({invoker: "public", region: "asia-south1"}, async (req, res) => {
  if (req.method !== "GET") return res.status(405).send("Method Not Allowed");
  logger.info("[Nodisaar] rebuildTopPicks: manual rebuild triggered");
  await generateTopPicksJSON();
  logger.info("[Nodisaar] rebuildTopPicks: done");
  return res.status(200).json({ok: true});
});

// ── generateTopPicksJSON ───────────────────────────────────────────────────────
async function generateTopPicksJSON() {
  const snap = await db.collection("WatchItems")
    .orderBy("watchCount", "desc")
    .get();

  const topPicks = snap.docs.map((d) => ({id: d.id, ...d.data()}));
  logger.info(`[Nodisaar] generateTopPicksJSON: writing ${topPicks.length} item(s) to toppicks.json`);

  await bucket.file("toppicks.json").save(JSON.stringify(topPicks), {
    contentType: "application/json",
    public: true,
    metadata: {cacheControl: "public, max-age=300"},
  });
}