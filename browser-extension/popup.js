const NETFLIX_URL = "https://www.netflix.com/settings/viewed/";
const PRIME_URL   = "https://www.primevideo.com/region/in/settings/watch-history/ref=atv_set_watch-history";

// ── DOM refs ──────────────────────────────────────────────────────────────────
const shareSection      = document.getElementById("share-section");
const totalCount        = document.getElementById("total-count");
const savedActions      = document.getElementById("saved-actions");
const saveBtn           = document.getElementById("save-btn");
const shareBtnSaved     = document.getElementById("share-btn");
const firstShareWrap    = document.getElementById("first-share-wrap");
const firstShareBtn     = document.getElementById("first-share-btn");
const shareHint         = document.getElementById("share-hint");
const sharedMsgWrap     = document.getElementById("shared-msg-wrap");
const sharedMsg         = document.getElementById("shared-msg");
const copyBtn           = document.getElementById("copy-btn");
const friendSection     = document.getElementById("friend-section");
const unlockMsg         = document.getElementById("unlock-msg");
const divider           = document.getElementById("divider");
const loadingFriend     = document.getElementById("loading-friend");

const yourNetflixList    = document.getElementById("your-netflix-list");
const yourNetflixEmpty   = document.getElementById("your-netflix-empty");
const yourPrimeList      = document.getElementById("your-prime-list");
const yourPrimeEmpty     = document.getElementById("your-prime-empty");

const friendNetflixList  = document.getElementById("friend-netflix-list");
const friendNetflixEmpty = document.getElementById("friend-netflix-empty");
const friendPrimeList    = document.getElementById("friend-prime-list");
const friendPrimeEmpty   = document.getElementById("friend-prime-empty");

document.getElementById("btn-netflix").addEventListener("click", () => {
  chrome.tabs.create({ url: NETFLIX_URL });
});
document.getElementById("btn-prime").addEventListener("click", () => {
  chrome.tabs.create({ url: PRIME_URL });
});

// ── Render a source section in Your Picks ────────────────────────────────────
function renderYourSection(items, listEl, emptyEl, source) {
  if (items.length === 0) {
    listEl.innerHTML = "";
    emptyEl.style.display = "block";
    return;
  }
  emptyEl.style.display = "none";
  listEl.innerHTML = "";
  items.forEach(item => {
    const li = document.createElement("li");
    li.className = "item";
    li.innerHTML = `
      <span class="item-title" title="${item.title}">${item.title}</span>
      <button class="item-remove" data-href="${item.href}" data-source="${source}" title="Remove">×</button>
    `;
    listEl.appendChild(li);
  });
  listEl.querySelectorAll(".item-remove").forEach(btn => {
    btn.addEventListener("click", () => {
      const { href, source: src } = btn.dataset;
      chrome.storage.local.get([src], data => {
        const updated = (data[src] || []).filter(i => i.href !== href);
        chrome.storage.local.set({ [src]: updated }, init);
      });
    });
  });
}

// ── Render your list ──────────────────────────────────────────────────────────
function renderYourList(netflix, prime, sharedUrl) {
  const count = netflix.length + prime.length;
  totalCount.textContent = count;

  renderYourSection(netflix, yourNetflixList, yourNetflixEmpty, "netflix");
  renderYourSection(prime, yourPrimeList, yourPrimeEmpty, "prime");

  if (count === 0) {
    shareSection.style.display = "none";
    return;
  }

  shareSection.style.display = "block";

  if (sharedUrl) {
    // Already shared — show Save Updated + Share with Friends
    savedActions.style.display   = "block";
    firstShareWrap.style.display = "none";
    sharedMsgWrap.style.display  = "none";
  } else {
    // Never shared — show first-time share button
    savedActions.style.display   = "none";
    firstShareWrap.style.display = "block";
    firstShareBtn.disabled = count < 5;
    shareHint.style.display = count < 5 ? "block" : "none";
  }
}

// ── Save updated list ─────────────────────────────────────────────────────────
saveBtn.addEventListener("click", () => {
  saveBtn.classList.add("loading");
  saveBtn.textContent = "Saving…";
  chrome.runtime.sendMessage({ type: "save_list" }, resp => {
    saveBtn.classList.remove("loading");
    saveBtn.textContent = resp.ok ? "✓ List Saved" : "Error — try again";
    setTimeout(() => { saveBtn.textContent = "Save Updated List"; }, 2000);
  });
});

// ── Share with friends (already shared — reveal message) ─────────────────────
shareBtnSaved.addEventListener("click", () => {
  chrome.storage.local.get(["sharedUrl"], ({ sharedUrl }) => {
    if (sharedUrl) showSharedMessage(sharedUrl);
  });
});

// ── First-time share ──────────────────────────────────────────────────────────
firstShareBtn.addEventListener("click", () => {
  firstShareBtn.classList.add("loading");
  firstShareBtn.textContent = "Sharing…";
  chrome.runtime.sendMessage({ type: "save_list" }, resp => {
    firstShareBtn.classList.remove("loading");
    if (!resp.ok) {
      firstShareBtn.textContent = "Error — try again";
      firstShareBtn.disabled = false;
      return;
    }
    chrome.storage.local.set({ sharedUrl: resp.url });
    firstShareWrap.style.display = "none";
    savedActions.style.display   = "block";
    showSharedMessage(resp.url);
  });
});

// ── Show share message ────────────────────────────────────────────────────────
function showSharedMessage(url) {
  sharedMsgWrap.style.display = "block";
  const text = `I have created favourites from my watchlist on OTT to be shared with friends at ${url}. To create the list, I needed to install a browser extension from Nodisaar. Clicking on the link will show you the steps to install the extension & then you can see 3 of the items from the list. To view more, you need to create your own list & share it with me :)`;
  sharedMsg.textContent = text;
}

// ── Copy & open WhatsApp ──────────────────────────────────────────────────────
copyBtn.addEventListener("click", () => {
  navigator.clipboard.writeText(sharedMsg.textContent).then(() => {
    copyBtn.textContent = "✓ Copied!";
    setTimeout(() => {
      copyBtn.textContent = "📋 Copy Message & Share on Whatsapp";
      window.open("https://wa.me/?text=" + encodeURIComponent(sharedMsg.textContent), "_blank");
    }, 600);
  });
});

// ── Render a source section in Friend's Picks ─────────────────────────────────
function renderFriendSection(items, listEl, emptyEl) {
  const sorted = [...items].sort((a, b) => (b.addedAt || 0) - (a.addedAt || 0));
  if (sorted.length === 0) {
    listEl.innerHTML = "";
    emptyEl.style.display = "block";
    return;
  }
  emptyEl.style.display = "none";
  listEl.innerHTML = "";
  sorted.forEach(item => {
    const li = document.createElement("li");
    li.className = "item";
    li.innerHTML = `<span class="item-title">${item.title}</span>`;
    listEl.appendChild(li);
  });
}

// ── Render friend list ────────────────────────────────────────────────────────
function renderFriendList(items, accessCount, hasOwnList) {
  friendSection.style.display = "block";
  divider.style.display       = "block";

  const showAll = hasOwnList && accessCount >= 1;
  const visible = showAll ? items : items.slice(0, 3);

  const netflix = visible.filter(i => i.source === "netflix");
  const prime   = visible.filter(i => i.source === "prime");

  renderFriendSection(netflix, friendNetflixList, friendNetflixEmpty);
  renderFriendSection(prime, friendPrimeList, friendPrimeEmpty);

  unlockMsg.style.display = showAll ? "none" : "block";
}

// ── Init ──────────────────────────────────────────────────────────────────────
function init() {
  chrome.storage.local.get(["netflix", "prime", "sharedUrl", "sharedUuid", "friendUuid"], data => {
    const netflix    = data.netflix || [];
    const prime      = data.prime   || [];
    const hasOwnList = (netflix.length + prime.length) > 0;

    renderYourList(netflix, prime, data.sharedUrl);

    if (data.friendUuid) {
      if (data.friendUuid === data.sharedUuid) return;
      loadingFriend.style.display = "block";
      chrome.runtime.sendMessage({ type: "get_friend_list", uuid: data.friendUuid }, resp => {
        loadingFriend.style.display = "none";
        if (resp.ok && resp.data && resp.data.items) {
          renderFriendList(resp.data.items, resp.data.accessCount, hasOwnList);
        }
      });
    }
  });
}

init();