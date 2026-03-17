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
    btn.textContent = 'Add to Watchlist';
    btn.className = 'nodisaar-btn';
    btn.style.cssText = `
      background: #e50914; color: #fff; border: none;
      padding: 4px 10px; border-radius: 4px; cursor: pointer;
      font-size: 13px; font-family: inherit;
    `;

    btn.addEventListener('click', () => {
      chrome.storage.local.get(['netflix'], ({ netflix = [] }) => {
        const exists = netflix.some(i => i.href === href);
        if (!exists) {
          netflix.push({ title, href, source: 'netflix' });
          chrome.storage.local.set({ netflix }, () => {
            btn.textContent = '✓ Added';
            btn.style.background = '#2ecc71';
            btn.disabled = true;
          });
        } else {
          btn.textContent = '✓ Already added';
          btn.disabled = true;
        }
      });
    });

    // Mark if already saved
    chrome.storage.local.get(['netflix'], ({ netflix = [] }) => {
      if (netflix.some(i => i.href === href)) {
        btn.textContent = '✓ Added';
        btn.style.background = '#2ecc71';
        btn.disabled = true;
      }
    });

    reportCol.appendChild(btn);
  });
}

// Netflix loads history dynamically
const observer = new MutationObserver(injectAddButtons);
observer.observe(document.body, { childList: true, subtree: true });
injectAddButtons();