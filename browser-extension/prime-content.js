function setNotAdded(btn) {
  btn.innerHTML = '<span style="font-size:14px;line-height:1">+</span> Add';
  btn.classList.remove('added');
  btn.dataset.added = "0";
}

function setAdded(btn) {
  btn.innerHTML = '✓ Added';
  btn.classList.add('added');
  btn.disabled = false;
  btn.dataset.added = "1";
}

function injectAddButtons() {
  const rows = document.querySelectorAll('li.avarm3[data-automation-id^="wh-item-"]');
  rows.forEach(row => {
    if (row.dataset.nodisaarInjected) return;

    const titleAnchor = row.querySelector('a._1NNx6V');
    const deleteForm  = row.querySelector('form[data-automation-id^="wh-delete-"]');
    if (!titleAnchor || !deleteForm) return;

    const href = titleAnchor.getAttribute('href');

    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'nodisaar-btn';

    btn.addEventListener('click', () => {
      // Read title fresh from DOM at click time — guaranteed rendered by then
      const title = titleAnchor.textContent.trim();
      chrome.storage.local.get(['prime'], ({ prime = [] }) => {
        const exists = prime.some(i => i.href === href);
        if (!exists) {
          prime.push({ title, href, source: 'prime', addedAt: Date.now() });
          chrome.storage.local.set({ prime, listDirty: true }, () => setAdded(btn));
        } else {
          const updated = prime.filter(i => i.href !== href);
          chrome.storage.local.set({ prime: updated, listDirty: true }, () => setNotAdded(btn));
        }
      });
    });

    // Initial state
    chrome.storage.local.get(['prime'], ({ prime = [] }) => {
      if (prime.some(i => i.href === href)) {
        setAdded(btn);
      } else {
        setNotAdded(btn);
      }
    });

    deleteForm.parentNode.replaceChild(btn, deleteForm);
    // Stamp only after successful injection
    row.dataset.nodisaarInjected = "1";
  });
}

// Inject Nodisaar button styles once
if (!document.getElementById('nodisaar-styles')) {
  const style = document.createElement('style');
  style.id = 'nodisaar-styles';
  style.textContent = `
    .nodisaar-btn {
      display: inline-flex; align-items: center; gap: 8px;
      padding: 8px 18px;
      border-radius: 8px;
      background: linear-gradient(135deg, #e50914, #00a8e1);
      color: #fff;
      font-family: 'Syne', sans-serif;
      font-weight: 700;
      font-size: 13px;
      text-decoration: none;
      letter-spacing: 0.3px;
      border: none;
      cursor: pointer;
      transition: opacity 0.15s, transform 0.15s;
      margin: auto 50px auto !important;
      width: 120px;
    }
    .nodisaar-btn:hover { background: #1f1f27; border-color: #3a3a47; color: #f0f0f0; }
    .nodisaar-btn.added { background: #2ecc71; color: #fff; border-color: #2ecc71; }
  `;
  document.head.appendChild(style);
}

const observer = new MutationObserver(injectAddButtons);
observer.observe(document.body, { childList: true, subtree: true });
injectAddButtons();