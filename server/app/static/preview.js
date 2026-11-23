/* 文件预览（图片缩放 + 上一张/下一张、视频、音频、PDF、文本/代码、压缩包目录、Office 结构化预览）。
 * 用法：ClipPreview.open([{name,kind,src,dl,size,archive,office}], index)
 *   kind: image | video | audio | pdf | text | archive | office ；src 为 inline 地址（?inline=1），dl 为下载地址
 * 所有文本一律用 textContent 渲染（不解析 HTML），Esc 关闭，←/→ 切换。 */
(function () {
  'use strict';
  var TEXT_LIMIT = 200 * 1024;
  var cur = null;

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function fmtSize(n) {
    if (!n) return '';
    var u = ['B', 'KB', 'MB', 'GB'], i = 0, v = n;
    while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
    return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)) + ' ' + u[i];
  }
  function fmtDur(s) {
    if (!isFinite(s)) return '';
    s = Math.round(s);
    var m = Math.floor(s / 60), r = s % 60;
    return m + ':' + (r < 10 ? '0' : '') + r;
  }

  function close() {
    if (!cur) return;
    stopMedia();
    document.removeEventListener('keydown', cur.onKey, true);
    cur.root.remove();
    document.body.classList.remove('pv-open');
    var back = cur.prevFocus;
    cur = null;
    if (back && back.focus) try { back.focus(); } catch (_) {}
  }
  function stopMedia() {
    if (!cur) return;
    cur.stage.querySelectorAll('video,audio').forEach(function (m) { try { m.pause(); m.removeAttribute('src'); m.load(); } catch (_) {} });
    if (cur.abort) { try { cur.abort.abort(); } catch (_) {} cur.abort = null; }
  }

  function show(i) {
    var st = cur; if (!st) return;
    stopMedia();
    st.i = (i + st.items.length) % st.items.length;
    var it = st.items[st.i];
    st.title.textContent = it.name || '';
    st.count.textContent = st.items.length > 1 ? (st.i + 1) + ' / ' + st.items.length : '';
    st.dl.href = it.dl || it.src;
    st.dl.setAttribute('download', it.name || '');
    st.prev.hidden = st.next.hidden = st.items.length < 2;
    st.stage.replaceChildren();
    st.stage.className = 'pv-stage pv-' + it.kind;
    var node;
    if (it.kind === 'image') {
      var img = el('img', 'pv-img'); img.alt = it.name || '';
      img.src = it.src; img.draggable = false;
      img.onerror = function () { st.stage.replaceChildren(el('p', 'pv-msg', '图片加载失败')); };
      img.onclick = function () { st.stage.classList.toggle('zoomed'); };
      var hint = el('p', 'pv-hint', '点击图片放大 / 还原');
      st.stage.append(img, hint);
    } else if (it.kind === 'video') {
      var v = document.createElement('video');
      v.controls = true; v.playsInline = true; v.preload = 'metadata'; v.src = it.src; v.className = 'pv-video';
      v.onerror = function () { st.stage.replaceChildren(msgDl('该视频格式浏览器无法播放', it)); };
      st.stage.append(v);
    } else if (it.kind === 'audio') {
      var box = el('div', 'pv-audio');
      box.append(el('div', 'pv-audio-ico', '♪'), el('div', 'pv-audio-name', it.name || ''));
      var dur = el('div', 'pv-audio-dur', fmtSize(it.size));
      var a = document.createElement('audio');
      a.controls = true; a.preload = 'metadata'; a.src = it.src;
      a.onloadedmetadata = function () { dur.textContent = '时长 ' + fmtDur(a.duration) + (it.size ? ' · ' + fmtSize(it.size) : ''); };
      a.onerror = function () { st.stage.replaceChildren(msgDl('该音频格式浏览器无法播放', it)); };
      box.append(a, dur);
      st.stage.append(box);
    } else if (it.kind === 'pdf') {
      node = document.createElement('iframe');
      node.className = 'pv-pdf'; node.src = it.src; node.title = it.name || 'PDF';
      st.stage.append(node);
      st.stage.append(el('p', 'pv-hint', '若无法显示，请点右上角下载'));
    } else if (it.kind === 'text') {
      var pre = el('pre', 'pv-text', '加载中…');
      st.stage.append(pre);
      var ac = (window.AbortController ? new AbortController() : null);
      st.abort = ac;
      fetch(it.src, { credentials: 'same-origin', headers: { Range: 'bytes=0-' + (TEXT_LIMIT - 1) }, signal: ac ? ac.signal : undefined })
        .then(function (r) {
          if (!r.ok && r.status !== 206) throw new Error('HTTP ' + r.status);
          return r.text().then(function (t) { return { t: t, partial: r.status === 206 && /\/(\d+)$/.test(r.headers.get('content-range') || '') && Number(RegExp.$1) > TEXT_LIMIT }; });
        })
        .then(function (o) {
          var t = o.t;
          if (!o.partial && /\.json$/i.test(it.name || '')) { try { t = JSON.stringify(JSON.parse(t), null, 2); } catch (_) {} }
          var full = t + (o.partial ? '\n\n… 仅显示前 200KB，完整内容请下载' : '');
          if (isCodeFile(it.name) && full.length <= 100000) {
            renderHighlighted(pre, full);
          } else {
            pre.textContent = full;
          }
        })
        .catch(function (e) { if (e && e.name === 'AbortError') return; pre.textContent = '加载失败：' + (e && e.message || e); });
    } else if (it.kind === 'archive' && it.archive) {
      renderArchive(st, it);
    } else if (it.kind === 'office' && it.office) {
      renderOffice(st, it);
    } else {
      st.stage.append(msgDl('此类型不支持在线预览', it));
    }
  }
  // ---- 压缩包目录（只列目录，不解压；全部用 textContent 渲染）----
  function buildTree(entries) {
    var root = { name: '', dir: true, kids: new Map(), size: 0, count: 0 };
    entries.forEach(function (e) {
      var parts = String(e.path).split('/').filter(function (x) { return x !== ''; });
      if (!parts.length) return;
      var n = root;
      parts.forEach(function (part, i) {
        var last = i === parts.length - 1;
        var key = part + (last && !e.is_dir ? '\u0000f' : '');
        var c = n.kids.get(key);
        if (!c) { c = { name: part, dir: !last || !!e.is_dir, kids: new Map(), size: 0, count: 0, mod: null }; n.kids.set(key, c); }
        if (last && !e.is_dir) { c.size = e.size || 0; c.mod = e.modified; c.enc = e.encrypted; }
        n = c;
      });
    });
    (function sum(n) {
      n.kids.forEach(function (c) { sum(c); if (c.dir) { n.size += c.size; n.count += c.count; } else { n.size += c.size; n.count += 1; } });
      return n;
    })(root);
    return root;
  }
  function renderNode(n, depth) {
    var frag = document.createDocumentFragment();
    var arr = Array.from(n.kids.values()).sort(function (a, b) { return (b.dir - a.dir) || a.name.localeCompare(b.name); });
    arr.forEach(function (c) {
      if (c.dir) {
        var d = document.createElement('details'); d.className = 'pv-dir'; if (depth < 1) d.open = true;
        var s = document.createElement('summary');
        s.append(el('span', 'pv-nm', '📁 ' + c.name), el('span', 'pv-sz', c.count + ' 项 · ' + fmtSize(c.size)));
        d.append(s, renderNode(c, depth + 1));
        frag.append(d);
      } else {
        var r = el('div', 'pv-file');
        r.append(el('span', 'pv-nm', (c.enc ? '🔒 ' : '📄 ') + c.name), el('span', 'pv-sz', fmtSize(c.size) || '0 B'));
        if (c.mod) r.title = c.mod;
        frag.append(r);
      }
    });
    return frag;
  }
  function renderArchive(st, it) {
    var box = el('div', 'pv-arch');
    var sum = el('p', 'pv-arch-sum', '正在读取目录…');
    var body = el('div', 'pv-arch-body');
    box.append(sum, body);
    st.stage.append(box);
    var ac = (window.AbortController ? new AbortController() : null);
    st.abort = ac;
    fetch(it.archive, { credentials: 'same-origin', signal: ac ? ac.signal : undefined })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (d) { return { ok: r.ok, d: d }; }); })
      .then(function (o) {
        if (!o.ok) { sum.textContent = (o.d && (o.d.error || o.d.detail)) || '无法读取压缩包目录'; sum.className = 'pv-arch-sum err'; return; }
        var d = o.d;
        var bits = [d.total + ' 项', '解压后约 ' + fmtSize(d.total_size)];
        if (d.encrypted) bits.push('含加密文件（只显示目录）');
        if (d.truncated) bits.push('仅显示前 ' + d.entries.length + ' 项');
        sum.textContent = bits.join(' · ');
        body.append(renderNode(buildTree(d.entries), 0));
        if (!d.entries.length) body.append(el('p', 'pv-hint2', '（空压缩包）'));
      })
      .catch(function (e) { if (e && e.name === 'AbortError') return; sum.textContent = '加载失败：' + (e && e.message || e); sum.className = 'pv-arch-sum err'; });
  }

  // ---- 轻量代码语法高亮（纯 DOM textContent，绝不使用 innerHTML）----
  var CODE_RE = /\.(?:py|js|ts|jsx|tsx|json|css|sh|bash|c|h|cpp|java|go|rs|sql|yaml|yml|toml|rb|php|xml|dart|swift|kt)$/i;
  var TOKEN_RE = /(\/\*[\s\S]*?\*\/|\/\/[^\n]*|#[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\b(?:function|return|const|let|var|if|else|for|while|switch|case|break|continue|class|extends|new|try|catch|finally|throw|async|await|import|export|from|def|lambda|with|as|pass|yield|None|True|False|true|false|null|undefined|int|float|str|bool|void|struct|enum|pub|fn|impl|match|SELECT|FROM|WHERE|INSERT|UPDATE|DELETE|CREATE|TABLE|JOIN|ORDER|GROUP|BY|LIMIT)\b|\b\d+(?:\.\d+)?\b)/g;
  function isCodeFile(name) { return CODE_RE.test(name || ''); }
  function renderHighlighted(pre, text) {
    var frag = document.createDocumentFragment();
    var last = 0, m;
    TOKEN_RE.lastIndex = 0;
    while ((m = TOKEN_RE.exec(text)) !== null) {
      if (m.index > last) frag.append(document.createTextNode(text.slice(last, m.index)));
      var tok = m[0], cls = 'hl-kw';
      if (tok.startsWith('//') || tok.startsWith('/*') || tok.startsWith('#')) cls = 'hl-cmt';
      else if (tok[0] === '"' || tok[0] === "'" || tok[0] === '`') cls = 'hl-str';
      else if (/^\d/.test(tok)) cls = 'hl-num';
      frag.append(el('span', cls, tok));
      last = TOKEN_RE.lastIndex;
    }
    if (last < text.length) frag.append(document.createTextNode(text.slice(last)));
    pre.replaceChildren(frag);
  }

  // ---- Office 文档结构化预览（docx / xlsx / xls / csv / pptx；全部用 textContent 渲染）----
  function colName(idx) {
    var s = '', n = idx;
    while (n >= 0) {
      s = String.fromCharCode(65 + (n % 26)) + s;
      n = Math.floor(n / 26) - 1;
    }
    return s;
  }
  function renderRuns(parent, blk) {
    if (!blk.runs || !blk.runs.length) {
      parent.textContent = blk.text || '';
      return;
    }
    blk.runs.forEach(function (r) {
      var node = document.createTextNode(r.t || '');
      if (r.s) { var s = document.createElement('s'); s.append(node); node = s; }
      if (r.u) { var u = document.createElement('u'); u.append(node); node = u; }
      if (r.i) { var em = document.createElement('em'); em.append(node); node = em; }
      if (r.b) { var st = document.createElement('strong'); st.append(node); node = st; }
      parent.append(node);
    });
  }
  function renderOfficeTable(tb) {
    var wrap = el('div', 'pv-tbl-wrap');
    var table = document.createElement('table');
    table.className = 'pv-tbl';
    var tbody = document.createElement('tbody');
    (tb.rows || []).forEach(function (row, ri) {
      var tr = document.createElement('tr');
      row.forEach(function (cell) {
        var td = document.createElement(ri === 0 ? 'th' : 'td');
        td.textContent = (cell && cell.text) || '';
        if (cell && cell.colspan > 1) td.colSpan = cell.colspan;
        tr.append(td);
      });
      tbody.append(tr);
    });
    table.append(tbody);
    wrap.append(table);
    if (tb.truncated) wrap.append(el('p', 'pv-hint2', '（表格行列过多，仅显示前部分内容）'));
    return wrap;
  }
  function renderOfficeBlocks(parent, blocks) {
    (blocks || []).forEach(function (b) {
      if (b.kind === 'heading') {
        var lvl = Math.max(1, Math.min(6, b.level || 2));
        parent.append(el('h' + lvl, 'pv-h pv-h' + lvl, b.text || ''));
      } else if (b.kind === 'paragraph') {
        var p = el('p', b.list ? 'pv-p pv-li' : 'pv-p');
        if (b.indent) p.style.marginLeft = (b.indent * 18) + 'px';
        if (b.list) p.append(el('span', 'pv-bullet', '• '));
        var span = document.createElement('span');
        renderRuns(span, b);
        p.append(span);
        parent.append(p);
      } else if (b.kind === 'table') {
        parent.append(renderOfficeTable(b));
      } else if (b.kind === 'image' && typeof b.src === 'string' && b.src.indexOf('data:image/') === 0) {
        var img = el('img', 'pv-doc-img');
        img.src = b.src;
        img.alt = b.alt || '嵌入图片';
        img.loading = 'lazy';
        parent.append(img);
      }
    });
  }
  function renderOffice(st, it) {
    var box = el('div', 'pv-office');
    var sum = el('p', 'pv-arch-sum', '正在解析文档…');
    var tabs = el('div', 'pv-tabs');
    tabs.hidden = true;
    var body = el('div', 'pv-off-body');
    box.append(sum, tabs, body);
    st.stage.append(box);
    var ac = (window.AbortController ? new AbortController() : null);
    st.abort = ac;
    fetch(it.office, { credentials: 'same-origin', signal: ac ? ac.signal : undefined })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (d) { return { ok: r.ok, d: d }; }); })
      .then(function (o) {
        if (!o.ok) {
          sum.textContent = (o.d && (o.d.error || o.d.detail)) || '无法预览此 Office 文档';
          sum.className = 'pv-arch-sum err';
          body.append(msgDl('可下载后使用本机办公软件打开', it));
          return;
        }
        var d = o.d;
        var m = d.meta || {};
        if (d.type === 'docx') {
          var bits = ['Word 文档', (m.paragraphs || 0) + ' 段'];
          if (m.tables) bits.push(m.tables + ' 个表格');
          if (m.images) bits.push(m.images + ' 张图片');
          if (m.omitted_images) bits.push('已省略 ' + m.omitted_images + ' 张大图/超额图');
          if (d.truncated) bits.push('仅显示前部分内容');
          sum.textContent = bits.join(' · ');
          body.className = 'pv-off-body pv-doc';
          if (d.title) body.append(el('div', 'pv-doc-title', d.title));
          renderOfficeBlocks(body, d.blocks);
          if (!(d.blocks && d.blocks.length)) body.append(el('p', 'pv-hint2', '（空白文档）'));
        } else if (d.type === 'xlsx' || d.type === 'xls' || d.type === 'csv') {
          var sheets = d.sheets || [];
          var kindLbl = d.type === 'csv' ? 'CSV 表格' : 'Excel 表格';
          body.className = 'pv-off-body pv-sheet';
          if (!sheets.length) {
            sum.textContent = kindLbl + ' · 0 个工作表';
            body.append(el('p', 'pv-hint2', '（空工作簿）'));
            return;
          }
          var showSheet = function (si) {
            var sh = sheets[si];
            Array.from(tabs.children).forEach(function (btn, idx) {
              btn.setAttribute('aria-selected', idx === si ? 'true' : 'false');
            });
            var rows = sh.rows || [];
            var cols = rows.length ? rows[0].length : 0;
            var bits = [kindLbl, '共 ' + (m.total_sheets || sheets.length) + ' 个工作表', sh.name + '（' + (sh.total_rows || rows.length) + ' 行 × ' + (sh.total_cols || cols) + ' 列）'];
            if (sh.truncated_rows || sh.truncated_cols) bits.push('仅显示前 ' + rows.length + ' 行 × ' + cols + ' 列');
            else if (d.truncated) bits.push('部分工作表已截断');
            sum.textContent = bits.join(' · ');
            body.replaceChildren();
            if (!rows.length) {
              body.append(el('p', 'pv-hint2', '（空白工作表）'));
              return;
            }
            var table = document.createElement('table');
            table.className = 'pv-grid';
            var thead = document.createElement('thead');
            var htr = document.createElement('tr');
            htr.append(el('th', 'pv-rn', ''));
            for (var c = 0; c < cols; c++) htr.append(el('th', null, colName(c)));
            thead.append(htr);
            var tbody = document.createElement('tbody');
            rows.forEach(function (r, ri) {
              var tr = document.createElement('tr');
              tr.append(el('th', 'pv-rn', String(ri + 1)));
              for (var c = 0; c < cols; c++) tr.append(el('td', null, r[c] != null ? String(r[c]) : ''));
              tbody.append(tr);
            });
            table.append(thead, tbody);
            body.append(table);
          };
          tabs.hidden = false;
          sheets.forEach(function (sh, idx) {
            var b = el('button', 'pv-tab', sh.name || ('Sheet' + (idx + 1)));
            b.type = 'button';
            b.setAttribute('role', 'tab');
            b.onclick = function () { showSheet(idx); };
            tabs.append(b);
          });
          showSheet(0);
        } else if (d.type === 'pptx') {
          var slides = d.slides || [];
          var pbits = ['PowerPoint 演示文稿', '共 ' + (m.total_slides || slides.length) + ' 页'];
          if (m.images) pbits.push(m.images + ' 张图片');
          if (m.omitted_images) pbits.push('已省略 ' + m.omitted_images + ' 张图');
          if (d.truncated) pbits.push('仅显示前 ' + slides.length + ' 页');
          sum.textContent = pbits.join(' · ');
          body.className = 'pv-off-body pv-slides';
          if (!slides.length) {
            body.append(el('p', 'pv-hint2', '（空演示文稿）'));
            return;
          }
          slides.forEach(function (sl) {
            var card = el('section', 'pv-slide');
            var head = el('div', 'pv-slide-head');
            head.append(el('span', 'pv-slide-num', sl.index + ' / ' + slides.length));
            if (sl.title) head.append(el('h3', 'pv-slide-title', sl.title));
            card.append(head);
            var sb = el('div', 'pv-slide-body');
            renderOfficeBlocks(sb, sl.blocks);
            if (!(sl.blocks && sl.blocks.length) && !sl.title) sb.append(el('p', 'pv-hint2', '（此页无文本内容）'));
            card.append(sb);
            if (sl.notes) {
              var notes = el('div', 'pv-slide-notes');
              notes.append(el('b', null, '演讲者备注：'), document.createTextNode(sl.notes));
              card.append(notes);
            }
            body.append(card);
          });
        } else {
          sum.textContent = '不支持的 Office 预览响应';
          sum.className = 'pv-arch-sum err';
        }
      })
      .catch(function (e) { if (e && e.name === 'AbortError') return; sum.textContent = '加载失败：' + (e && e.message || e); sum.className = 'pv-arch-sum err'; });
  }

  function msgDl(text, it) {
    var w = el('div', 'pv-msg');
    w.append(el('p', null, text));
    var a = el('a', 'btn btn--accent', '下载文件');
    a.href = it.dl || it.src; a.setAttribute('download', it.name || '');
    w.append(a);
    return w;
  }

  function open(items, index) {
    if (!items || !items.length) return;
    close();
    var root = el('div', 'pv'); root.setAttribute('role', 'dialog'); root.setAttribute('aria-modal', 'true');
    var head = el('div', 'pv-head');
    var title = el('div', 'pv-title'), count = el('div', 'pv-count');
    var dl = el('a', 'pv-btn', '下载'); dl.setAttribute('aria-label', '下载');
    var x = el('button', 'pv-btn pv-x', '✕'); x.type = 'button'; x.setAttribute('aria-label', '关闭 (Esc)');
    head.append(title, count, dl, x);
    var stage = el('div', 'pv-stage');
    var prev = el('button', 'pv-nav pv-prev', '‹'); prev.type = 'button'; prev.setAttribute('aria-label', '上一个');
    var next = el('button', 'pv-nav pv-next', '›'); next.type = 'button'; next.setAttribute('aria-label', '下一个');
    root.append(head, stage, prev, next);
    document.body.append(root);
    document.body.classList.add('pv-open');
    var st = { root: root, stage: stage, title: title, count: count, dl: dl, prev: prev, next: next, items: items, i: 0,
      prevFocus: document.activeElement };
    st.onKey = function (e) {
      if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(); }
      else if (e.key === 'ArrowLeft') { show(st.i - 1); }
      else if (e.key === 'ArrowRight') { show(st.i + 1); }
    };
    cur = st;
    document.addEventListener('keydown', st.onKey, true);
    x.onclick = close;
    prev.onclick = function () { show(st.i - 1); };
    next.onclick = function () { show(st.i + 1); };
    // 点击空白处关闭（不含媒体本体）
    stage.addEventListener('click', function (e) { if (e.target === stage) close(); });
    // 触摸滑动切换
    var sx = null;
    stage.addEventListener('touchstart', function (e) { sx = e.touches.length === 1 ? e.touches[0].clientX : null; }, { passive: true });
    stage.addEventListener('touchend', function (e) {
      if (sx == null || stage.classList.contains('zoomed')) return;
      var dx = e.changedTouches[0].clientX - sx; sx = null;
      if (Math.abs(dx) > 70 && st.items.length > 1) show(st.i + (dx < 0 ? 1 : -1));
    }, { passive: true });
    show(index || 0);
    x.focus();
  }

  window.ClipPreview = { open: open, close: close };
})();
