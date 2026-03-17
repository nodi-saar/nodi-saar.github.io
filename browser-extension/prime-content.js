function injectAddButtons() {
  const rows = document.querySelectorAll('li.avarm3[data-automation-id^="wh-item-"]');
  rows.forEach(row => {
    if (row.dataset.nodisaarInjected) return;
    row.dataset.nodisaarInjected = "1";

    const titleAnchor = row.querySelector('a._1NNx6V, a[href*="/detail/"]');
    const deleteForm = row.querySelector('form[data-automation-id^="wh-delete-"]');
    if (!titleAnchor || !deleteForm) return;

    const title = titleAnchor.textContent.trim();
    const href = titleAnchor.getAttribute('href');

    const btn = document.createElement('button');
    btn.textContent = 'Add to Watchlist';
    btn.type = 'button';
    btn.style.cssText = `
      background: #00a8e1; color: #fff; border: none;
      padding: 6px 12px; border-radius: 4px; cursor: pointer;
      font-size: 13px; font-family: inherit; margin-top: 6px;
    `;

    btn.addEventListener('click', () => {
      chrome.storage.local.get(['prime'], ({ prime = [] }) => {
        const exists = prime.some(i => i.href === href);
        if (!exists) {
          prime.push({ title, href, source: 'prime' });
          chrome.storage.local.set({ prime }, () => {
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

    chrome.storage.local.get(['prime'], ({ prime = [] }) => {
      if (prime.some(i => i.href === href)) {
        btn.textContent = '✓ Added';
        btn.style.background = '#2ecc71';
        btn.disabled = true;
      }
    });

    deleteForm.parentNode.insertBefore(btn, deleteForm);
  });
}

const observer = new MutationObserver(injectAddButtons);
observer.observe(document.body, { childList: true, subtree: true });
injectAddButtons();