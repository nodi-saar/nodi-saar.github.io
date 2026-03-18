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
  const rows = document.querySelectorAll('li.retableRow[data-uia="activity-row"]');
  rows.forEach(row => {
    if (row.dataset.nodisaarInjected) return;
    row.dataset.nodisaarInjected = "1";

    const reportCol = row.querySelector('.col.report');
    if (!reportCol) return;

    const titleAnchor = row.querySelector('.col.title a');
    if (!titleAnchor) return;

    const title = titleAnchor.textContent.trim();
    const href = titleAnchor.getAttribute('href');

    reportCol.innerHTML = '';
    const btn = document.createElement('button');
    btn.className = 'nodisaar-btn';

    btn.addEventListener('click', () => {
      chrome.storage.local.get(['netflix'], ({ netflix = [] }) => {
        const exists = netflix.some(i => i.href === href);
        if (!exists) {
          netflix.push({ title, href, source: 'netflix', addedAt: Date.now() });
          chrome.storage.local.set({ netflix, listDirty: true }, () => setAdded(btn));
        } else {
          const updated = netflix.filter(i => i.href !== href);
          chrome.storage.local.set({ netflix: updated, listDirty: true }, () => setNotAdded(btn));
        }
      });
    });

    // Initial state
    chrome.storage.local.get(['netflix'], ({ netflix = [] }) => {
      if (netflix.some(i => i.href === href)) {
        setAdded(btn);
      } else {
        setNotAdded(btn);
      }
    });

    reportCol.appendChild(btn);
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
    }
    .nodisaar-btn:hover { background: #1f1f27; border-color: #3a3a47; color: #f0f0f0; }
    .nodisaar-btn.added { background: #2ecc71; color: #fff; border-color: #2ecc71; }
  `;
  document.head.appendChild(style);
}

const observer = new MutationObserver(injectAddButtons);
observer.observe(document.body, { childList: true, subtree: true });
injectAddButtons();