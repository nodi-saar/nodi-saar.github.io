import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'storage.dart';
import 'models.dart';

class WebViewScreen extends StatefulWidget {
  final String platform; // 'netflix' | 'prime'
  const WebViewScreen({super.key, required this.platform});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _ctrl;
  bool _loading = true;
  bool _changed = false;

  String get _url => widget.platform == 'netflix'
      ? 'https://www.netflix.com/settings/viewed/'
      : 'https://www.primevideo.com/region/in/settings/watch-history/ref=atv_set_watch-history';

  Future<void> _inject() async {
    final items = await AppStorage.getItems();
    final addedHrefs = items
        .where((i) => i.source == widget.platform)
        .map((i) => i.href)
        .toList();
    final addedJson = addedHrefs
        .map((h) => '"${h.replaceAll('"', '\\"')}"')
        .join(',');

    final js = widget.platform == 'netflix'
        ? _buildNetflixJS(addedJson)
        : _buildPrimeJS(addedJson);

    await _ctrl?.evaluateJavascript(source: js);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0e0e11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0e0e11),
        foregroundColor: Colors.white,
        title: Text(
          widget.platform == 'netflix' ? 'Netflix History' : 'Prime History',
          style: const TextStyle(fontFamily: 'Syne', fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _changed),
            child: const Text('Done',
                style: TextStyle(
                    color: Color(0xFF00a8e1),
                    fontFamily: 'Syne',
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_url)),
            initialSettings: InAppWebViewSettings(
              domStorageEnabled: true,
              databaseEnabled: true,
              javaScriptEnabled: true,
              userAgent:
                  'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 '
                  'Chrome/120 Mobile Safari/537.36',
            ),
            onWebViewCreated: (ctrl) {
              _ctrl = ctrl;

              // Add item handler
              ctrl.addJavaScriptHandler(
                handlerName: 'nodisaarAdd',
                callback: (args) async {
                  if (args.isEmpty) return;
                  final d = Map<String, dynamic>.from(args[0] as Map);
                  final item = WatchItem(
                    title: d['title'] as String,
                    href: d['href'] as String,
                    source: widget.platform,
                    viewedAt: _parseDate(d['viewedAt'] as String? ?? ''),
                    addedAt: DateTime.now(),
                  );
                  await AppStorage.addItem(item);
                  _changed = true;
                },
              );

              // Remove item handler
              ctrl.addJavaScriptHandler(
                handlerName: 'nodisaarRemove',
                callback: (args) async {
                  if (args.isEmpty) return;
                  final href = args[0] as String;
                  await AppStorage.removeItem(href);
                  _changed = true;
                },
              );
            },
            onLoadStop: (ctrl, url) async {
              setState(() => _loading = false);
              await _inject();
            },
            onScrollChanged: (ctrl, x, y) async {
              await _inject();
            },
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00a8e1)),
            ),
        ],
      ),
    );
  }

  // ── Date parsing ────────────────────────────────────────────────────────────
  // Netflix: "24/3/26" → DD/M/YY
  // Prime:   "March 23, 2026" → passed from JS date group header
  DateTime _parseDate(String raw) {
    try {
      if (raw.contains('/')) {
        // Netflix format: DD/M/YY
        final parts = raw.split('/');
        if (parts.length == 3) {
          final day   = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final year  = 2000 + int.parse(parts[2]);
          return DateTime(year, month, day);
        }
      } else if (raw.isNotEmpty) {
        // Prime format: "March 23, 2026"
        return _parsePrimeDate(raw);
      }
    } catch (_) {}
    return DateTime.now();
  }

  DateTime _parsePrimeDate(String s) {
    const months = {
      'january': 1, 'february': 2, 'march': 3, 'april': 4,
      'may': 5, 'june': 6, 'july': 7, 'august': 8,
      'september': 9, 'october': 10, 'november': 11, 'december': 12,
    };
    // "March 23, 2026"
    final parts = s.replaceAll(',', '').split(' ');
    if (parts.length == 3) {
      final month = months[parts[0].toLowerCase()] ?? 1;
      final day   = int.tryParse(parts[1]) ?? 1;
      final year  = int.tryParse(parts[2]) ?? DateTime.now().year;
      return DateTime(year, month, day);
    }
    return DateTime.now();
  }
}

// ── Netflix injection JS ───────────────────────────────────────────────────────
String _buildNetflixJS(String addedHrefsJson) => '''
(function() {
  const addedHrefs = new Set([$addedHrefsJson]);

  if (!document.getElementById('nd-styles')) {
    const s = document.createElement('style');
    s.id = 'nd-styles';
    s.textContent = `
      .nd-btn {
        display:inline-flex;align-items:center;gap:5px;
        padding:5px 12px;border-radius:7px;
        background:linear-gradient(135deg,#e50914,#00a8e1);
        color:#fff;font-weight:700;font-size:12px;
        border:none;cursor:pointer;white-space:nowrap;
      }
      .nd-btn.added { background:#2ecc71; }
    `;
    document.head.appendChild(s);
  }

  function injectButtons() {
    const rows = document.querySelectorAll('li.retableRow[data-uia="activity-row"]');
    rows.forEach(row => {
      if (row.dataset.ndInjected) return;
      const titleAnchor = row.querySelector('.col.title a');
      const reportCol   = row.querySelector('.col.report');
      const dateEl      = row.querySelector('.col.date');
      if (!titleAnchor || !reportCol) return;

      const title    = titleAnchor.textContent.trim();
      const href     = titleAnchor.getAttribute('href');
      const viewedAt = dateEl ? dateEl.textContent.trim() : '';

      row.dataset.ndInjected = '1';
      reportCol.innerHTML = '';

      const btn = document.createElement('button');
      btn.className = 'nd-btn' + (addedHrefs.has(href) ? ' added' : '');
      btn.textContent = addedHrefs.has(href) ? '✓ Added' : '+ Add';

      btn.addEventListener('click', () => {
        const isAdded = btn.classList.contains('added');
        if (isAdded) {
          window.flutter_inappwebview.callHandler('nodisaarRemove', href);
          addedHrefs.delete(href);
          btn.classList.remove('added');
          btn.textContent = '+ Add';
        } else {
          window.flutter_inappwebview.callHandler('nodisaarAdd', {title, href, viewedAt});
          addedHrefs.add(href);
          btn.classList.add('added');
          btn.textContent = '✓ Added';
        }
      });

      reportCol.appendChild(btn);
    });
  }

  injectButtons();
  new MutationObserver(injectButtons).observe(document.body, {childList:true, subtree:true});
})();
''';

// ── Prime injection JS ─────────────────────────────────────────────────────────
String _buildPrimeJS(String addedHrefsJson) => '''
(function() {
  const addedHrefs = new Set([$addedHrefsJson]);

  if (!document.getElementById('nd-styles')) {
    const s = document.createElement('style');
    s.id = 'nd-styles';
    s.textContent = `
      .nd-btn {
        display:inline-flex;align-items:center;gap:5px;
        padding:5px 12px;border-radius:7px;
        background:linear-gradient(135deg,#e50914,#00a8e1);
        color:#fff;font-weight:700;font-size:12px;
        border:none;cursor:pointer;white-space:nowrap;
        margin:auto 20px;
      }
      .nd-btn.added { background:#2ecc71; }
    `;
    document.head.appendChild(s);
  }

  // Build a map of li -> date from group headers
  function getDateForRow(row) {
    // Walk up to the parent ul, then to its preceding sibling div with date
    const ul = row.closest('ul');
    if (!ul) return '';
    const prev = ul.previousElementSibling;
    if (!prev) return '';
    const h3 = prev.querySelector('h3');
    return h3 ? h3.textContent.trim() : '';
  }

  function injectButtons() {
    const rows = document.querySelectorAll('li.avarm3[data-automation-id^="wh-item-"]');
    rows.forEach(row => {
      if (row.dataset.ndInjected) return;
      const titleAnchor = row.querySelector('a._1NNx6V');
      const deleteForm  = row.querySelector('form[data-automation-id^="wh-delete-"]');
      if (!titleAnchor || !deleteForm) return;

      const href     = titleAnchor.getAttribute('href');
      const title    = titleAnchor.textContent.trim();
      const viewedAt = getDateForRow(row);

      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'nd-btn' + (addedHrefs.has(href) ? ' added' : '');
      btn.textContent = addedHrefs.has(href) ? '✓ Added' : '+ Add';

      btn.addEventListener('click', () => {
        const isAdded = btn.classList.contains('added');
        if (isAdded) {
          window.flutter_inappwebview.callHandler('nodisaarRemove', href);
          addedHrefs.delete(href);
          btn.classList.remove('added');
          btn.textContent = '+ Add';
        } else {
          window.flutter_inappwebview.callHandler('nodisaarAdd', {title, href, viewedAt});
          addedHrefs.add(href);
          btn.classList.add('added');
          btn.textContent = '✓ Added';
        }
      });

      deleteForm.parentNode.replaceChild(btn, deleteForm);
      row.dataset.ndInjected = '1';
    });
  }

  injectButtons();
  new MutationObserver(injectButtons).observe(document.body, {childList:true, subtree:true});
})();
''';