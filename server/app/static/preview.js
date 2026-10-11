/* 文件预览（图片缩放 + 上一张/下一张、视频、音频、PDF、文本/代码）。
 * 用法：ClipPreview.open([{name,kind,src,dl,size}], index)
 *   kind: image | video | audio | pdf | text ；src 为 inline 地址（?inline=1），dl 为下载地址
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
          pre.textContent = t + (o.partial ? '\n\n… 仅显示前 200KB，完整内容请下载' : '');
        })
        .catch(function (e) { if (e && e.name === 'AbortError') return; pre.textContent = '加载失败：' + (e && e.message || e); });
    } else if (it.kind === 'archive' && it.archive) {
      renderArchive(st, it);
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
