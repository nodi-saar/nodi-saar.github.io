const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();
const bucket = admin.storage().bucket("nodi-saar.firebasestorage.app");

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

  const snap = await db.collection("Users")
    .where("username", "==", username.trim().toLowerCase())
    .limit(1)
    .get();

  return res.status(200).json({available: snap.empty});
});

// ── Firestore trigger: Users/{docId}/WatchItems/{watchItemId} ──────────────────
exports.onWatchItemWritten = onDocumentWritten(
  {document: "Users/{docId}/WatchItems/{watchItemId}", region: "asia-south1"},
  async (event) => {
    const watchItemId = event.params.watchItemId;
    const before = event.data?.before?.data();
    const after  = event.data?.after?.data();
    const globalRef = db.collection("WatchItems").doc(watchItemId);

    if (!before && after) {
      await globalRef.set({
        title:      after.title,
        href:       after.href,
        source:     after.source,
        watchCount: admin.firestore.FieldValue.increment(1),
        addedBy:    after.addedBy || "",
      }, {merge: true});
    } else if (before && !after) {
      const snap = await globalRef.get();
      if (snap.exists) {
        const count = (snap.data().watchCount || 1) - 1;
        if (count <= 0) {
          await globalRef.delete();
        } else {
          await globalRef.update({watchCount: admin.firestore.FieldValue.increment(-1)});
        }
      }
    }

    await generateTopPicksJSON();
  }
);

// ── GET /rebuildTopPicks ──────────────────────────────────────────────────────
exports.rebuildTopPicks = onRequest({invoker: "public", region: "asia-south1"}, async (req, res) => {
  if (req.method !== "GET") return res.status(405).send("Method Not Allowed");
  await generateTopPicksJSON();
  return res.status(200).json({ok: true});
});

// ── generateTopPicksJSON ───────────────────────────────────────────────────────
async function generateTopPicksJSON() {
  const snap = await db.collection("WatchItems")
    .orderBy("watchCount", "desc")
    .get();

  const topPicks = snap.docs.map(d => ({id: d.id, ...d.data()}));

  await bucket.file("toppicks.json").save(JSON.stringify(topPicks), {
    contentType: "application/json",
    public: true,
    metadata: {cacheControl: "public, max-age=300"},
  });
}