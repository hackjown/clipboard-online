/* Clipboard Online — 增强版前端 */
(() => {
  'use strict';
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const SVGNS = 'http://www.w3.org/2000/svg';

  function h(tag, props, ...kids) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(props || {})) {
      if (v == null || v === false) continue;
      if (k === 'class') el.className = v;
      else if (k === 'text') el.textContent = v;
      else if (k === 'html') el.innerHTML = v;
      else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
      else el.setAttribute(k, v === true ? '' : v);
    }
    for (const c of kids.flat()) {
      if (c == null || c === false) continue;
      el.append(c.nodeType ? c : document.createTextNode(String(c)));
    }
    return el;
  }

  const P = (d) => `<path d="${d}"/>`;
  const ICONS = {
    clip: P('M8 7v9a4 4 0 0 0 8 0V6a2.5 2.5 0 0 0-5 0v9.5a1 1 0 0 0 2 0V8'),
    plus: P('M12 5v14M5 12h14'),
    upload: P('M12 16V4M7 9l5-5 5 5M4 16v3a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-3'),
    download: P('M12 4v12M7 11l5 5 5-5M4 20h16'),
    eye: P('M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z') + '<circle cx="12" cy="12" r="3"/>',
    search: '<circle cx="11" cy="11" r="6.5"/>' + P('m20 20-4.2-4.2'),
    text: P('M5 6h14M5 11h14M5 16h9'),
    file: P('M7 3h7l5 5v12a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM14 3v5h5'),
    trash: P('M4 7h16M10 11v6M14 11v6M6 7l1 12a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-12M9 7V4h6v3'),
    copy: '<rect x="9" y="9" width="11" height="11" rx="2"/>' + P('M5 15V6a2 2 0 0 1 2-2h8'),
    check: P('m5 12.5 4.5 4.5L19 7.5'),
    sun: '<circle cx="12" cy="12" r="4"/>' + P('M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4'),
    moon: P('M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z'),
    auto: '<circle cx="12" cy="12" r="8"/>' + '<path d="M12 4a8 8 0 0 1 0 16z" fill="currentColor"/>',
    chev: P('m6 9 6 6 6-6'),
    alert: P('M12 4 2.8 19.5h18.4zM12 10v4.5M12 17.4v.1'),
    x: P('M6 6l12 12M18 6 6 18'),
    logout: P('M10 4H6a1 1 0 0 0-1 1v14a1 1 0 0 0 1 1h4M15 8l4 4-4 4M19 12H9'),
    lock: P('M8 11V8a4 4 0 0 1 8 0v3M7 11h10v10H7z'),
    globe: '<circle cx="12" cy="12" r="9"/>' + P('M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18'),
    user: '<circle cx="12" cy="9" r="3.5"/>' + P('M5 20a7 7 0 0 1 14 0'),
    star: P('M12 3l2.9 5.9 6.5.9-4.7 4.6 1.1 6.5L12 18.3 6.2 21l1.1-6.5L2.6 9.8l6.5-.9z'),
    pin: P('M12 17v5M8 3h8l-1 7h3l-6 6-6-6h3z'),
    share: P('M16 6a3 3 0 1 0-2.8-4M16 6l-8 5M8 11a3 3 0 1 0 0 2M8 13l8 5M16 18a3 3 0 1 0 0 0.01'),
    clock: '<circle cx="12" cy="12" r="9"/>' + P('M12 7v5l3 2'),
    tag: P('M4 11V5a1 1 0 0 1 1-1h6l9 9-7 7zM7.5 7.5h.01'),
  };
  function iconSVG(name) {
    return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ''}</svg>`;
  }
  function icon(name) { const s = h('span', { class: 'ico' }); s.innerHTML = iconSVG(name); return s; }
  function hydrateIcons(root = document) { $$('.ico[data-i]', root).forEach((e) => { e.innerHTML = iconSVG(e.dataset.i); }); }

  const CATS = {
    pdf: ['#d93a2b', 'pdf'], doc: ['#2f6feb', 'doc docx rtf odt pages'], sheet: ['#1d8f4e', 'xls xlsx csv tsv numbers ods'],
    slide: ['#e07b18', 'ppt pptx key odp'], image: ['#a642b8', 'png jpg jpeg gif webp svg bmp heic avif ico tiff'],
    archive: ['#a8741a', 'zip rar 7z tar gz tgz bz2 xz zst'],
    code: ['#0f8fa3', 'js ts jsx tsx py json html htm css sh bash zsh java c h cpp go rs php rb yml yaml xml sql toml ini md lua swift kt'],
    audio: ['#d93d78', 'mp3 wav flac aac m4a ogg opus'], video: ['#6b46d9', 'mp4 mov avi mkv webm m4v'],
    app: ['#4b5563', 'apk exe dmg msi deb rpm pkg ipa iso'], text: ['#5b5b52', 'txt log'],
  };
  const EXT2CAT = {};
  for (const [cat, [, exts]] of Object.entries(CATS)) exts.split(' ').forEach((e) => (EXT2CAT[e] = cat));
  const GLYPH = {
    pdf: 'M13 22h24M13 28h24M13 34h14', doc: 'M13 22h24M13 28h24M13 34h16', text: 'M13 23h24M13 29h20M13 35h24',
    sheet: 'M13 21h24v15H13zM13 26h24M13 31h24M21 21v15M29 21v15', slide: 'M14 36V28M21 36V22M28 36V30M35 36V25',
    image: 'M13 36l8-9 6 6 4-4 6 7M13 21h24v15H13z', archive: 'M25 20v3M25 25v3M25 30v3M22 22.5h3M25 27.5h3M22 32.5h3',
    code: 'M20 23l-6 6 6 6M30 23l6 6-6 6', audio: 'M21 35V22l12-3v13M21 35a3 3 0 1 1-3-3 3 3 0 0 1 3 3zM33 32a3 3 0 1 1-3-3 3 3 0 0 1 3 3z',
    video: 'M19 21l14 8-14 8z', app: 'M13 25l12-6 12 6v10l-12 6-12-6zM13 25l12 6 12-6M25 31v10', def: 'M13 23h24M13 29h24M13 35h12',
  };
  function catOf(ext) { return EXT2CAT[(ext || '').toLowerCase()] || 'def'; }
  function fileTile(ext) {
    const cat = catOf(ext);
    const col = (CATS[cat] || ['#5b5b52'])[0];
    const label = (ext || 'file').replace(/[^a-z0-9]/gi, '').slice(0, 4).toUpperCase() || 'FILE';
    const g = GLYPH[cat] || GLYPH.def;
    const w = h('div', { class: 'ftile', 'aria-hidden': 'true' });
    w.style.setProperty('--c', col);
    w.innerHTML = `<svg viewBox="0 0 52 62" fill="none"><path d="M5 2.5h29l14 14v42a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-54a2 2 0 0 1 2-2z" fill="var(--paper)" stroke="currentColor" stroke-width="3" stroke-linejoin="round"/>` +
      `<path d="M34 2.5v14h14" stroke="currentColor" stroke-width="3" stroke-linejoin="round" fill="var(--paper-2)"/>` +
      `<path d="${g}" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>` +
      `<rect x="1" y="42" width="${12 + label.length * 7.4}" height="16" rx="4" fill="currentColor"/>` +
      `<text x="${1 + (12 + label.length * 7.4) / 2}" y="53.2" text-anchor="middle" font-family="ui-monospace,Menlo,Consolas,monospace" font-weight="800" font-size="10" fill="#fff">${label}</text></svg>`;
    return w;
  }

  function fmtSize(n) {
    if (!n) return '0 B';
    const u = ['B', 'KB', 'MB', 'GB', 'TB']; let i = 0; let v = n;
    while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
    return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)) + ' ' + u[i];
  }
  const pad = (n) => String(n).padStart(2, '0');
  function fmtFull(ts) { const d = new Date(ts * 1000); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`; }
  function fmtTime(ts) {
    const d = new Date(ts * 1000), now = new Date(); const s = (now - d) / 1000;
    if (s < 45) return '刚刚';
    if (s < 3600) return Math.floor(s / 60 + .5) + ' 分钟前';
    const hm = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    const day = (x) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
    const diff = Math.round((day(now) - day(d)) / 86400000);
    if (diff === 0) return `今天 ${hm}`;
    if (diff === 1) return `昨天 ${hm}`;
    if (d.getFullYear() === now.getFullYear()) return `${d.getMonth() + 1}月${d.getDate()}日 ${hm}`;
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  }
  function fmtRemain(exp) {
    if (!exp) return null;
    const s = exp - Date.now() / 1000;
    if (s <= 0) return { text: '已过期', cls: 'dead' };
    if (s < 3600) return { text: Math.ceil(s / 60) + ' 分钟后过期', cls: 'warn' };
    if (s < 86400) return { text: Math.ceil(s / 3600) + ' 小时后过期', cls: 'warn' };
    return { text: Math.ceil(s / 86400) + ' 天后过期', cls: '' };
  }
  function looksLikeCode(t) {
    const s = t.trim();
    if (!s) return false;
    if (/^[\x21-\x7e]{20,}$/.test(s)) return true;
    if (/^(\$ |#!|sudo |git |curl |wget |npm |npx |pip3? |docker |ssh )/m.test(s)) return true;
    const lines = s.split('\n');
    const hits = lines.filter((l) => /[{};]\s*$|=>|^\s*(def|class|function|const|let|var|import)\b/.test(l)).length;
    return lines.length >= 2 && hits >= 2;
  }
  function highlight(text, q) {
    if (!q) return [text];
    const out = []; const lo = text.toLowerCase(); const ql = q.toLowerCase(); let i = 0;
    for (;;) {
      const j = lo.indexOf(ql, i);
      if (j < 0) { out.push(text.slice(i)); break; }
      if (j > i) out.push(text.slice(i, j));
      out.push(h('mark', { class: 'hl', text: text.slice(j, j + q.length) }));
      i = j + q.length;
    }
    return out;
  }

  /* sensitive heuristics */
  function isSensitive(text) {
    if (!text) return false;
    const t = text;
    if (/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/.test(t)) return true;
    if (/\bAKIA[0-9A-Z]{16}\b/.test(t)) return true;
    if (/\bsk-[A-Za-z0-9]{20,}\b/.test(t)) return true;
    if (/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/.test(t)) return true;
    if (/(?:password|passwd|pwd|secret|api[_-]?key)\s*[=:]\s*\S+/i.test(t)) return true;
    if (/^[A-Za-z0-9+/=]{80,}$/.test(t.trim()) && /[+\/=]/.test(t)) return true;
    // high-entropy long token
    if (/^[A-Za-z0-9_\-]{40,}$/.test(t.trim())) return true;
    return false;
  }

  /* tiny markdown → safe HTML */
  function escHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  function renderMd(src) {
    let t = src.replace(/\r\n/g, '\n');
    // fenced code
    t = t.replace(/```[\w]*\n([\s\S]*?)```/g, (_, c) => `<pre><code>${escHtml(c.replace(/\n$/, ''))}</code></pre>`);
    const lines = t.split('\n');
    const out = [];
    let listType = null;
    const flushList = () => { if (listType) { out.push(listType === 'ol' ? '</ol>' : '</ul>'); listType = null; } };
    for (let line of lines) {
      if (/^```/.test(line)) continue;
      if (line.startsWith('<pre>')) { flushList(); out.push(line); continue; }
      let m;
      if ((m = /^(#{1,3})\s+(.+)$/.exec(line))) {
        flushList(); const n = m[1].length;
        out.push(`<h${n}>${inlineMd(m[2])}</h${n}>`); continue;
      }
      if ((m = /^(\d+)\.\s+(.+)$/.exec(line))) {
        if (listType !== 'ol') { flushList(); out.push('<ol>'); listType = 'ol'; }
        out.push(`<li>${inlineMd(m[2])}</li>`); continue;
      }
      if ((m = /^[-*]\s+(.+)$/.exec(line))) {
        if (listType !== 'ul') { flushList(); out.push('<ul>'); listType = 'ul'; }
        out.push(`<li>${inlineMd(m[1])}</li>`); continue;
      }
      flushList();
      if (!line.trim()) { out.push(''); continue; }
      out.push(`<p>${inlineMd(line)}</p>`);
    }
    flushList();
    return out.join('\n');
  }
  function inlineMd(s) {
    let t = escHtml(s);
    t = t.replace(/`([^`]+)`/g, '<code>$1</code>');
    t = t.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    t = t.replace(/(?<!\*)\*([^*]+)\*(?!\*)/g, '<em>$1</em>');
    t = t.replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');
    return t;
  }

  const state = {
    items: [], counts: { total: 0, text: 0, file: 0, bytes: 0, public: 0, private: 0, starred: 0 },
    tags: [], filter: 'all', scope: 'public', q: '', tag: '', starred: false, loaded: false,
    user: null, cfg: { register: true, max_upload: 200 * 1048576 },
    ws: false,
  };
  const list = $('#list');
  const cache = new Map();
  let polling = false, again = null, pollTimer = null;

  async function api(path, opt = {}) {
    const init = { method: opt.method || 'GET', credentials: 'same-origin', headers: {} };
    if (opt.body !== undefined) { init.headers['Content-Type'] = 'application/json'; init.body = JSON.stringify(opt.body); }
    const r = await fetch(path, init);
    let data = null; try { data = await r.json(); } catch (_) {}
    if (!r.ok) throw new Error((data && (data.error || data.detail)) || `请求失败 (${r.status})`);
    return data;
  }

  function toast(msg, kind = 'ok') {
    const box = $('#toasts');
    while (box.children.length >= 3) box.firstChild.remove();
    const t = h('div', { class: 'toast' + (kind === 'err' ? ' err' : '') }, h('span', { class: 't-ico' }, icon(kind === 'err' ? 'x' : 'check')), h('span', { text: msg }));
    box.append(t);
    setTimeout(() => { t.classList.add('out'); setTimeout(() => t.remove(), 320); }, kind === 'err' ? 3800 : 2400);
  }

  async function copyText(t) {
    try { if (navigator.clipboard && window.isSecureContext) { await navigator.clipboard.writeText(t); return true; } } catch (_) {}
    const ta = h('textarea', { 'aria-hidden': 'true', readonly: true });
    ta.style.cssText = 'position:fixed;top:0;left:0;opacity:0;font-size:16px';
    ta.value = t; document.body.append(ta); ta.focus(); ta.select();
    let ok = false; try { ok = document.execCommand('copy'); } catch (_) {}
    ta.remove(); return ok;
  }

  // 预览：当前列表中所有可预览的文件（图片可左右切换）；inline=1 走白名单内联端点
  function previewItems() {
    return state.items.filter((x) => matches(x) && x.type === 'file' && x.preview).map((x) => ({
      id: x.uuid, name: x.filename, kind: x.preview, size: x.size,
      src: '/download/' + encodeURIComponent(x.filename) + '?inline=1',
      dl: '/download/' + encodeURIComponent(x.filename),
    }));
  }
  function openPreview(it) {
    const list = previewItems();
    let i = list.findIndex((x) => x.id === it.uuid);
    if (i < 0) return;
    window.ClipPreview.open(list, i);
  }

  function makeCard(it) {
    const card = { id: it.uuid, it, q: null, md: false };
    const timeEl = h('span', { class: 'meta' });
    const art = h('article', { class: 'card ' + (it.type === 'text' ? 'card--text' : 'card--file') });
    const slot = h('li', { class: 'slot', 'data-id': it.uuid }, h('div', { class: 'slot-in' }, art));
    card.el = slot;

    const visChip = h('span', { class: 'chip ' + (it.visibility === 'public' ? 'chip--pub' : 'chip--priv') },
      icon(it.visibility === 'public' ? 'globe' : 'lock'), it.visibility === 'public' ? '公共' : '私有');
    const typeChip = h('span', { class: 'chip ' + (it.type === 'text' ? 'chip--text' : 'chip--file') },
      icon(it.type === 'text' ? 'text' : 'file'), it.type === 'text' ? '文本' : '文件');
    const headKids = [typeChip, visChip];
    const rem = fmtRemain(it.expires_at);
    if (rem) headKids.push(h('span', { class: 'exp-pill ' + rem.cls }, icon('clock'), rem.text));
    headKids.push(timeEl);
    if (it.visibility === 'public' && it.owner_username) headKids.push(h('span', { class: 'owner', text: '@' + it.owner_username }));
    art.append(h('div', { class: 'card-head' }, ...headKids));

    const tools = h('div', { class: 'card-tools' });
    if (state.user) {
      const star = h('button', { type: 'button', class: 'star-btn' + (it.favorite ? ' on' : ''), title: '收藏',
        onclick: async () => {
          try {
            const r = await api('/api/items/' + it.uuid + '/favorite', { method: 'POST' });
            it.favorite = r.favorite; star.classList.toggle('on', r.favorite); toast(r.favorite ? '已收藏' : '已取消收藏');
            refreshScoped();
          } catch (e) { toast(e.message, 'err'); }
        } }, icon('star'));
      tools.append(star);
    }
    if (it.mine) {
      const pin = h('button', { type: 'button', class: 'pin-btn' + (it.pinned ? ' on' : ''), title: '置顶',
        onclick: async () => {
          try {
            const r = await api('/api/items/' + it.uuid + '/pin', { method: 'POST' });
            it.pinned = r.pinned; pin.classList.toggle('on', r.pinned); toast(r.pinned ? '已置顶' : '已取消置顶');
            refreshScoped();
          } catch (e) { toast(e.message, 'err'); }
        } }, icon('pin'));
      const share = h('button', { type: 'button', class: 'share-btn', title: '分享', onclick: () => openShare(it) }, icon('share'));
      const tagb = h('button', { type: 'button', class: 'tag-btn', title: '标签', onclick: () => openTags(it) }, icon('tag'));
      tools.append(pin, share, tagb);
    }
    if (tools.childNodes.length) art.append(tools);

    if (it.tags && it.tags.length) {
      art.append(h('div', { class: 'tags' }, ...it.tags.map((t) =>
        h('button', { type: 'button', class: 'tag' + (state.tag === t ? ' on' : ''), text: t, onclick: () => setTag(state.tag === t ? '' : t) }))));
    }

    const actions = h('div', { class: 'actions wrap' });
    if (it.mine) {
      actions.append(h('button', { type: 'button', class: 'btn btn--del sm', onclick: () => confirmDelete(it) }, icon('trash'), h('span', { text: '删除' })));
    }

    if (it.type === 'text') {
      const chars = [...it.content].length;
      const mono = looksLikeCode(it.content) && !it.looks_md;
      const body = h('div', { class: 'text-body' + (mono ? ' mono' : '') });
      const mdBody = h('div', { class: 'md-body', hidden: true });
      const box = h('div', { class: 'clampbox' }, body, mdBody);
      const more = h('button', { type: 'button', class: 'more', hidden: true }, h('span', { text: '展开全文' }), icon('chev'));
      more.addEventListener('click', () => {
        const open = box.classList.toggle('open');
        more.firstChild.textContent = open ? '收起' : '展开全文';
      });
      let mdOn = false;
      const mdToggle = it.looks_md ? h('button', { type: 'button', class: 'md-toggle', text: '预览 Markdown', onclick: () => {
        mdOn = !mdOn;
        body.hidden = mdOn; mdBody.hidden = !mdOn;
        mdToggle.textContent = mdOn ? '查看原文' : '预览 Markdown';
        if (mdOn) mdBody.innerHTML = renderMd(it.content);
        requestAnimationFrame(measure);
      } }) : null;

      const copy = h('button', { type: 'button', class: 'btn btn--ink sm' }, icon('copy'), h('span', { text: '复制' }));
      let timer = null;
      copy.addEventListener('click', async () => {
        if (!(await copyText(it.content))) { toast('复制失败', 'err'); return; }
        copy.classList.add('done'); copy.replaceChildren(icon('check'), h('span', { text: '已复制' }));
        clearTimeout(timer);
        timer = setTimeout(() => { copy.classList.remove('done'); copy.replaceChildren(icon('copy'), h('span', { text: '复制' })); }, 2000);
      });
      actions.prepend(copy);
      if (mdToggle) art.append(mdToggle);
      art.append(box, more);

      // OG for single URL
      if (it.is_url) {
        const og = h('a', { class: 'og-card noimg', href: it.content.trim(), target: '_blank', rel: 'noopener' },
          h('div', {}, h('div', { class: 'og-t', text: '加载预览…' }), h('div', { class: 'og-d', text: it.content.trim() })));
        art.append(og);
        fetch('/api/og?url=' + encodeURIComponent(it.content.trim())).then((r) => r.json()).then((d) => {
          og.replaceChildren();
          if (d.image) {
            og.classList.remove('noimg');
            og.append(h('img', { src: d.image, alt: '', referrerpolicy: 'no-referrer', onerror: (e) => e.target.remove() }));
          }
          og.append(h('div', {}, h('div', { class: 'og-t', text: d.title || d.domain }), h('div', { class: 'og-d', text: d.domain || '' })));
        }).catch(() => {});
      }

      art.append(actions);
      card.setQuery = (q) => {
        if (card.q === q) return; card.q = q;
        body.replaceChildren(...highlight(it.content, q));
        requestAnimationFrame(measure);
      };
      const measure = () => {
        if (!box.isConnected) return;
        const el = mdOn ? mdBody : body;
        const was = box.classList.contains('open');
        const over = el.scrollHeight > (mdOn ? 200 : body.clientHeight + 6) || was;
        box.classList.toggle('clamped', over && !was && !mdOn);
        more.hidden = !over;
      };
      card.measure = measure;
      card.tick = () => {
        timeEl.replaceChildren(fmtTime(it.created), h('span', { class: 'sep', text: '·' }), `${chars} 字`);
        timeEl.title = fmtFull(it.created);
      };
    } else {
      const name = h('div', { class: 'fname' });
      const sub = h('div', { class: 'fsub', text: `${(it.ext || '—').toUpperCase()} · ${fmtSize(it.size)}` });
      if (it.is_image) {
        const src = '/download/' + encodeURIComponent(it.filename);
        const img = h('img', { class: 'thumb', src, alt: it.filename, loading: 'lazy', onclick: () => openPreview(it) });
        art.append(img);
      }
      const row = h('div', { class: 'file-row' + (it.preview ? ' pv-able' : '') }, fileTile(it.ext), h('div', { class: 'fmeta' }, name, sub));
      if (it.preview && !it.is_image) { row.onclick = () => openPreview(it); row.title = '点击预览'; }
      art.append(row);
      const dl = h('a', { class: 'btn btn--ink sm', href: '/download/' + encodeURIComponent(it.filename), download: it.filename }, icon('download'), h('span', { text: '下载' }));
      actions.prepend(dl);
      if (it.preview) {
        const pv = h('button', { class: 'btn sm', type: 'button', onclick: () => openPreview(it) }, icon('eye'), h('span', { text: '预览' }));
        actions.prepend(pv);
      }
      art.append(actions);
      card.setQuery = (q) => { if (card.q === q) return; card.q = q; name.replaceChildren(...highlight(it.filename, q)); };
      card.tick = () => { timeEl.replaceChildren(fmtTime(it.created)); timeEl.title = fmtFull(it.created); };
    }
    return card;
  }

  function matches(it) {
    if (state.filter !== 'all' && it.type !== state.filter) return false;
    if (state.starred && !it.favorite) return false;
    if (state.tag && !(it.tags || []).includes(state.tag)) return false;
    if (!state.q) return true;
    const hay = ((it.type === 'text' ? it.content : it.filename) + ' ' + (it.owner_username || '') + ' ' + (it.tags || []).join(' ')).toLowerCase();
    return hay.includes(state.q.toLowerCase());
  }

  let firstPaint = true;
  function render(freshIds) {
    $$('.skel', list).forEach((e) => e.remove());
    const ids = new Set(state.items.map((i) => i.uuid));
    for (const [id, c] of cache) if (!ids.has(id)) { if (!c.el.classList.contains('leaving')) c.el.remove(); cache.delete(id); }
    const vis = state.items.filter(matches);
    const keep = new Set(vis.map((i) => i.uuid));
    for (const el of Array.from(list.children)) if (!el.classList.contains('leaving') && !keep.has(el.dataset.id)) el.remove();
    const live = () => Array.from(list.children).filter((e) => !e.classList.contains('leaving'));
    vis.forEach((it, idx) => {
      let c = cache.get(it.uuid);
      const sig = [it.mine, it.favorite, it.pinned, (it.tags || []).join(','), it.expires_at, it.has_share].join('|');
      if (!c) {
        c = makeCard(it); c._sig = sig; cache.set(it.uuid, c);
        c.el.classList.add('enter');
        if (firstPaint) c.el.style.setProperty('--i', Math.min(idx, 8));
        if (freshIds && freshIds.has(it.uuid)) c.el.classList.add('fresh');
      } else if (c._sig !== sig) {
        const old = c.el;
        c = makeCard(it); c._sig = sig; cache.set(it.uuid, c);
        old.replaceWith(c.el);
      }
      c.it = it; c.setQuery(state.q); c.tick();
      const cur = live()[idx];
      if (cur !== c.el) list.insertBefore(c.el, cur || null);
      if (c.measure) requestAnimationFrame(c.measure);
    });
    firstPaint = false;
    updateChrome(vis.length);
  }

  function emptyView(kind) {
    const e = $('#empty'); e.replaceChildren();
    const wrap = h('div');
    wrap.innerHTML = `<svg viewBox="0 0 240 170" fill="none" stroke="var(--ink)" stroke-width="3" stroke-linejoin="round" stroke-linecap="round" aria-hidden="true">
      <g class="float-b"><rect x="20" y="40" width="96" height="84" rx="10" fill="var(--sky)" transform="rotate(-8 68 82)"/></g>
      <g class="float-a"><rect x="96" y="26" width="108" height="100" rx="12" fill="var(--sun)" transform="rotate(6 150 76)"/></g>
      <ellipse cx="120" cy="152" rx="70" ry="7" fill="var(--ink)" opacity=".12" stroke="none"/></svg>`;
    e.append(wrap.firstChild);
    if (kind === 'login') {
      e.append(h('h2', { text: '登录后查看私有内容' }), h('p', { text: '私有剪贴板只有你本人可见。' }),
        h('div', { class: 'row' }, h('button', { class: 'btn btn--accent', type: 'button', onclick: () => openAuth('login') }, '登录'),
          state.cfg.register ? h('button', { class: 'btn', type: 'button', onclick: () => openAuth('register') }, '注册') : null));
    } else if (kind === 'search') {
      e.append(h('h2', { text: '没有找到匹配项' }),
        h('div', { class: 'row' }, h('button', { class: 'btn btn--ink', type: 'button', onclick: () => { setQuery(''); setFilter('all'); setTag(''); setStarred(false); } }, '清除筛选')));
    } else {
      e.append(h('h2', { text: state.scope === 'private' ? '私有剪贴板是空的' : '这里还没有内容' }),
        h('p', { text: state.user ? '粘贴文字或截图、拖入文件即可添加。' : '访客可浏览公共内容。登录后可添加并拥有私有区。' }),
        h('div', { class: 'row' },
          state.user
            ? [h('button', { class: 'btn btn--accent', type: 'button', onclick: () => openAdd('text') }, icon('plus'), '添加文本'),
               h('button', { class: 'btn', type: 'button', onclick: () => openAdd('file') }, icon('upload'), '上传文件')]
            : [h('button', { class: 'btn btn--accent', type: 'button', onclick: () => openAuth('login') }, '登录')]));
    }
  }

  function updateChrome(visCount) {
    const c = state.counts;
    $$('[data-s]').forEach((e) => { const k = e.dataset.s; e.textContent = k === 'bytes' ? fmtSize(c.bytes) : (c[k] ?? 0); });
    $$('[data-c]').forEach((e) => { e.textContent = c[e.dataset.c] ?? 0; });
    $$('#seg [data-filter]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.filter === state.filter)));
    $$('#scope [data-scope]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.scope === state.scope)));
    $$('.tabbar [data-scope-tab]').forEach((b) => b.classList.toggle('on', b.dataset.scopeTab === state.scope));
    const logged = !!state.user;
    $$('.auth-guest').forEach((e) => { e.hidden = logged; });
    $$('.auth-user').forEach((e) => { e.hidden = !logged; });
    if (logged) {
      $('#whoName').textContent = state.user.username;
      $('#avatar').textContent = (state.user.username[0] || '?').toUpperCase();
      $('#tabAuthLabel').textContent = '我的';
      const who = document.querySelector('.who');
      if (who) { who.setAttribute('data-act', 'account'); who.setAttribute('role', 'button'); who.tabIndex = 0; }
    } else {
      $('#tabAuthLabel').textContent = '登录';
    }
    $('#warnGuest').hidden = logged;
    const sf = $('#starFilter');
    if (sf) { sf.classList.toggle('on', state.starred); sf.hidden = !logged; }
    // tags bar
    const tb = $('#tagBar');
    if (tb) {
      tb.replaceChildren();
      if (state.tags.length && logged) {
        state.tags.forEach((t) => tb.append(h('button', { type: 'button', class: 'tag' + (state.tag === t ? ' on' : ''), text: t, onclick: () => setTag(state.tag === t ? '' : t) })));
      }
    }
    let line = `可见 ${c.total} · 公共 ${c.public} · 私有 ${c.private} · ${fmtSize(c.bytes)}`;
    if (state.q || state.filter !== 'all' || state.scope !== 'all' || state.tag || state.starred) line = `显示 ${visCount} 条 · ` + line;
    line += state.user ? ` · @${state.user.username}` : ' · 访客';
    line += state.ws ? ' · 实时' : ' · 轮询';
    $('#statline').textContent = line;
    const empty = $('#empty');
    if (!state.loaded) { empty.hidden = true; return; }
    if (state.scope === 'private' && !state.user) { emptyView('login'); empty.hidden = false; return; }
    if (visCount === 0) { emptyView((state.q || state.tag || state.starred) ? 'search' : 'empty'); empty.hidden = false; }
    else empty.hidden = true;
  }

  const syncEl = $('#sync');
  function setSync(k, text) {
    syncEl.className = 'sync ' + k + (state.ws ? ' ws' : '');
    const span = $('span', syncEl);
    if (span) span.textContent = text;
  }

  async function refreshScoped(fresh) {
    if (polling) { again = new Set([...(again || []), ...(fresh || [])]); return; }
    polling = true;
    if (!state.loaded) setSync('busy', '同步中');
    try {
      let url = `/api/items?scope=${encodeURIComponent(state.scope)}`;
      if (state.starred) url += '&starred=1';
      if (state.tag) url += '&tag=' + encodeURIComponent(state.tag);
      const d = await api(url);
      state.items = d.items; state.counts = d.counts; state.tags = d.tags || []; state.loaded = true;
      render(fresh || null);
      setSync('ok', state.ws ? '实时' : '已同步');
    } catch (e) { setSync('err', '离线'); }
    finally { polling = false; if (again) { const f = again; again = null; refreshScoped(f); } }
  }

  function setFilter(f) { state.filter = f; render(); }
  function setQuery(q) { state.q = q; $('#q').value = q; render(); }
  function setTag(t) { state.tag = t; refreshScoped(); }
  function setStarred(on) { state.starred = on; refreshScoped(); }
  function setScope(s, opts = {}) {
    const same = state.scope === s;
    state.scope = s;
    if (!same || opts.force) {
      firstPaint = true; cache.clear(); list.replaceChildren(); state.loaded = false;
      list.append(h('li', { class: 'skel' }, h('div', { class: 'sk sk-a' }), h('div', { class: 'sk sk-b' })),
        h('li', { class: 'skel' }, h('div', { class: 'sk sk-a' }), h('div', { class: 'sk sk-b' })));
      updateChrome(0);
    }
    refreshScoped();
  }

  $('#q').addEventListener('input', (e) => { state.q = e.target.value.trim(); render(); });
  $('#clearQ').addEventListener('click', () => { setQuery(''); $('#q').focus(); });
  $('#seg').addEventListener('click', (e) => { const b = e.target.closest('[data-filter]'); if (b) setFilter(b.dataset.filter); });
  $('#scope').addEventListener('click', (e) => { const b = e.target.closest('[data-scope]'); if (b) setScope(b.dataset.scope); });
  $('.tabbar').addEventListener('click', (e) => {
    const b = e.target.closest('[data-scope-tab]');
    if (b) { if (state.scope === b.dataset.scopeTab) window.scrollTo({ top: 0, behavior: 'smooth' }); setScope(b.dataset.scopeTab); }
  });

  /* sheets */
  const sheetRoot = $('#sheet'), sheetEl = $('.sheet', sheetRoot), sheetBody = $('#sheetBody');
  let sheetKind = null, lastFocus = null, addView = null;

  function showSheet(kind, node) {
    const first = sheetRoot.hidden;
    sheetKind = kind;
    node.classList.add('swap');
    sheetBody.replaceChildren(node);
    if (first) {
      lastFocus = document.activeElement;
      sheetRoot.hidden = false; sheetEl.style.transform = '';
      document.documentElement.style.overflow = 'hidden';
      requestAnimationFrame(() => requestAnimationFrame(() => sheetRoot.classList.add('open')));
    }
    sheetBody.scrollTop = 0;
  }
  function closeSheet(fromPop) {
    if (sheetRoot.hidden) return;
    sheetRoot.classList.remove('open'); sheetEl.style.transform = '';
    sheetKind = null; addView = null;
    document.documentElement.style.overflow = '';
    setTimeout(() => { if (!sheetKind) { sheetRoot.hidden = true; sheetBody.replaceChildren(); } }, 380);
    if (!fromPop && ['/add_content', '/upload_file'].includes(location.pathname)) history.pushState(null, '', '/');
  }
  $('.scrim', sheetRoot).addEventListener('click', () => closeSheet());
  (() => {
    const g = $('#grab'); let y0 = null, dy = 0;
    g.addEventListener('pointerdown', (e) => { if (innerWidth >= 700) return; y0 = e.clientY; dy = 0; sheetEl.classList.add('dragging'); g.setPointerCapture(e.pointerId); });
    g.addEventListener('pointermove', (e) => { if (y0 == null) return; dy = Math.max(0, e.clientY - y0); sheetEl.style.transform = `translateY(${dy}px)`; });
    const end = () => { if (y0 == null) return; y0 = null; sheetEl.classList.remove('dragging'); if (dy > 110) closeSheet(); else sheetEl.style.transform = ''; };
    g.addEventListener('pointerup', end); g.addEventListener('pointercancel', end);
  })();

  function openAuth(mode = 'login') {
    const isReg = mode === 'register';
    if (isReg && !state.cfg.register) { toast('当前已关闭注册', 'err'); return openAuth('login'); }
    const err = h('p', { class: 'err', hidden: true, role: 'alert' });
    const go = h('button', { type: 'submit', class: 'btn btn--accent btn--block' }, isReg ? '注册并登录' : '登录');
    const form = h('form', { class: 'auth-form', onsubmit: (e) => {
      e.preventDefault();
      go.disabled = true; err.hidden = true;
      api(isReg ? '/api/register' : '/api/login', { method: 'POST', body: { username: $('#authUser', form).value.trim(), password: $('#authPw', form).value } })
        .then((d) => { state.user = d.user; toast(isReg ? '注册成功' : '登录成功'); closeSheet(); updateChrome(0); connectWS(); refreshScoped(); })
        .catch((ex) => { err.textContent = ex.message; err.hidden = false; go.disabled = false; });
    } },
      h('label', { class: 'field' }, h('span', { text: '用户名' }), h('input', { type: 'text', id: 'authUser', autocomplete: 'username', maxlength: '32', required: true })),
      h('label', { class: 'field' }, h('span', { text: '密码' }), h('input', { type: 'password', id: 'authPw', autocomplete: isReg ? 'new-password' : 'current-password', required: true })),
      err, go,
      h('button', { type: 'button', class: 'btn btn--ghost btn--block', onclick: () => openAuth(isReg ? 'login' : 'register') },
        isReg ? '已有账号？去登录' : (state.cfg.register ? '没有账号？去注册' : '当前已关闭注册')));
    showSheet('auth', h('div', {}, h('h2', { id: 'sheetTitle', text: isReg ? '注册账号' : '登录' }),
      h('p', { class: 'lead', text: isReg ? '注册后拥有私有剪贴板，也可发布到公共区。' : '登录后可添加内容、管理私有区。' }), form));
    setTimeout(() => $('#authUser', form).focus({ preventScroll: true }), 80);
  }

  function visToggle(defaultVis = 'private') {
    const wrap = h('div', { class: 'vistog', role: 'radiogroup', 'aria-label': '可见性' });
    const mk = (v, label, ico) => {
      const b = h('button', { type: 'button', class: 'vistog-btn', 'data-vis': v, 'aria-checked': String(v === defaultVis) }, icon(ico), h('span', { text: label }));
      b.addEventListener('click', () => {
        wrap.dataset.vis = v;
        $$('.vistog-btn', wrap).forEach((x) => x.setAttribute('aria-checked', String(x.dataset.vis === v)));
        // sync expiry default hint
        if (addView && addView.exp) addView.exp.setDefaultFor(v);
      });
      return b;
    };
    wrap.dataset.vis = defaultVis;
    wrap.append(mk('private', '私有', 'lock'), mk('public', '公共', 'globe'));
    return wrap;
  }

  function expiryPicker(vis) {
    const presets = [{ sec: 0, label: '不过期' }, { sec: 3600, label: '1 小时' }, { sec: 86400, label: '24 小时' }, { sec: 604800, label: '7 天' }];
    const def = vis === 'public' ? 86400 : 0;
    const wrap = h('div', { class: 'exprow', role: 'radiogroup', 'aria-label': '过期时间' });
    wrap.dataset.sec = String(def);
    const hint = h('p', { class: 'hint', text: vis === 'public' ? '公共默认 24 小时后自动删除' : '私有默认永不过期' });
    presets.forEach((p) => {
      const b = h('button', { type: 'button', 'aria-checked': String(p.sec === def), text: p.label, onclick: () => {
        wrap.dataset.sec = String(p.sec);
        $$('button', wrap).forEach((x) => x.setAttribute('aria-checked', String(x.textContent === p.label)));
      } });
      wrap.append(b);
    });
    const box = h('div', {}, h('p', { class: 'hint', text: '有效期' }), wrap, hint);
    box.setDefaultFor = (v) => {
      const sec = v === 'public' ? 86400 : 0;
      wrap.dataset.sec = String(sec);
      const label = presets.find((p) => p.sec === sec).label;
      $$('button', wrap).forEach((x) => x.setAttribute('aria-checked', String(x.textContent === label)));
      hint.textContent = v === 'public' ? '公共默认 24 小时后自动删除' : '私有默认永不过期';
    };
    box.getSec = () => parseInt(wrap.dataset.sec || '0', 10);
    return box;
  }

  function confirmSensitive(content, onPublic, onPrivate) {
    const still = h('button', { type: 'button', class: 'btn btn--danger', onclick: () => { closeSheet(); onPublic(); } }, '仍要公开');
    const priv = h('button', { type: 'button', class: 'btn btn--accent', onclick: () => { closeSheet(); onPrivate(); } }, '改为私有');
    showSheet('sens', h('div', {},
      h('div', { class: 'sens-ico' }, icon('alert')),
      h('h2', { id: 'sheetTitle', text: '检测到可能是密钥/密码' }),
      h('p', { class: 'lead', text: '内容看起来像密钥、令牌或密码。建议改为私有，避免泄露。' }),
      h('div', { class: 'preview mono', text: content.slice(0, 160) + (content.length > 160 ? '…' : '') }),
      h('div', { class: 'btn-row' }, priv, still)));
  }

  function openAdd(tab = 'text', opts = {}) {
    if (!state.user) { openAuth('login'); toast('请先登录后再添加', 'err'); return; }
    if (!opts.fromPop) {
      const r = tab === 'text' ? '/add_content' : '/upload_file';
      if (location.pathname !== r) history.pushState(null, '', r);
    }
    if (sheetKind === 'add' && addView) { addView.setTab(tab); return; }
    addView = buildAddView(tab);
    showSheet('add', addView.root);
  }

  function buildAddView(tab) {
    const title = h('h2', { id: 'sheetTitle', text: '添加到剪贴板' });
    const b1 = h('button', { type: 'button', role: 'tab' }, icon('text'), '文本');
    const b2 = h('button', { type: 'button', role: 'tab' }, icon('upload'), '文件');
    const tabs = h('div', { class: 'tabs2', role: 'tablist' }, h('i', { class: 'thumb' }), b1, b2);
    const vis = visToggle('private');
    const exp = expiryPicker('private');

    const ta = h('textarea', { class: 'ta', placeholder: '输入或粘贴文本… 也可直接 Ctrl+V 粘贴截图', 'aria-label': '文本内容', rows: 6 });
    const hint = h('span', { class: 'hint', text: '0 字 · Ctrl/⌘ + Enter 添加' });
    const addBtn = h('button', { type: 'button', class: 'btn btn--accent' }, icon('plus'), h('span', { text: '添加' }));
    ta.addEventListener('input', () => { hint.textContent = `${[...ta.value].length} 字 · Ctrl/⌘ + Enter 添加`; });

    const doAdd = async (visibility) => {
      const v = ta.value;
      if (!v.trim()) { ta.focus(); toast('请先输入内容', 'err'); return; }
      addBtn.disabled = true;
      try {
        const r = await api('/content', { method: 'POST', body: { content: v, visibility, expires_in: exp.getSec() } });
        addBtn.disabled = false; addBtn.classList.add('done');
        addBtn.replaceChildren(icon('check'), h('span', { text: '已添加' }));
        ta.value = ''; hint.textContent = '0 字 · Ctrl/⌘ + Enter 添加';
        if (visibility === 'private' && state.scope === 'public') setScope('private');
        else refreshScoped(new Set([r.uuid]));
        setTimeout(() => { addBtn.classList.remove('done'); addBtn.replaceChildren(icon('plus'), h('span', { text: '添加' })); }, 2000);
        setTimeout(() => { if (sheetKind === 'add' && !ta.value) closeSheet(); }, 900);
      } catch (e) { addBtn.disabled = false; toast(e.message, 'err'); }
    };

    const submit = () => {
      const v = ta.value;
      const visibility = vis.dataset.vis;
      if (visibility === 'public' && isSensitive(v)) {
        confirmSensitive(v, () => doAdd('public'), () => { vis.dataset.vis = 'private'; $$('.vistog-btn', vis).forEach((x) => x.setAttribute('aria-checked', String(x.dataset.vis === 'private'))); exp.setDefaultFor('private'); doAdd('private'); });
        return;
      }
      doAdd(visibility);
    };
    addBtn.addEventListener('click', submit);
    ta.addEventListener('keydown', (e) => { if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') { e.preventDefault(); submit(); } });
    const textPane = h('div', { class: 'pane' }, ta, h('div', { class: 'row-between' }, hint, addBtn));

    const input = h('input', { type: 'file', multiple: true, accept: 'image/*,*/*', tabindex: '-1' });
    const dz = h('label', { class: 'dz', tabindex: '0' }, icon('upload'), h('b', { text: '点击选择，或拖到这里' }), h('small', { text: `支持截图粘贴 · 单文件最大 ${fmtSize(state.cfg.max_upload)}` }), input);
    dz.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); input.click(); } });
    input.addEventListener('change', () => { enqueue(Array.from(input.files), false); input.value = ''; });
    ['dragenter', 'dragover'].forEach((ev) => dz.addEventListener(ev, (e) => { e.preventDefault(); dz.classList.add('over'); }));
    ['dragleave', 'drop'].forEach((ev) => dz.addEventListener(ev, () => dz.classList.remove('over')));
    dz.addEventListener('drop', (e) => { e.preventDefault(); e.stopPropagation(); enqueue(Array.from(e.dataTransfer.files), false); });
    const uplist = h('ul', { class: 'uplist' });
    const upBtn = h('button', { type: 'button', class: 'btn btn--accent btn--block', hidden: true }, icon('upload'), h('span', { text: '上传' }));
    upBtn.addEventListener('click', () => startUploads());
    const filePane = h('div', { class: 'pane' }, dz, uplist, h('div', { class: 'btn-row' }, upBtn));

    const root = h('div', {}, title, tabs, vis, exp, textPane, filePane);
    const view = { root, ta, uplist, upBtn, rows: new Map(), vis, exp };
    view.setTab = (t) => {
      tabs.dataset.on = t;
      b1.setAttribute('aria-selected', String(t === 'text')); b2.setAttribute('aria-selected', String(t === 'file'));
      textPane.hidden = t !== 'text'; filePane.hidden = t !== 'file';
      title.textContent = t === 'text' ? '添加文本' : '上传文件';
      view.tab = t; renderPill();
    };
    b1.addEventListener('click', () => openAdd('text')); b2.addEventListener('click', () => openAdd('file'));
    view.setTab(tab);
    uploads.forEach((u) => ensureRow(view, u));
    refreshUploadUI();
    return view;
  }

  /* uploads */
  const uploads = []; let uid = 0, running = false;
  const RING = 113.1;
  function ringEl() {
    const s = document.createElementNS(SVGNS, 'svg'); s.setAttribute('viewBox', '0 0 44 44'); s.setAttribute('class', 'ring');
    s.innerHTML = '<circle class="ring-bg" cx="22" cy="22" r="18"/><circle class="ring-fg" cx="22" cy="22" r="18"/>'; return s;
  }
  function ensureRow(view, u) {
    if (view.rows.has(u.id)) return view.rows.get(u.id);
    const ring = ringEl(); const rp = h('span', { class: 'rp' });
    const name = h('div', { class: 'up-name', text: u.file.name }); const sub = h('div', { class: 'up-sub' });
    const rm = h('button', { type: 'button', class: 'rm', 'aria-label': '移除', onclick: () => { if (u.xhr && u.status === 'uploading') u.xhr.abort(); removeUpload(u); } }, icon('x'));
    const li = h('li', { class: 'up' }, h('div', { class: 'ringwrap' }, ring, rp), h('div', { class: 'up-info' }, name, sub), rm);
    view.uplist.append(li);
    const row = { li, ring, rp, sub }; view.rows.set(u.id, row); return row;
  }
  function paintRow(view, u) {
    const r = ensureRow(view, u);
    r.ring.lastChild.style.strokeDashoffset = String(RING * (1 - u.pct / 100));
    r.li.className = 'up ' + u.status;
    if (u.status === 'done') { r.rp.replaceChildren(icon('check')); r.sub.textContent = '100% 上传成功'; }
    else if (u.status === 'error') { r.rp.replaceChildren(icon('alert')); r.sub.textContent = u.error || '上传失败'; }
    else if (u.status === 'uploading') { r.rp.textContent = u.pct; r.sub.textContent = `${u.pct}% 上传中 · ${fmtSize(u.file.size)}`; }
    else { r.rp.textContent = '··'; r.sub.textContent = `等待上传 · ${fmtSize(u.file.size)}`; }
  }
  function refreshUploadUI() {
    if (addView) {
      uploads.forEach((u) => paintRow(addView, u));
      addView.upBtn.hidden = !uploads.some((u) => u.status === 'pending') || running;
    }
    renderPill();
  }
  function removeUpload(u) {
    const i = uploads.indexOf(u); if (i >= 0) uploads.splice(i, 1);
    if (addView) { const r = addView.rows.get(u.id); if (r) { r.li.classList.add('gone'); setTimeout(() => r.li.remove(), 380); addView.rows.delete(u.id); } }
    refreshUploadUI();
  }
  function screenshotName(file) {
    const ext = ({ 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/gif': 'gif' })[file.type] || 'png';
    const d = new Date();
    return `screenshot-${d.getFullYear()}${pad(d.getMonth()+1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}.${ext}`;
  }
  function enqueue(files, auto) {
    if (!state.user) { openAuth('login'); toast('请先登录后再上传', 'err'); return; }
    files = files.filter(Boolean); if (!files.length) return;
    files.forEach((f) => {
      let file = f;
      if (f.type && f.type.startsWith('image/') && (!f.name || f.name === 'image.png' || f.name === 'blob')) {
        file = new File([f], screenshotName(f), { type: f.type });
      }
      const u = { id: ++uid, file, pct: 0, status: 'pending' };
      if (file.size > state.cfg.max_upload) { u.status = 'error'; u.error = `超过 ${fmtSize(state.cfg.max_upload)} 限制`; }
      uploads.push(u);
    });
    refreshUploadUI();
    if (auto) { if (!addView) openAdd('file'); startUploads(); }
  }
  async function startUploads() {
    if (running) return; running = true; refreshUploadUI();
    for (;;) {
      const u = uploads.find((x) => x.status === 'pending'); if (!u) break;
      await uploadOne(u);
    }
    running = false; refreshUploadUI(); refreshScoped();
  }
  function uploadOne(u) {
    return new Promise((resolve) => {
      const xhr = new XMLHttpRequest(); u.xhr = xhr; u.status = 'uploading'; u.pct = 0; refreshUploadUI();
      const fd = new FormData();
      fd.append('file', u.file, u.file.name);
      fd.append('visibility', (addView && addView.vis && addView.vis.dataset.vis) || 'private');
      fd.append('expires_in', String((addView && addView.exp && addView.exp.getSec()) ?? -1));
      xhr.upload.onprogress = (e) => { if (e.lengthComputable) { u.pct = Math.min(99, Math.floor((e.loaded / e.total) * 100)); refreshUploadUI(); } };
      const fail = (m) => { u.status = 'error'; u.error = m; refreshUploadUI(); toast(m, 'err'); resolve(); };
      xhr.onload = () => {
        let d = null; try { d = JSON.parse(xhr.responseText); } catch (_) {}
        if (xhr.status >= 200 && xhr.status < 300) {
          u.pct = 100; u.status = 'done'; refreshUploadUI(); toast('上传成功');
          if (d && d.visibility === 'private' && state.scope === 'public') setScope('private');
          else refreshScoped(new Set([d && d.uuid]));
          setTimeout(() => { if (uploads.includes(u)) removeUpload(u); }, 4500);
          resolve();
        } else if (xhr.status === 401) { fail('请先登录'); openAuth('login'); }
        else fail((d && (d.error || d.detail)) || `上传失败 (${xhr.status})`);
      };
      xhr.onerror = () => fail('网络错误');
      xhr.onabort = () => { u.status = 'error'; resolve(); };
      xhr.open('POST', '/upload_file'); xhr.withCredentials = true; xhr.send(fd);
    });
  }
  function renderPill() {
    const active = uploads.filter((u) => u.status === 'uploading' || u.status === 'pending');
    const pill = $('#upill');
    const viewing = sheetKind === 'add' && addView && addView.tab === 'file';
    if (!active.length || viewing) { pill.hidden = true; return; }
    const cur = active.find((u) => u.status === 'uploading') || active[0];
    pill.hidden = false;
    pill.lastChild.textContent = `上传中 ${cur.pct}%` + (active.length > 1 ? ` · 还有 ${active.length - 1} 个` : '');
    pill.firstChild.lastChild.style.strokeDashoffset = String(RING * (1 - cur.pct / 100));
  }
  $('#upill').addEventListener('click', () => openAdd('file'));

  /* share / tags / confirm */
  async function openShare(it) {
    let token = it.share_token;
    let shareExp = it.share_expires_at;
    if (!token) {
      try {
        const r = await api('/api/items/' + it.uuid + '/share', { method: 'POST', body: { hours: 24 * 7 } });
        token = r.token; shareExp = r.share_expires_at; it.share_token = token; it.has_share = true;
      } catch (e) { toast(e.message, 'err'); return; }
    }
    const url = location.origin + '/s/' + token;
    const input = h('input', { type: 'text', value: url, readonly: true, onclick: (e) => e.target.select() });
    const copyBtn = h('button', { type: 'button', class: 'btn btn--ink', onclick: async () => {
      if (await copyText(url)) { copyBtn.replaceChildren(icon('check'), h('span', { text: '已复制' })); setTimeout(() => copyBtn.replaceChildren(icon('copy'), h('span', { text: '复制' })), 2000); }
    } }, icon('copy'), h('span', { text: '复制' }));
    const qrImg = h('img', { alt: '二维码', src: '/api/share/' + encodeURIComponent(token) + '/qr' });
    const revoke = h('button', { type: 'button', class: 'btn btn--ghost btn--block', onclick: async () => {
      await api('/api/items/' + it.uuid + '/share', { method: 'DELETE' });
      it.share_token = null; it.has_share = false; toast('已撤销分享'); closeSheet(); refreshScoped();
    } }, '撤销分享链接');
    const note = h('p', { class: 'lead', text: it.visibility === 'private'
      ? '这是私有内容的临时分享链接：任何人凭链接可查看/下载，直到过期或你撤销。'
      : '公共内容分享链接，访客无需登录即可打开。' });
    const expNote = shareExp ? h('p', { class: 'hint', text: '链接有效至 ' + fmtFull(shareExp) }) : h('p', { class: 'hint', text: '链接永不过期（可随时撤销）' });
    showSheet('share', h('div', {},
      h('h2', { id: 'sheetTitle', text: '分享' }), note,
      h('div', { class: 'qr-wrap' }, qrImg),
      h('div', { class: 'share-link' }, input, copyBtn), expNote, revoke,
      h('div', { class: 'btn-row' }, h('button', { type: 'button', class: 'btn', onclick: () => closeSheet() }, '关闭'))));
  }

  function openTags(it) {
    const cur = [...(it.tags || [])];
    const input = h('input', { type: 'text', placeholder: '输入标签后回车，最多 8 个', maxlength: '32' });
    input.style.cssText = 'width:100%;height:48px;border:var(--line);border-radius:12px;padding:0 12px;background:var(--paper-2);font-size:16px';
    const listEl = h('div', { class: 'tags' });
    const redraw = () => {
      listEl.replaceChildren(...cur.map((t, i) => h('button', { type: 'button', class: 'tag on', text: t + ' ×', onclick: () => { cur.splice(i, 1); redraw(); } })));
    };
    redraw();
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        const t = input.value.trim();
        if (t && !cur.includes(t) && cur.length < 8) { cur.push(t); input.value = ''; redraw(); }
      }
    });
    const save = h('button', { type: 'button', class: 'btn btn--accent btn--block', onclick: async () => {
      try {
        const r = await api('/api/items/' + it.uuid + '/tags', { method: 'POST', body: { tags: cur } });
        it.tags = r.tags; toast('标签已保存'); closeSheet(); refreshScoped();
      } catch (e) { toast(e.message, 'err'); }
    } }, '保存');
    showSheet('tags', h('div', {}, h('h2', { id: 'sheetTitle', text: '标签' }), h('p', { class: 'lead', text: '标签仅自己可见，用于筛选自己的内容。' }), input, listEl, h('div', { class: 'btn-row', style: 'margin-top:14px' }, save)));
    setTimeout(() => input.focus(), 80);
  }

  function confirmView({ title, desc, preview, mono, okText, onOk }) {
    const ok = h('button', { type: 'button', class: 'btn btn--danger' }, icon('trash'), h('span', { text: okText }));
    ok.addEventListener('click', async () => {
      ok.disabled = true; ok.replaceChildren(h('i', { class: 'spin' }), h('span', { text: '处理中' }));
      try { await onOk(); closeSheet(); } catch (e) { ok.disabled = false; ok.replaceChildren(icon('trash'), h('span', { text: okText })); toast(e.message, 'err'); }
    });
    const cancel = h('button', { type: 'button', class: 'btn', onclick: () => closeSheet() }, '取消');
    showSheet('confirm', h('div', {}, h('div', { class: 'confirm-ico' }, icon('trash')), h('h2', { id: 'sheetTitle', text: title }), h('p', { class: 'lead', text: desc }),
      preview ? h('div', { class: 'preview' + (mono ? ' mono' : ''), text: preview }) : null, h('div', { class: 'btn-row' }, cancel, ok)));
  }
  function confirmDelete(it) {
    const isText = it.type === 'text';
    confirmView({ title: '删除这条内容？', desc: '删除后无法恢复。', preview: isText ? it.content.slice(0, 160) : it.filename, mono: isText && looksLikeCode(it.content), okText: '删除',
      onOk: async () => {
        await api('/delete', { method: 'POST', body: { uuid: it.uuid } });
        const c = cache.get(it.uuid);
        if (c) { c.el.classList.add('leaving'); setTimeout(() => c.el.remove(), 450); cache.delete(it.uuid); }
        setTimeout(() => refreshScoped(), 420); toast('已删除');
      } });
  }
  function confirmClear(scope) {
    const map = {
      private: ['private', '清空我的私有内容？', '将删除你的全部私有内容。', '清空私有'],
      public: ['public', '清空我发布的公共内容？', '其他人的内容不受影响。', '清空我的公共'],
      all: ['all', '清空我的全部内容？', '私有 + 我的公共。', '全部清空'],
    };
    const [s, title, desc, okText] = map[scope];
    confirmView({ title, desc, okText, onOk: async () => { await api('/api/clear', { method: 'POST', body: { command: 'clear', scope: s } }); await refreshScoped(); toast('已清空'); } });
  }
  function openClearMenu() {
    if (!state.user) { openAuth('login'); return; }
    const c = state.counts;
    const row = (cls, ico, t, sub, scope) => h('button', { type: 'button', class: cls === 'pk-all' ? 'danger-row' : '', onclick: () => confirmClear(scope) },
      h('span', { class: 'pk-ico ' + cls }, icon(ico)), h('span', {}, h('b', { text: t }), h('small', { text: sub })));
    showSheet('clear', h('div', {}, h('h2', { id: 'sheetTitle', text: '清空' }), h('p', { class: 'lead', text: '只会清除你自己的内容。' }),
      h('div', { class: 'pick' },
        row('pk-text', 'lock', '清空我的私有', `${c.private} 条`, 'private'),
        row('pk-file', 'globe', '清空我的公共', '你发布的公共内容', 'public'),
        row('pk-all', 'trash', '清空我的全部', '私有 + 我的公共', 'all')),
      h('div', { class: 'btn-row' }, h('button', { type: 'button', class: 'btn', onclick: () => closeSheet() }, '取消'))));
  }
  function openAccountMenu() {
    if (!state.user) { openAuth('login'); return; }
    showSheet('account', h('div', {}, h('h2', { id: 'sheetTitle', text: '@' + state.user.username }),
      h('div', { class: 'pick' },
        h('button', { type: 'button', onclick: () => { closeSheet(); setScope('private'); } }, h('span', { class: 'pk-ico pk-text' }, icon('lock')), h('span', {}, h('b', { text: '我的私有' }), h('small', { text: `${state.counts.private} 条` }))),
        h('button', { type: 'button', onclick: () => { closeSheet(); setStarred(true); } }, h('span', { class: 'pk-ico pk-file' }, icon('star')), h('span', {}, h('b', { text: '我的收藏' }), h('small', { text: `${state.counts.starred || 0} 条` }))),
        h('button', { type: 'button', onclick: () => openClearMenu() }, h('span', { class: 'pk-ico pk-file' }, icon('trash')), h('span', {}, h('b', { text: '清空内容' }), h('small', { text: '只清自己的' }))),
        h('button', { type: 'button', class: 'danger-row', onclick: async () => { await api('/api/logout', { method: 'POST' }); state.user = null; closeSheet(); toast('已退出'); updateChrome(0); setScope('public'); } },
          h('span', { class: 'pk-ico pk-all' }, icon('logout')), h('span', {}, h('b', { text: '退出登录' }), h('small', { text: '回到访客模式' })))),
      h('div', { class: 'btn-row' }, h('button', { type: 'button', class: 'btn', onclick: () => closeSheet() }, '取消'))));
  }

  /* theme */
  const THEMES = ['auto', 'light', 'dark']; const TLABEL = { auto: '跟随系统', light: '浅色', dark: '深色' };
  let theme = 'auto'; try { theme = localStorage.getItem('clip-theme') || 'auto'; } catch (_) {}
  if (!THEMES.includes(theme)) theme = 'auto';
  function applyTheme(toastIt) {
    if (theme === 'auto') document.documentElement.removeAttribute('data-theme'); else document.documentElement.setAttribute('data-theme', theme);
    try { localStorage.setItem('clip-theme', theme); } catch (_) {}
    const b = $('#themeBtn'); b.replaceChildren(icon(theme === 'auto' ? 'auto' : theme === 'light' ? 'sun' : 'moon'));
    b.title = `主题：${TLABEL[theme]}`;
    if (toastIt) toast('主题：' + TLABEL[theme]);
  }
  function cycleTheme() { theme = THEMES[(THEMES.indexOf(theme) + 1) % 3]; applyTheme(true); }

  document.addEventListener('click', (e) => {
    const t = e.target.closest('[data-act]'); if (!t) return;
    const act = t.dataset.act;
    if (act === 'home') { e.preventDefault(); closeSheet(); setQuery(''); setFilter('all'); setTag(''); setStarred(false); setScope('public'); }
    else if (act === 'add-text') { e.preventDefault(); openAdd('text'); }
    else if (act === 'add-file') { e.preventDefault(); openAdd('file'); }
    else if (act === 'clear-menu') openClearMenu();
    else if (act === 'theme') cycleTheme();
    else if (act === 'login') openAuth('login');
    else if (act === 'register') openAuth('register');
    else if (act === 'logout') { api('/api/logout', { method: 'POST' }).then(() => { state.user = null; toast('已退出'); updateChrome(0); setScope('public'); }); }
    else if (act === 'auth-or-clear' || act === 'account') { if (state.user) openAccountMenu(); else openAuth('login'); }
    else if (act === 'close-sheet') closeSheet();
    else if (act === 'star-filter') setStarred(!state.starred);
  });
  window.addEventListener('popstate', () => {
    const p = location.pathname;
    if (p === '/add_content') openAdd('text', { fromPop: true });
    else if (p === '/upload_file') openAdd('file', { fromPop: true });
    else closeSheet(true);
  });

  const typing = (el) => el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { if (!sheetRoot.hidden) closeSheet(); return; }
    if (e.ctrlKey || e.metaKey || e.altKey || typing(e.target)) return;
    if (!sheetRoot.hidden) return;
    const k = e.key.toLowerCase();
    if (k === 'n') { e.preventDefault(); openAdd('text'); }
    else if (k === 'u') { e.preventDefault(); openAdd('file'); }
    else if (k === '/') { e.preventDefault(); $('#q').focus(); }
    else if (k === 't') cycleTheme();
    else if (k === '1') setScope('public'); else if (k === '2') setScope('private'); else if (k === '3') setScope('all');
  });

  document.addEventListener('paste', async (e) => {
    if (typing(e.target) && !(sheetKind === 'add' && addView)) return;
    if (!state.user) return;
    const cd = e.clipboardData; if (!cd) return;
    const items = Array.from(cd.items || []);
    const imageItems = items.filter((i) => i.type.startsWith('image/'));
    if (imageItems.length) {
      e.preventDefault();
      const files = imageItems.map((i) => i.getAsFile()).filter(Boolean);
      enqueue(files, true);
      toast(`已粘贴 ${files.length} 张图片`);
      return;
    }
    const files = Array.from(cd.files || []);
    if (files.length) { e.preventDefault(); enqueue(files, true); return; }
    if (typing(e.target)) return;
    const text = cd.getData('text/plain');
    if (text && text.trim()) {
      e.preventDefault();
      try {
        const r = await api('/content', { method: 'POST', body: { content: text, visibility: 'private', expires_in: 0 } });
        toast('已粘贴到私有区'); if (state.scope !== 'private') setScope('private'); else refreshScoped(new Set([r.uuid]));
      } catch (err) { toast(err.message, 'err'); }
    }
  });

  let dragDepth = 0;
  const hasFiles = (e) => e.dataTransfer && Array.from(e.dataTransfer.types || []).includes('Files');
  window.addEventListener('dragenter', (e) => { if (hasFiles(e)) { dragDepth++; $('#dropveil').hidden = false; } });
  window.addEventListener('dragleave', (e) => { if (hasFiles(e) && --dragDepth <= 0) { dragDepth = 0; $('#dropveil').hidden = true; } });
  window.addEventListener('dragover', (e) => { if (hasFiles(e)) e.preventDefault(); });
  window.addEventListener('drop', (e) => {
    dragDepth = 0; $('#dropveil').hidden = true;
    if (!hasFiles(e)) return; e.preventDefault();
    enqueue(Array.from(e.dataTransfer.files), true);
  });

  /* websocket */
  let ws = null, wsRetry = 0;
  function connectWS() {
    if (ws) try { ws.close(); } catch (_) {}
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    try {
      ws = new WebSocket(proto + '//' + location.host + '/ws');
    } catch (_) { state.ws = false; startPoll(); return; }
    ws.onopen = () => { state.ws = true; wsRetry = 0; setSync('ok', '实时'); stopPoll(); };
    ws.onmessage = (ev) => {
      try {
        const msg = JSON.parse(ev.data);
        if (msg.type === 'hello') return;
        if (['create', 'delete', 'update', 'clear'].includes(msg.type)) refreshScoped();
      } catch (_) {}
    };
    ws.onclose = () => { state.ws = false; startPoll(); const delay = Math.min(15000, 1000 * Math.pow(1.5, wsRetry++)); setTimeout(connectWS, delay); };
    ws.onerror = () => { try { ws.close(); } catch (_) {} };
  }
  function startPoll() {
    if (pollTimer) return;
    pollTimer = setInterval(() => { if (!document.hidden && !state.ws) refreshScoped(); }, 4000);
  }
  function stopPoll() {
    if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
  }

  async function boot() {
    $('#brandMark').innerHTML = iconSVG('clip'); hydrateIcons(); applyTheme(false);
    $('#logoutBtn').replaceChildren(icon('logout'));
    // inject star filter + tag bar if missing
    if (!$('#starFilter')) {
      const fr = h('div', { class: 'filter-row' },
        h('button', { type: 'button', class: 'star-filter', id: 'starFilter', 'data-act': 'star-filter', hidden: true }, icon('star'), h('span', { text: '收藏' })),
        h('div', { class: 'tags', id: 'tagBar' }));
      const tb = $('.toolbar'); if (tb) tb.append(fr);
    }
    try {
      const c = await fetch('/api/config', { credentials: 'same-origin' }).then((r) => r.json());
      state.cfg = c; state.user = c.user || null;
    } catch (_) {}
    updateChrome(0);
    await refreshScoped();
    const p = location.pathname;
    if (p === '/add_content') openAdd('text', { fromPop: true });
    else if (p === '/upload_file') openAdd('file', { fromPop: true });
    connectWS();
    startPoll();
    document.addEventListener('visibilitychange', () => { if (!document.hidden) refreshScoped(); });
    window.addEventListener('focus', () => refreshScoped());
  }
  boot();
  window.__clip = { state, openAdd, openAuth, openShare, openTags, setScope, setFilter, setQuery, setTag, setStarred, refreshScoped, isSensitive, enqueue };
})();
