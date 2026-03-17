const FIREBASE_BASE = "https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net";

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === "ping") {
    sendResponse({ ok: true });
    return true;
  }

  if (msg.type === "store_friend_uuid") {
    chrome.storage.local.set({ friendUuid: msg.uuid }, () => sendResponse({ ok: true }));
    return true;
  }

  if (msg.type === "get_friend_list") {
    const uuid = msg.uuid;
    fetch(`${FIREBASE_BASE}/getList?id=${uuid}`)
      .then(r => r.json())
      .then(data => sendResponse({ ok: true, data }))
      .catch(() => sendResponse({ ok: false }));
    return true;
  }

  if (msg.type === "save_list") {
    chrome.storage.local.get(["netflix", "prime"], ({ netflix = [], prime = [] }) => {
      const items = [...netflix, ...prime];
      fetch(`${FIREBASE_BASE}/saveList`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ items })
      })
        .then(r => r.json())
        .then(data => {
          chrome.storage.local.set({ sharedUrl: data.url, sharedUuid: data.uuid });
          sendResponse({ ok: true, url: data.url });
        })
        .catch(() => sendResponse({ ok: false }));
    });
    return true;
  }
});

// Handle external messages from nodi-saar.github.io
chrome.runtime.onMessageExternal.addListener((msg, sender, sendResponse) => {
  if (msg.type === "ping") {
    sendResponse({ ok: true });
    return true;
  }
  if (msg.type === "store_friend_uuid") {
    chrome.storage.local.set({ friendUuid: msg.uuid }, () => sendResponse({ ok: true }));
    return true;
  }
});