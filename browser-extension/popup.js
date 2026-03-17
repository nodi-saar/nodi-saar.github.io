const NETFLIX_URL  = "https://www.netflix.com/settings/viewed/";
const PRIME_URL    = "https://www.primevideo.com/region/in/settings/watch-history/ref=atv_set_watch-history";

// ── DOM refs ──────────────────────────────────────────────────────────────────
const addButtons     = document.getElementById("add-buttons");
const yourList       = document.getElementById("your-list");
const yourEmpty      = document.getElementById("your-empty");
const shareSection   = document.getElementById("share-section");
const totalCount     = document.getElementById("total-count");
const shareBtn       = document.getElementById("share-btn");
const shareHint      = document.getElementById("share-hint");
const shareBtnWrap   = document.getElementById("share-btn-wrap");
const sharedMsgWrap  = document.getElementById("shared-msg-wrap");
const sharedMsg      = document.getElementById("shared-msg");
const copyBtn        = document.getElementById("copy-btn");
const friendSection  = document.getElementById("friend-section");
const friendList     = document.getElementById("friend-list");
const unlockMsg      = document.getElementById("unlock-msg");
const divider        = document.getElementById("divider");
const loadingFriend  = document.getElementById("loading-friend");

document.getElementById("btn-netflix").addEventListener("click", () => {
  chrome.tabs.create({ url: NETFLIX_URL });
});
document.getElementById("btn-prime").addEventListener("click", () => {
  chrome.tabs.create({ url: PRIME_URL });
});

// ── Render your list ──────────────────────────────────────────────────────────
function renderYourList(netflix, prime) {
  const all = [...netflix, ...prime];
  const count = all.length;
  totalCount.textContent = count;

  if (count === 0) {
    addButtons.style.display = "block";
    yourList.style.display   = "none";
    yourEmpty.style.display  = "none";
    shareSection.style.display = "none";
    return;
  }

  addButtons.style.display = "none";
  shareSection.style.display = "block";

  yourList.style.display  = "block";
  yourEmpty.style.display = "none";
  yourList.innerHTML = "";

  all.forEach(item => {
    const li = document.createElement("li");
    li.className = "item";
    li.innerHTML = `
      <span class="dot ${item.source === 'netflix' ? 'dot-n' : 'dot-p'}"></span>
      <span class="item-title" title="${item.title}">${item.title}</span>
      <button class="item-remove" data-href="${item.href}" data-source="${item.source}" title="Remove">×</button>
    `;
    yourList.appendChild(li);
  });

  // Remove handlers
  yourList.querySelectorAll(".item-remove").forEach(btn => {
    btn.addEventListener("click", () => {
      const { href, source } = btn.dataset;
      chrome.storage.local.get([source], data => {
        const updated = (data[source] || []).filter(i => i.href !== href);
        chrome.storage.local.set({ [source]: updated }, init);
      });
    });
  });

  // Share button state
  shareBtn.disabled = count < 5;
  shareHint.style.display = count < 5 ? "block" : "none";
}

// ── Share ─────────────────────────────────────────────────────────────────────
shareBtn.addEventListener("click", () => {
  shareBtn.classList.add("loading");
  shareBtn.textContent = "Sharing…";
  chrome.runtime.sendMessage({ type: "save_list" }, resp => {
    shareBtn.classList.remove("loading");
    if (!resp.ok) {
      shareBtn.textContent = "Error — try again";
      shareBtn.disabled = false;
      return;
    }
    showSharedMessage(resp.url);
    chrome.storage.local.set({ sharedUrl: resp.url });
  });
});

function showSharedMessage(url) {
  shareBtnWrap.style.display  = "none";
  sharedMsgWrap.style.display = "block";
  const text = `I have created favourites from my watchlist on OTT to be shared with friends at ${url}. To create the list, I needed to install a browser extension from Nodisaar. Clicking on the link will show you the steps to install the extension & then you can see 3 of the items from the list. To view more, you need to create your own list & share it with me :)`;
  sharedMsg.textContent = text;
}

copyBtn.addEventListener("click", () => {
  navigator.clipboard.writeText(sharedMsg.textContent).then(() => {
    copyBtn.textContent = "✓ Copied!";
    setTimeout(() => copyBtn.textContent = "Copy message", 2000);
  });
});

// ── Friend list ───────────────────────────────────────────────────────────────
function renderFriendList(items, accessCount, hasOwnList) {
  friendSection.style.display = "block";
  divider.style.display       = "block";

  const showAll = hasOwnList && accessCount >= 1;
  const visible = showAll ? items : items.slice(0, 3);

  friendList.innerHTML = "";
  visible.forEach(item => {
    const li = document.createElement("li");
    li.className = "item";
    li.innerHTML = `
      <span class="dot ${item.source === 'netflix' ? 'dot-n' : 'dot-p'}"></span>
      <span class="item-title">${item.title}</span>
    `;
    friendList.appendChild(li);
  });

  if (!showAll) {
    unlockMsg.style.display = "block";
  }
}

// ── Init ──────────────────────────────────────────────────────────────────────
function init() {
  chrome.storage.local.get(["netflix", "prime", "sharedUrl", "friendUuid"], data => {
    const netflix = data.netflix || [];
    const prime   = data.prime   || [];
    const hasOwnList = (netflix.length + prime.length) > 0;

    // Restore shared state
    if (data.sharedUrl) {
      shareSection.style.display  = "block";
      shareBtnWrap.style.display  = "none";
      sharedMsgWrap.style.display = "block";
      totalCount.textContent = (netflix.length + prime.length).toString();
      sharedMsg.textContent = `I have created favourites from my watchlist on OTT to be shared with friends at ${data.sharedUrl}. To create the list, I needed to install a browser extension from Nodisaar. Clicking on the link will show you the steps to install the extension & then you can see 3 of the items from the list. To view more, you need to create your own list & share it with me :)`;
    }

    renderYourList(netflix, prime);

    // Load friend's list if uuid is pending
    if (data.friendUuid) {
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