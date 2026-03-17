const functions = require("firebase-functions");
const admin     = require("firebase-admin");
const { v4: uuidv4 } = require("uuid");

admin.initializeApp();
const db = admin.firestore();

// ── POST /saveList ─────────────────────────────────────────────────────────────
// Body: { items: [{ title, href, source }] }
// Returns: { uuid, url }
exports.saveList = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "chrome-extension://*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

  const { items } = req.body;
  if (!Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: "items array required" });
  }

  const uuid = uuidv4();
  await db.collection("lists").doc(uuid).set({
    items,
    createdAt:   admin.firestore.FieldValue.serverTimestamp(),
    accessCount: 0
  });

  const url = `https://nodi-saar.github.io/?id=${uuid}`;
  return res.status(200).json({ uuid, url });
});

// ── GET /getList?id=uuid ──────────────────────────────────────────────────────
// Returns: { items, accessCount }
// Also increments accessCount on each call (each call = a friend viewed it)
exports.getList = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "chrome-extension://*");
  res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "GET") return res.status(405).send("Method Not Allowed");

  const { id } = req.query;
  if (!id) return res.status(400).json({ error: "id query param required" });

  const ref = db.collection("lists").doc(id);
  const snap = await ref.get();

  if (!snap.exists) return res.status(404).json({ error: "List not found" });

  const data = snap.data();

  // Increment access count
  await ref.update({ accessCount: admin.firestore.FieldValue.increment(1) });

  return res.status(200).json({
    items:       data.items,
    accessCount: data.accessCount  // value before this visit
  });
});