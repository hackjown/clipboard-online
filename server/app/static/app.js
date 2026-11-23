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
    key: '<circle cx="8" cy="15" r="4"/>' + P('M11 12l9-9M16 7l2 2M19 4l2 2'),
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
    ws: false, batch: false, selected: new Set(),
  };
  const list = $('#list');
  const cache = new Map();
  let polling = false, again = null, pollTimer = null;

  // 本设备 ID（随机 UUID，仅存本机）：随写入请求发送，用于 Bark「不推送本设备发出的内容」
  const DEVICE_ID = (() => {
    try {
      let d = localStorage.getItem('clip-device-id');
      if (!d) { d = (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2)); localStorage.setItem('clip-device-id', d); }
      return d;
    } catch (_) { return ''; }
  })();

  async function api(path, opt = {}) {
    const init = { method: opt.method || 'GET', credentials: 'same-origin', headers: { 'X-Device-Id': DEVICE_ID } };
    if (opt.body !== undefined) { init.headers['Content-Type'] = 'application/json'; init.body = JSON.stringify(opt.body); }
    const r = await fetch(path, init);
    let data = null; try { data = await r.json(); } catch (_) {}
    if (!r.ok) {
      const msg = data && (data.error || data.detail);
      // 旧版服务器缺少路由时返回裸的 "Not Found"：给出明确提示
      if (r.status === 404 && msg === 'Not Found') {
        const v = state.cfg && state.cfg.version;
        throw new Error(`服务器版本过旧（${v || '早于 0.1.8'}），请更新 Docker 镜像`);
      }
      throw new Error(msg || `请求失败 (${r.status})`);
    }
    return data;
  }

  function toast(msg, kind = 'ok', action = null) {
    const box = $('#toasts');
    while (box.children.length >= 3) box.firstChild.remove();
    const actBtn = action ? h('button', { type: 'button', class: 'toast-act', text: action.label, onclick: () => { t.remove(); action.onClick(); } }) : null;
    const t = h('div', { class: 'toast' + (kind === 'err' ? ' err' : '') }, h('span', { class: 't-ico' }, icon(kind === 'err' ? 'x' : 'check')), h('span', { text: msg }), actBtn);
    box.append(t);
    const ms = action ? 6000 : (kind === 'err' ? 3800 : 2400);
    setTimeout(() => { if (!t.isConnected) return; t.classList.add('out'); setTimeout(() => t.remove(), 320); }, ms);
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
      archive: x.preview === 'archive' ? '/api/items/' + encodeURIComponent(x.uuid) + '/archive' : undefined,
      office: x.preview === 'office' ? '/api/items/' + encodeURIComponent(x.uuid) + '/office' : undefined,
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
      icon(it.type === 'text' ? 'text' : 'file'), it.type === 'text' ? (it.encrypted ? '加密文本' : '文本') : '文件');
    const headKids = [];
    if (state.batch) {
      const ck = h('input', { type: 'checkbox', class: 'batch-ck', checked: state.selected.has(it.uuid), 'aria-label': '选择此条目' });
      ck.addEventListener('change', () => {
        if (ck.checked) state.selected.add(it.uuid); else state.selected.delete(it.uuid);
        art.classList.toggle('is-sel', ck.checked);
        renderBatchBar();
      });
      if (state.selected.has(it.uuid)) art.classList.add('is-sel');
      headKids.push(ck);
    }
    headKids.push(typeChip, visChip);
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
      const share = h('button', { type: 'button', class: 'share-btn' + (it.has_share ? ' on' : ''), title: it.has_share ? '分享（已开启）' : '分享', onclick: () => openShare(it) }, icon('share'));
      const tagb = h('button', { type: 'button', class: 'tag-btn' + ((it.tags || []).length ? ' on' : ''), title: '标签', onclick: () => openTags(it) }, icon('tag'));
      tools.append(pin, share, tagb);
    }
    if (tools.childNodes.length) art.append(tools);

    if (it.tags && it.tags.length) {
      art.append(h('div', { class: 'tags' }, ...it.tags.map((t) =>
        h('button', { type: 'button', class: 'tag' + (state.tag === t ? ' on' : ''), text: t, onclick: () => setTag(state.tag === t ? '' : t) }))));
    }

    const actions = h('div', { class: 'actions wrap' });
    if (it.mine) {
      if (it.type === 'text' && !it.encrypted) actions.append(h('button', { type: 'button', class: 'btn sm btn--edit', onclick: () => openEdit(it) }, h('span', { text: '编辑' })));
      if (it.type === 'file') actions.append(h('button', { type: 'button', class: 'btn sm btn--edit', onclick: () => openEditFile(it) }, h('span', { text: '备注/改名' })));
      actions.append(h('button', { type: 'button', class: 'btn btn--del sm', onclick: () => confirmDelete(it) }, icon('trash'), h('span', { text: '删除' })));
    }

    if (it.type === 'text' && it.encrypted) {
      let plain = null;
      const body = h('div', { class: 'e2ee-box' }, h('b', { text: '🔒 端到端加密内容' }), h('small', { text: '服务器仅保存密文，点击输入口令在本地解密' }));
      const decBtn = h('button', { type: 'button', class: 'btn btn--accent sm' }, icon('key'), h('span', { text: '解密查看' }));
      const copyDec = h('button', { type: 'button', class: 'btn btn--ink sm', hidden: true }, icon('copy'), h('span', { text: '复制明文' }));
      decBtn.onclick = async () => {
        if (plain !== null) {
          plain = null;
          body.className = 'e2ee-box';
          body.replaceChildren(h('b', { text: '🔒 端到端加密内容' }), h('small', { text: '已重新锁定' }));
          decBtn.replaceChildren(icon('key'), h('span', { text: '解密查看' }));
          copyDec.hidden = true;
          return;
        }
        const pw = prompt('请输入此条目的解密口令：');
        if (!pw) return;
        try {
          const env = JSON.parse(it.content);
          const salt = window.ClipVault.crypto.b64Decode(env.salt);
          const kh = await window.ClipVault.crypto.deriveKey(pw, salt, env.iterations || 200000);
          const dec = await window.ClipVault.crypto.decryptVault(env, kh);
          plain = (dec.items && dec.items[0] && dec.items[0].text) || '';
          body.className = 'text-body mono';
          body.textContent = plain;
          decBtn.replaceChildren(icon('lock'), h('span', { text: '重新锁定' }));
          copyDec.hidden = false;
        } catch (ex) {
          toast('解密失败：口令错误或数据损坏', 'err');
        }
      };
      copyDec.onclick = async () => { if (plain != null && await copyText(plain)) toast('明文已复制'); };
      actions.prepend(copyDec, decBtn);
      art.append(body, actions);
      card.setQuery = () => {};
      card.tick = () => { timeEl.replaceChildren(fmtTime(it.created), h('span', { class: 'sep', text: '·' }), 'E2EE'); timeEl.title = fmtFull(it.created); };
    } else if (it.type === 'text') {
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
        const orig = '/download/' + encodeURIComponent(it.filename);
        const src = it.thumb_url || orig;
        const img = h('img', { class: 'thumb', src, alt: it.filename, loading: 'lazy', onclick: () => openPreview(it),
          onerror: (e) => { if (e.target.src.indexOf('/thumb') >= 0) e.target.src = orig; } });
        art.append(img);
      }
      const fmeta = h('div', { class: 'fmeta' }, name, sub);
      if (it.note) fmeta.append(h('div', { class: 'fnote', text: it.note }));
      const row = h('div', { class: 'file-row' + (it.preview ? ' pv-able' : '') }, fileTile(it.ext), fmeta);
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
    const hay = ((it.type === 'text' ? (it.encrypted ? '' : it.content) : it.filename) + ' ' + (it.note || '') + ' ' + (it.owner_username || '') + ' ' + (it.tags || []).join(' ')).toLowerCase();
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
      const sig = [it.mine, it.favorite, it.pinned, (it.tags || []).join(','), it.expires_at, it.has_share, it.updated, it.size, it.visibility, it.note || '', it.filename || '', it.encrypted ? 1 : 0, state.batch ? 1 : 0, state.selected.has(it.uuid) ? 1 : 0].join('|');
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
    const presets = [{ sec: 3600, label: '1小时' }, { sec: 86400, label: '1天' }, { sec: 604800, label: '7天' }, { sec: 2592000, label: '30天' }, { sec: 0, label: '永不过期' }];
    const def = vis === 'public' ? 86400 : 0;
    const wrap = h('div', { class: 'exprow', role: 'radiogroup', 'aria-label': '过期时间' });
    wrap.dataset.sec = String(def);
    const hint = h('p', { class: 'hint', text: vis === 'public' ? '公共默认 1 天后自动删除，可改选' : '私有默认永不过期' });
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
      hint.textContent = v === 'public' ? '公共默认 1 天后自动删除，可改选' : '私有默认永不过期';
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
    // 默认可见性跟随当前所在的区：在「公共」里打开就默认公共（之前总是默认私有，传完还被跳到私有区，看起来像「公共区上传失败」）
    const defVis = scopeVis();
    const vis = visToggle(defVis);
    const exp = expiryPicker(defVis);

    const ta = h('textarea', { class: 'ta', placeholder: '输入或粘贴文本… 也可直接 Ctrl+V 粘贴截图', 'aria-label': '文本内容', rows: 6 });
    const e2eeCk = h('input', { type: 'checkbox' });
    const e2eePw = h('input', { type: 'password', class: 'vt-in', placeholder: '设置本条加密口令（至少 4 位，服务器仅存密文）', hidden: true, style: 'margin-top:6px' });
    e2eeCk.addEventListener('change', () => { e2eePw.hidden = !e2eeCk.checked; if (e2eeCk.checked) e2eePw.focus(); });
    const e2eeRow = h('div', { style: 'margin-top:8px' },
      h('label', { style: 'display:inline-flex;align-items:center;gap:6px;font-size:13px;font-weight:700;cursor:pointer' }, e2eeCk, h('span', { text: '🔒 口令端到端加密（服务器仅存密文）' })),
      e2eePw);
    const hint = h('span', { class: 'hint', text: '0 字 · Ctrl/⌘ + Enter 添加' });
    const addBtn = h('button', { type: 'button', class: 'btn btn--accent' }, icon('plus'), h('span', { text: '添加' }));
    ta.addEventListener('input', () => { hint.textContent = `${[...ta.value].length} 字 · Ctrl/⌘ + Enter 添加`; });

    const doAdd = async (visibility) => {
      const v = ta.value;
      if (!v.trim()) { ta.focus(); toast('请先输入内容', 'err'); return; }
      let payloadContent = v;
      let isEnc = false;
      if (e2eeCk.checked) {
        if (!window.ClipVault || !window.ClipVault.crypto) { toast('加密模块未加载', 'err'); return; }
        if (e2eePw.value.length < 4) { e2eePw.focus(); toast('加密口令至少 4 位', 'err'); return; }
        addBtn.disabled = true;
        try {
          const salt = new Uint8Array(16); crypto.getRandomValues(salt);
          const kh = await window.ClipVault.crypto.deriveKey(e2eePw.value, salt, 200000);
          const env = await window.ClipVault.crypto.encryptVault({ v: 1, items: [{ text: v }] }, kh, salt, 200000);
          payloadContent = JSON.stringify(env);
          isEnc = true;
        } catch (ex) { addBtn.disabled = false; toast('加密失败：' + ex.message, 'err'); return; }
      }
      addBtn.disabled = true;
      try {
        const r = await api('/content', { method: 'POST', body: { content: payloadContent, visibility, expires_in: exp.getSec(), encrypted: isEnc } });
        addBtn.disabled = false; addBtn.classList.add('done');
        addBtn.replaceChildren(icon('check'), h('span', { text: '已添加' }));
        ta.value = ''; e2eePw.value = ''; e2eeCk.checked = false; e2eePw.hidden = true;
        hint.textContent = '0 字 · Ctrl/⌘ + Enter 添加';
        if (visibility === 'private' && state.scope === 'public') setScope('private');
        else refreshScoped(new Set([r.uuid]));
        setTimeout(() => { addBtn.classList.remove('done'); addBtn.replaceChildren(icon('plus'), h('span', { text: '添加' })); }, 2000);
        setTimeout(() => { if (sheetKind === 'add' && !ta.value) closeSheet(); }, 900);
      } catch (e) { addBtn.disabled = false; toast(e.message, 'err'); }
    };

    const submit = () => {
      const v = ta.value;
      const visibility = vis.dataset.vis;
      if (visibility === 'public' && !e2eeCk.checked && isSensitive(v)) {
        confirmSensitive(v, () => doAdd('public'), () => { vis.dataset.vis = 'private'; $$('.vistog-btn', vis).forEach((x) => x.setAttribute('aria-checked', String(x.dataset.vis === 'private'))); exp.setDefaultFor('private'); doAdd('private'); });
        return;
      }
      doAdd(visibility);
    };
    addBtn.addEventListener('click', submit);
    ta.addEventListener('keydown', (e) => { if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') { e.preventDefault(); submit(); } });
    const textPane = h('div', { class: 'pane' }, ta, e2eeRow, h('div', { class: 'row-between' }, hint, addBtn));

    const input = h('input', { type: 'file', multiple: true, id: 'fileInput', tabindex: '-1' }); // 不设 accept：任意类型、可多选（移动端也能选非图片）
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
  function scopeVis() { return state.scope === 'public' ? 'public' : 'private'; }
  function curVis() { return (addView && addView.vis && addView.vis.dataset.vis) || scopeVis(); }
  function curExp() { return (addView && addView.exp) ? addView.exp.getSec() : -1; }
  function enqueue(files, auto) {
    if (!state.user) { openAuth('login'); toast('请先登录后再上传', 'err'); return; }
    files = files.filter(Boolean); if (!files.length) return;
    files.forEach((f) => {
      let file = f;
      if (f.type && f.type.startsWith('image/') && (!f.name || f.name === 'image.png' || f.name === 'blob')) {
        file = new File([f], screenshotName(f), { type: f.type });
      }
      const u = { id: ++uid, file, pct: 0, status: 'pending', vis: curVis(), exp: curExp() };
      if (file.size > state.cfg.max_upload) { u.status = 'error'; u.error = `超过 ${fmtSize(state.cfg.max_upload)} 限制`; }
      uploads.push(u);
    });
    refreshUploadUI();
    if (auto) { if (!addView) openAdd('file'); startUploads(); }
  }
  async function startUploads() {
    if (running) return; running = true;
    // 点「上传」那一刻的选择为准；之后关掉面板，队列里剩下的文件也不会掉回「私有」
    if (addView && addView.vis) uploads.forEach((x) => { if (x.status === 'pending') { x.vis = curVis(); x.exp = curExp(); } });
    refreshUploadUI();
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
      fd.append('visibility', u.vis === 'public' ? 'public' : 'private');
      fd.append('expires_in', String(u.exp ?? -1));
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
      xhr.open('POST', '/upload_file'); xhr.withCredentials = true; xhr.setRequestHeader('X-Device-Id', DEVICE_ID); xhr.send(fd);
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
    let hasPw = !!it.share_has_password;
    let maxViews = it.share_max_views || 0;
    if (!token) {
      try {
        const r = await api('/api/items/' + it.uuid + '/share', { method: 'POST', body: { hours: 24 * 7 } });
        token = r.token; shareExp = r.share_expires_at; hasPw = !!r.has_password; maxViews = r.max_views || 0;
        it.share_token = token; it.has_share = true;
      } catch (e) { toast(e.message, 'err'); return; }
    }
    const urlInput = h('input', { type: 'text', value: location.origin + '/s/' + token, readonly: true, onclick: (e) => e.target.select() });
    const qrImg = h('img', { alt: '二维码', src: '/api/share/' + encodeURIComponent(token) + '/qr' });
    const statusLine = h('p', { class: 'hint' });
    const syncStatus = () => {
      const bits = [shareExp ? ('有效至 ' + fmtFull(shareExp)) : '永不过期'];
      if (hasPw) bits.push('🔒 需提取码');
      if (maxViews) bits.push(`🔥 限 ${maxViews} 次` + (maxViews === 1 ? '（阅后即焚）' : ''));
      statusLine.textContent = bits.join(' · ');
    };
    syncStatus();

    const copyBtn = h('button', { type: 'button', class: 'btn btn--ink', onclick: async () => {
      if (await copyText(urlInput.value)) { copyBtn.replaceChildren(icon('check'), h('span', { text: '已复制' })); setTimeout(() => copyBtn.replaceChildren(icon('copy'), h('span', { text: '复制' })), 2000); }
    } }, icon('copy'), h('span', { text: '复制' }));

    const pwInput = h('input', { type: 'text', class: 'vt-in', placeholder: '可选提取码（留空=免密）', maxlength: '32' });
    const mvSel = h('select', { class: 'vt-in' },
      ...[ [0, '访问次数：不限'], [1, '🔥 1 次（阅后即焚）'], [3, '限 3 次'], [5, '限 5 次'], [10, '限 10 次'] ]
        .map(([v, t]) => h('option', { value: String(v), selected: v === maxViews ? 'selected' : false, text: t })));
    const regenBtn = h('button', { type: 'button', class: 'btn sm', onclick: async () => {
      regenBtn.disabled = true;
      try {
        const r = await api('/api/items/' + it.uuid + '/share', {
          method: 'POST',
          body: { hours: 24 * 7, password: pwInput.value.trim(), max_views: parseInt(mvSel.value, 10) || 0 },
        });
        token = r.token; shareExp = r.share_expires_at; hasPw = !!r.has_password; maxViews = r.max_views || 0;
        it.share_token = token; it.has_share = true; it.share_has_password = hasPw; it.share_max_views = maxViews || null;
        urlInput.value = location.origin + '/s/' + token;
        qrImg.src = '/api/share/' + encodeURIComponent(token) + '/qr?t=' + Date.now();
        syncStatus();
        toast('已应用安全设置并更新链接');
        refreshScoped();
      } catch (e) { toast(e.message, 'err'); }
      finally { regenBtn.disabled = false; }
    } }, '更新安全设置');

    const revoke = h('button', { type: 'button', class: 'btn btn--ghost btn--block', onclick: async () => {
      await api('/api/items/' + it.uuid + '/share', { method: 'DELETE' });
      it.share_token = null; it.has_share = false; toast('已撤销分享'); closeSheet(); refreshScoped();
    } }, '撤销分享链接');
    const note = h('p', { class: 'lead', text: it.visibility === 'private'
      ? '私有内容临时分享链接：可附加提取码或设为「阅后即焚」。'
      : '公共内容分享链接，访客无需登录即可打开。' });
    showSheet('share', h('div', {},
      h('h2', { id: 'sheetTitle', text: '分享' }), note,
      h('div', { class: 'qr-wrap' }, qrImg),
      h('div', { class: 'share-link' }, urlInput, copyBtn), statusLine,
      h('div', { class: 'share-opts' }, pwInput, mvSel, regenBtn),
      revoke,
      h('div', { class: 'btn-row' }, h('button', { type: 'button', class: 'btn', onclick: () => closeSheet() }, '关闭'))));
  }

  function openEditFile(it) {
    const fnIn = h('input', { type: 'text', class: 'vt-in', value: it.filename || '', placeholder: '文件名' });
    const noteIn = h('textarea', { class: 'ta', rows: 4, placeholder: '添加文件备注（支持搜索）' });
    noteIn.value = it.note || '';
    const err = h('p', { class: 'err', hidden: true });
    const save = h('button', { type: 'button', class: 'btn btn--accent' }, icon('check'), h('span', { text: '保存' }));
    save.onclick = async () => {
      const fn = fnIn.value.trim();
      if (!fn) { err.textContent = '文件名不能为空'; err.hidden = false; return; }
      save.disabled = true; err.hidden = true;
      try {
        await api('/api/items/' + it.uuid, { method: 'PATCH', body: { filename: fn, note: noteIn.value.trim() } });
        toast('已更新'); closeSheet(); refreshScoped();
      } catch (e) { err.textContent = e.message; err.hidden = false; save.disabled = false; }
    };
    showSheet('edit-file', h('div', {},
      h('h2', { id: 'sheetTitle', text: '文件重命名与备注' }),
      h('label', { class: 'field' }, h('span', { text: '文件名' }), fnIn),
      h('label', { class: 'field', style: 'margin-top:10px' }, h('span', { text: '备注' }), noteIn),
      err,
      h('div', { class: 'btn-row', style: 'margin-top:14px' }, h('button', { type: 'button', class: 'btn', onclick: () => closeSheet() }, '取消'), save)));
    setTimeout(() => fnIn.focus(), 80);
  }

  function openEdit(it) {
    const ta = h('textarea', { class: 'edit-ta', rows: '8', maxlength: String(state.cfg.max_text || 1048576), 'aria-label': '编辑文本' });
    ta.value = it.content || '';
    ta.style.cssText = 'width:100%;min-height:180px;border:var(--line);border-radius:12px;padding:12px;background:var(--paper-2);font-size:16px;line-height:1.5;resize:vertical;color:var(--ink)';
    const err = h('p', { class: 'form-err', hidden: true });
    const save = h('button', { type: 'button', class: 'btn btn--accent' }, icon('check'), h('span', { text: '保存' }));
    const cancel = h('button', { type: 'button', class: 'btn', onclick: () => closeSheet() }, '取消');
    const doSave = async (force) => {
      const v = ta.value;
      if (!v.trim()) { err.textContent = '内容不能为空'; err.hidden = false; return; }
      if (v === it.content) { closeSheet(); return; }
      if (!force && it.visibility === 'public' && isSensitive(v)) {
        confirmSensitive(v, () => doSave(true), async () => {
          try { await api('/api/items/' + it.uuid, { method: 'PATCH', body: { content: v, visibility: 'private' } }); toast('已保存并改为私有'); refreshScoped(); } catch (e) { toast(e.message, 'err'); }
        });
        return;
      }
      save.disabled = true; err.hidden = true;
      try {
        await api('/api/items/' + it.uuid, { method: 'PATCH', body: { content: v } });
        toast('已保存'); closeSheet(); refreshScoped();
      } catch (e) { err.textContent = e.message; err.hidden = false; save.disabled = false; }
    };
    save.addEventListener('click', () => doSave(false));
    ta.addEventListener('keydown', (e) => { if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') { e.preventDefault(); doSave(false); } });
    showSheet('edit', h('div', {}, h('h2', { id: 'sheetTitle', text: '编辑文本' }),
      h('p', { class: 'lead', text: '保存后同步到所有设备，分享链接保持不变。Ctrl/⌘ + Enter 保存。' }),
      ta, err, h('div', { class: 'btn-row', style: 'margin-top:14px' }, cancel, save)));
    setTimeout(() => { ta.focus(); ta.setSelectionRange(ta.value.length, ta.value.length); }, 80);
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
    confirmView({ title: '移入回收站？', desc: '条目将在回收站保留 7 天，可随时撤销恢复。', preview: isText ? (it.encrypted ? '🔒 端到端加密内容' : it.content.slice(0, 160)) : it.filename, mono: isText && !it.encrypted && looksLikeCode(it.content), okText: '删除',
      onOk: async () => {
        await api('/delete', { method: 'POST', body: { uuid: it.uuid } });
        const c = cache.get(it.uuid);
        if (c) { c.el.classList.add('leaving'); setTimeout(() => c.el.remove(), 450); cache.delete(it.uuid); }
        setTimeout(() => refreshScoped(), 420);
        toast('已移入回收站', 'ok', {
          label: '撤销',
          onClick: async () => {
            try { await api('/api/trash/' + encodeURIComponent(it.uuid) + '/restore', { method: 'POST' }); toast('已恢复'); refreshScoped(); }
            catch (e) { toast(e.message, 'err'); }
          },
        });
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
  // ---- 多设备剪贴板同步（设计参考 lanecho，MIT；独立实现）----
  const DIR_LABEL = { both: '双向', send: '只发送', recv: '只接收', off: '关闭' };
  const PLAT_LABEL = { macos: 'Mac', ios: 'iPhone/iPad', android: 'Android', web: '网页', windows: 'Windows', linux: 'Linux' };
  let clipView = null;
  function openClipSync() {
    const list = h('ul', { class: 'devlist' });
    const instLine = h('p', { class: 'hint', text: '' });
    const latestBox = h('div', { class: 'preview mono', text: '加载中…' });
    const latestImg = h('img', { class: 'thumb', hidden: true, alt: '同步图片', style: 'max-height:180px;cursor:default' });
    const latestMeta = h('p', { class: 'hint', text: '' });
    let latestText = '';
    const copyBtn = h('button', { type: 'button', class: 'btn sm', onclick: async () => {
      if (!latestText) return;
      try { await navigator.clipboard.writeText(latestText); toast('已复制到本机剪贴板'); } catch (_) { toast('浏览器不允许写剪贴板，请手动复制', 'err'); }
    } }, icon('copy'), h('span', { text: '复制到本机' }));
    const ta = h('textarea', { class: 'ta', rows: 3, placeholder: '输入文本，发送到我所有开启了同步的设备的剪贴板' });
    const imgIn = h('input', { type: 'file', accept: 'image/*', hidden: true });
    imgIn.onchange = async () => {
      const f = imgIn.files && imgIn.files[0]; if (!f) return;
      imgIn.value = '';
      if (f.size > 4 * 1024 * 1024) { toast('同步图片不能超过 4 MB', 'err'); return; }
      const b64 = await new Promise((res, rej) => { const fr = new FileReader(); fr.onload = () => res(String(fr.result).split(',')[1] || ''); fr.onerror = rej; fr.readAsDataURL(f); });
      try {
        await api('/api/devices/' + encodeURIComponent(DEVICE_ID), { method: 'PUT', body: { name: '网页浏览器', platform: 'web', direction: 'send' } }).catch(() => {});
        const r = await api('/api/clipsync', { method: 'POST', body: { kind: 'image', image_b64: b64 } });
        toast(r.duplicate ? '图片与当前同步剪贴板相同' : '图片已同步到你的其他设备'); load();
      } catch (e) { toast(e.message, 'err'); }
    };
    const imgBtn = h('button', { type: 'button', class: 'btn', onclick: () => imgIn.click() }, icon('upload'), h('span', { text: '发送图片' }));
    const send = async (text) => {
      if (!text || !text.trim()) { toast('内容为空', 'err'); return; }
      try {
        await api('/api/devices/' + encodeURIComponent(DEVICE_ID), { method: 'PUT', body: { name: '网页浏览器', platform: 'web', direction: 'send' } }).catch(() => {});
        const r = await api('/api/clipsync', { method: 'POST', body: { text, save_history: false } });
        toast(r.duplicate ? '内容与当前同步剪贴板相同' : '已同步到你的其他设备'); ta.value = ''; load();
      } catch (e) { toast(e.message, 'err'); }
    };
    const sendBtn = h('button', { type: 'button', class: 'btn btn--accent', onclick: () => send(ta.value) }, icon('upload'), h('span', { text: '发送文本' }));
    const readBtn = h('button', { type: 'button', class: 'btn', onclick: async () => {
      try { send(await navigator.clipboard.readText()); } catch (_) { toast('浏览器不允许读取剪贴板，请粘贴到输入框', 'err'); }
    } }, icon('copy'), h('span', { text: '读剪贴板发送' }));
    async function load() {
      try {
        const [d, c] = await Promise.all([api('/api/devices'), api('/api/clipsync')]);
        list.replaceChildren(...(d.devices.length ? d.devices.map((x) => h('li', { class: 'dev' },
          h('span', { class: 'dot ' + (x.online ? 'on' : 'off'), title: x.online ? '在线' : '离线' }),
          h('span', { class: 'dev-main' }, h('b', { text: x.name + (x.current ? '（本机）' : '') }),
            h('small', { text: `${PLAT_LABEL[x.platform] || x.platform || '未知'} · ${DIR_LABEL[x.direction] || x.direction} · ${x.online ? '在线' : '离线' + (x.last_seen ? '（上次在线 ' + fmtTime(x.last_seen) + '）' : '') + (x.platform === 'ios' || x.platform === 'android' ? ' · 手机只在打开 App 时在线' : '')}` })),
          h('button', { type: 'button', class: 'btn sm btn--ghost', onclick: async () => {
            if (!confirm(`移除设备「${x.name}」？它下次开启同步时会重新出现。`)) return;
            try { await api('/api/devices/' + encodeURIComponent(x.device_id), { method: 'DELETE' }); load(); } catch (e) { toast(e.message, 'err'); }
          } }, '移除'))) : [h('li', { class: 'hint', text: '还没有设备开启同步。在 Mac / iPhone / Android 客户端的「设置 → 多设备剪贴板同步」里打开。' })]));
        instLine.textContent = `账号 ${d.user || '—'} · 服务器实例 ${d.instance || '—'} · 实时连接 ${state.ws ? '已连接' : '未连接'}（各设备的账号与实例须一致）`;
        const isImg = c.clip && c.clip.kind === 'image';
        latestImg.hidden = !isImg;
        latestBox.hidden = !!isImg;
        if (isImg) {
          latestImg.src = '/api/clipsync/image?t=' + encodeURIComponent(String(c.clip.ts || Date.now()));
          latestText = '';
          copyBtn.disabled = true;
        } else {
          latestText = (c.clip && c.clip.text) || '';
          latestBox.textContent = latestText ? latestText.slice(0, 400) + (latestText.length > 400 ? '…' : '') : '（还没有同步过内容）';
          copyBtn.disabled = !latestText;
        }
        latestMeta.textContent = c.clip ? `来自「${c.clip.origin_name}」 · ${fmtTime(c.clip.ts)}` + (isImg ? ` · 图片 ${fmtSize(c.clip.size)}` : '') : '';
      } catch (e) { latestBox.textContent = e.message; }
    }
    clipView = { load };
    showSheet('clipsync', h('div', {}, h('h2', { id: 'sheetTitle', text: '多设备剪贴板同步' }),
      h('p', { class: 'lead', text: '支持文本与图片跨设备实时同步。浏览器可手动发送文本或图片到你的其他设备。' }),
      h('p', { class: 'hint', text: '当前同步剪贴板' }), latestImg, latestBox, h('div', { class: 'row-between' }, latestMeta, copyBtn),
      h('p', { class: 'hint', text: '我的设备' }), instLine, list,
      h('p', { class: 'hint', text: '发送' }), ta, imgIn, h('div', { class: 'btn-row' }, readBtn, imgBtn, sendBtn)));
    load();
  }

  function openBarkSettings() {
    const err = h('p', { class: 'err', hidden: true, role: 'alert' });
    const input = h('input', { type: 'url', id: 'barkUrl', placeholder: 'https://api.day.app/你的Key', autocomplete: 'off', spellcheck: 'false', maxlength: '512' });
    const skip = h('input', { type: 'checkbox', id: 'barkSkip' });
    const inapp = h('input', { type: 'checkbox', id: 'barkInApp', checked: true });
    const test = h('button', { type: 'button', class: 'btn' }, '测试');
    const save = h('button', { type: 'submit', class: 'btn btn--accent' }, '保存');
    const show = (m) => { err.textContent = m; err.hidden = !m; };
    const body = () => ({ bark_url: input.value.trim(), bark_exclude_device: skip.checked ? DEVICE_ID : '', open_in_app: inapp.checked });
    test.addEventListener('click', () => {
      show(''); test.disabled = true;
      api('/api/settings/bark/test', { method: 'POST', body: { bark_url: input.value.trim(), open_in_app: inapp.checked } })
        .then(() => toast('测试推送已发送，请查看手机')).catch((e) => show(e.message)).finally(() => { test.disabled = false; });
    });
    const form = h('form', { class: 'auth-form', onsubmit: (e) => {
      e.preventDefault(); show(''); save.disabled = true;
      api('/api/settings/bark', { method: 'PUT', body: body() })
        .then((d) => { toast(d.configured ? 'Bark 已保存' : 'Bark 已关闭'); closeSheet(); })
        .catch((ex) => show(ex.message)).finally(() => { save.disabled = false; });
    } },
      h('label', { class: 'field' }, h('span', { text: 'Bark 推送地址' }), input),
      h('label', { class: 'field', style: 'display:flex;gap:8px;align-items:center' }, skip, h('span', { text: '不推送本设备发出的内容' })),
      h('label', { class: 'field', style: 'display:flex;gap:8px;align-items:center' }, inapp, h('span', { text: '点击推送打开 App（clipboard:// 深链；关闭则打开网站链接）' })),
      err, h('div', { class: 'btn-row' }, test, save));
    showSheet('bark', h('div', {}, h('h2', { id: 'sheetTitle', text: 'Bark 推送' }),
      h('p', { class: 'lead', text: '在 iPhone 安装 Bark，复制其中的设备地址粘贴到这里。你的私有区有新内容时会推送（留空并保存即关闭）。' }), form));
    api('/api/settings/bark').then((d) => { input.value = d.bark_url || ''; skip.checked = !!d.bark_exclude_device && d.bark_exclude_device === DEVICE_ID; inapp.checked = d.open_in_app !== false; }).catch(() => {});
  }

  // 主题：跟随系统 / 浅色 / 深色（直接选择，不只是循环切换）
  function themePicker() {
    const wrap = h('div', { class: 'theme-pick', role: 'radiogroup', 'aria-label': '主题', style: 'display:flex;gap:8px;align-items:center;margin:12px 0' },
      h('span', { text: '主题', style: 'font-weight:700;margin-right:4px' }));
    THEMES.forEach((v) => {
      const b = h('button', { type: 'button', class: 'btn sm', role: 'radio', 'data-theme-opt': v, 'aria-checked': String(theme === v) }, TLABEL[v]);
      b.addEventListener('click', () => { theme = v; applyTheme(true); $$('[data-theme-opt]', wrap).forEach((x) => { const on = x.dataset.themeOpt === v; x.setAttribute('aria-checked', String(on)); x.classList.toggle('btn--ink', on); }); });
      if (theme === v) b.classList.add('btn--ink');
      wrap.append(b);
    });
    return wrap;
  }

  function openVault() {
    if (!state.user) { openAuth('login'); return; }
    closeSheet();
    if (window.ClipVault) window.ClipVault.open({ toast });
  }

  // ---- 批量多选模式 & 浮动操作条 ----
  let batchBarEl = null;
  function toggleBatchMode(force) {
    state.batch = force !== undefined ? !!force : !state.batch;
    if (!state.batch) state.selected.clear();
    const btn = $('#batchToggle');
    if (btn) btn.classList.toggle('on', state.batch);
    render();
    renderBatchBar();
  }
  function renderBatchBar() {
    if (!state.batch) { if (batchBarEl) { batchBarEl.remove(); batchBarEl = null; } return; }
    if (!batchBarEl) {
      batchBarEl = h('div', { class: 'batch-bar', role: 'toolbar' });
      document.body.append(batchBarEl);
    }
    const ids = Array.from(state.selected);
    const n = ids.length;
    const doZip = async () => {
      if (!n) return;
      try {
        const r = await fetch('/api/items/zip', {
          method: 'POST', credentials: 'same-origin',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ uuids: ids }),
        });
        if (!r.ok) { const d = await r.json().catch(() => ({})); throw new Error(d.error || d.detail || '打包失败'); }
        const blob = await r.blob();
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = `clipboard-batch-${new Date().toISOString().slice(0, 10)}.zip`;
        a.click();
        setTimeout(() => URL.revokeObjectURL(a.href), 3000);
        toast(`已打包下载 ${n} 项`);
      } catch (e) { toast(e.message, 'err'); }
    };
    const doBatchTag = async () => {
      if (!n) return;
      const raw = prompt('为选中的条目追加标签（多个用逗号分隔）：');
      if (!raw || !raw.trim()) return;
      const tags = raw.split(/[,，]/).map((x) => x.trim()).filter(Boolean);
      try {
        const r = await api('/api/items/batch', { method: 'POST', body: { action: 'tag', uuids: ids, tags } });
        toast(`已为 ${r.affected} 项添加标签`); toggleBatchMode(false); refreshScoped();
      } catch (e) { toast(e.message, 'err'); }
    };
    const doBatchVis = async (visibility) => {
      if (!n) return;
      try {
        const r = await api('/api/items/batch', { method: 'POST', body: { action: 'visibility', uuids: ids, visibility } });
        toast(`已修改 ${r.affected} 项为${visibility === 'private' ? '私有' : '公共'}`); toggleBatchMode(false); refreshScoped();
      } catch (e) { toast(e.message, 'err'); }
    };
    const doBatchDel = async () => {
      if (!n || !confirm(`将选中的 ${n} 条自己的内容移入回收站？`)) return;
      try {
        const r = await api('/api/items/batch', { method: 'POST', body: { action: 'delete', uuids: ids } });
        toast(`已将 ${r.affected} 项移入回收站`); toggleBatchMode(false); refreshScoped();
      } catch (e) { toast(e.message, 'err'); }
    };
    const selAll = () => {
      const vis = state.items.filter(matches);
      if (state.selected.size >= vis.length) state.selected.clear();
      else vis.forEach((x) => state.selected.add(x.uuid));
      render(); renderBatchBar();
    };
    batchBarEl.replaceChildren(
      h('span', { class: 'batch-cnt', text: `已选 ${n} 项` }),
      h('button', { type: 'button', class: 'btn sm', onclick: selAll }, '全选'),
      h('button', { type: 'button', class: 'btn sm btn--ink', disabled: !n, onclick: doZip }, '打包 ZIP'),
      state.user ? h('button', { type: 'button', class: 'btn sm', disabled: !n, onclick: doBatchTag }, '加标签') : null,
      state.user ? h('button', { type: 'button', class: 'btn sm', disabled: !n, onclick: () => doBatchVis('private') }, '设私有') : null,
      state.user ? h('button', { type: 'button', class: 'btn sm btn--danger', disabled: !n, onclick: doBatchDel }, '删除') : null,
      h('button', { type: 'button', class: 'btn sm btn--ghost', onclick: () => toggleBatchMode(false) }, '完成')
    );
  }

  // ---- 回收站 ----
  function openTrash() {
    const listBox = h('div', { class: 'pick' }, h('p', { class: 'hint', text: '加载中…' }));
    const emptyBtn = h('button', { type: 'button', class: 'btn btn--danger', onclick: async () => {
      if (!confirm('确认彻底清空回收站？所有已删条目与文件将永久删除且无法恢复。')) return;
      try { const r = await api('/api/trash/empty', { method: 'POST' }); toast(`已永久清除 ${r.removed} 项`); load(); }
      catch (e) { toast(e.message, 'err'); }
    } }, '清空回收站');
    async function load() {
      try {
        const d = await api('/api/trash');
        if (!d.items.length) { listBox.replaceChildren(h('p', { class: 'hint', text: '回收站是空的（删除的条目会在此保留 7 天）。' })); emptyBtn.disabled = true; return; }
        emptyBtn.disabled = false;
        listBox.replaceChildren(...d.items.map((it) => {
          const title = it.type === 'text' ? (it.encrypted ? '🔒 加密文本' : (it.content || '').slice(0, 60)) : (it.filename || '文件');
          return h('div', { class: 'dev' },
            h('span', { class: 'dev-main' }, h('b', { text: title }), h('small', { text: `${it.type === 'text' ? '文本' : fmtSize(it.size)} · 删除于 ${fmtTime(it.deleted_at)}` })),
            h('button', { type: 'button', class: 'btn sm btn--accent', onclick: async () => {
              try { await api('/api/trash/' + encodeURIComponent(it.uuid) + '/restore', { method: 'POST' }); toast('已恢复'); load(); refreshScoped(); }
              catch (e) { toast(e.message, 'err'); }
            } }, '恢复'),
            h('button', { type: 'button', class: 'btn sm btn--ghost', onclick: async () => {
              try { await api('/delete', { method: 'POST', body: { uuid: it.uuid, permanent: true } }); toast('已永久删除'); load(); }
              catch (e) { toast(e.message, 'err'); }
            } }, '彻底删'));
        }));
      } catch (e) { listBox.replaceChildren(h('p', { class: 'err', text: e.message })); }
    }
    showSheet('trash', h('div', {},
      h('h2', { id: 'sheetTitle', text: '回收站' }),
      h('p', { class: 'lead', text: '删除的条目保留 7 天，可一键恢复或彻底清除。' }),
      listBox,
      h('div', { class: 'btn-row' }, emptyBtn, h('button', { type: 'button', class: 'btn', onclick: () => closeSheet() }, '关闭'))));
    load();
  }

  // ---- 扫码快速配对登录客户端 ----
  async function openPairModal() {
    try {
      const r = await api('/api/pair/create', { method: 'POST' });
      const qr = h('img', { alt: '配对登录二维码', src: r.qr_url });
      const uriIn = h('input', { type: 'text', value: r.uri, readonly: true, onclick: (e) => e.target.select() });
      const cp = h('button', { type: 'button', class: 'btn btn--ink', onclick: async () => { if (await copyText(r.uri)) toast('配对链接已复制'); } }, icon('copy'), h('span', { text: '复制' }));
      let left = r.expires_in || 120;
      const cd = h('p', { class: 'hint', text: `一次性配对码，${left} 秒后失效（切勿截图发给他人）` });
      const iv = setInterval(() => {
        if (!cd.isConnected) { clearInterval(iv); return; }
        left--;
        cd.textContent = left > 0 ? `一次性配对码，${left} 秒后失效（切勿截图发给他人）` : '配对码已过期，请关闭后重新生成';
        if (left <= 0) clearInterval(iv);
      }, 1000);
      showSheet('pair', h('div', {},
        h('h2', { id: 'sheetTitle', text: '扫码配对客户端' }),
        h('p', { class: 'lead', text: '用手机相机扫下方二维码即可自动打开 App 并登录当前账号；Mac 客户端也可在登录页点击「粘贴配对码」。' }),
        h('div', { class: 'qr-wrap' }, qr),
        h('div', { class: 'share-link' }, uriIn, cp),
        cd,
        h('div', { class: 'btn-row' }, h('button', { type: 'button', class: 'btn', onclick: () => closeSheet() }, '关闭'))));
    } catch (e) { toast(e.message, 'err'); }
  }

  // ---- 空间统计 & 一键个人备份 ----
  function openAccountStats() {
    const box = h('div', { class: 'stats', style: 'margin:12px 0' }, h('div', {}, h('dt', { text: '加载中' }), h('dd', { text: '…' })));
    const dl = h('a', { class: 'btn btn--accent btn--block', href: '/api/account/export', download: '' }, icon('download'), h('span', { text: '下载个人完整备份 ZIP' }));
    showSheet('stats', h('div', {},
      h('h2', { id: 'sheetTitle', text: '空间用量与个人备份' }),
      h('p', { class: 'lead', text: '备份 ZIP 包含你的全部文本（items.json）、全部文件及已加密的密码库信封（vault_encrypted.json）。' }),
      box, dl,
      h('div', { class: 'btn-row' }, h('button', { type: 'button', class: 'btn', onclick: () => closeSheet() }, '关闭'))));
    api('/api/account/stats').then((s) => {
      box.replaceChildren(
        h('div', {}, h('dt', { text: '有效条目' }), h('dd', { text: `${s.total_items} 条` })),
        h('div', {}, h('dt', { text: '已用空间' }), h('dd', { text: fmtSize(s.total_bytes) })),
        h('div', {}, h('dt', { text: '回收站' }), h('dd', { text: `${s.trash_items} 条 · ${fmtSize(s.trash_bytes)}` })),
        h('div', {}, h('dt', { text: '密码库' }), h('dd', { text: s.vault_exists ? `${s.vault_items} 条` : '未创建' })),
      );
    }).catch((e) => { box.replaceChildren(h('p', { class: 'err', text: e.message })); });
  }

  function openAccountMenu() {
    if (!state.user) { openAuth('login'); return; }
    showSheet('account', h('div', {}, h('h2', { id: 'sheetTitle', text: '@' + state.user.username }),
      h('div', { class: 'pick' },
        h('button', { type: 'button', onclick: () => openVault() }, h('span', { class: 'pk-ico pk-text' }, icon('key')), h('span', {}, h('b', { text: '密码库（E2EE）' }), h('small', { text: '账号密码 · 2FA 验证码 · 端到端加密' }))),
        h('button', { type: 'button', onclick: () => openPairModal() }, h('span', { class: 'pk-ico pk-file' }, icon('share')), h('span', {}, h('b', { text: '扫码配对客户端' }), h('small', { text: '手机扫码免输地址和密码登录' }))),
        h('button', { type: 'button', onclick: () => { closeSheet(); setScope('private'); } }, h('span', { class: 'pk-ico pk-text' }, icon('lock')), h('span', {}, h('b', { text: '我的私有' }), h('small', { text: `${state.counts.private} 条` }))),
        h('button', { type: 'button', onclick: () => { closeSheet(); setStarred(true); } }, h('span', { class: 'pk-ico pk-file' }, icon('star')), h('span', {}, h('b', { text: '我的收藏' }), h('small', { text: `${state.counts.starred || 0} 条` }))),
        h('button', { type: 'button', onclick: () => openTrash() }, h('span', { class: 'pk-ico pk-file' }, icon('trash')), h('span', {}, h('b', { text: '回收站' }), h('small', { text: '7 天内误删内容可恢复' }))),
        h('button', { type: 'button', onclick: () => openAccountStats() }, h('span', { class: 'pk-ico pk-text' }, icon('download')), h('span', {}, h('b', { text: '空间统计与一键备份' }), h('small', { text: '查看占用 · 导出全部数据 ZIP' }))),
        h('button', { type: 'button', onclick: () => openClipSync() }, h('span', { class: 'pk-ico pk-text' }, icon('copy')), h('span', {}, h('b', { text: '多设备剪贴板同步' }), h('small', { text: '文本与图片 · 设备列表' }))),
        h('button', { type: 'button', onclick: () => openBarkSettings() }, h('span', { class: 'pk-ico pk-text' }, icon('check')), h('span', {}, h('b', { text: 'Bark 推送' }), h('small', { text: '新私有内容推送到 iPhone' }))),
        h('button', { type: 'button', onclick: () => openClearMenu() }, h('span', { class: 'pk-ico pk-file' }, icon('trash')), h('span', {}, h('b', { text: '清空内容' }), h('small', { text: '只清自己的' }))),
        h('button', { type: 'button', class: 'danger-row', onclick: async () => { await api('/api/logout', { method: 'POST' }); state.user = null; closeSheet(); toast('已退出'); updateChrome(0); setScope('public'); } },
          h('span', { class: 'pk-ico pk-all' }, icon('logout')), h('span', {}, h('b', { text: '退出登录' }), h('small', { text: '回到访客模式' })))),
      themePicker(),
      h('p', { class: 'hint', style: 'margin:6px 0 10px', text: `服务器版本 ${(state.cfg && state.cfg.version) || '未知（早于 0.1.8）'} · 网页 0.1.17` }),
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
    else if (act === 'vault') { e.preventDefault(); openVault(); }
    else if (act === 'clear-menu') openClearMenu();
    else if (act === 'theme') cycleTheme();
    else if (act === 'login') openAuth('login');
    else if (act === 'register') openAuth('register');
    else if (act === 'logout') { api('/api/logout', { method: 'POST' }).then(() => { state.user = null; toast('已退出'); updateChrome(0); setScope('public'); }); }
    else if (act === 'auth-or-clear' || act === 'account') { if (state.user) openAccountMenu(); else openAuth('login'); }
    else if (act === 'close-sheet') closeSheet();
    else if (act === 'star-filter') setStarred(!state.starred);
    else if (act === 'batch-toggle') toggleBatchMode();
  });
  window.addEventListener('popstate', () => {
    const p = location.pathname;
    if (p === '/add_content') openAdd('text', { fromPop: true });
    else if (p === '/upload_file') openAdd('file', { fromPop: true });
    else closeSheet(true);
  });

  const typing = (el) => el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);
  document.addEventListener('keydown', (e) => {
    if (document.body.classList.contains('pv-open')) return;
    if (e.key === 'Escape') { if (!sheetRoot.hidden) closeSheet(); return; }
    if (e.ctrlKey || e.metaKey || e.altKey || typing(e.target)) return;
    if (!sheetRoot.hidden) return;
    const k = e.key.toLowerCase();
    if (k === 'n') { e.preventDefault(); openAdd('text'); }
    else if (k === 'u') { e.preventDefault(); openAdd('file'); }
    else if (k === 'v') { e.preventDefault(); openVault(); }
    else if (k === '/') { e.preventDefault(); $('#q').focus(); }
    else if (k === 't') cycleTheme();
    else if (k === '1') setScope('public'); else if (k === '2') setScope('private'); else if (k === '3') setScope('all');
  });

  document.addEventListener('paste', async (e) => {
    if (document.body.classList.contains('pv-open')) return;
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
      ws = new WebSocket(proto + '//' + location.host + '/ws' + (DEVICE_ID ? '?device=' + encodeURIComponent(DEVICE_ID) : ''));
    } catch (_) { state.ws = false; startPoll(); return; }
    ws.onopen = () => { state.ws = true; wsRetry = 0; setSync('ok', '实时'); stopPoll(); };
    ws.onmessage = (ev) => {
      try {
        const msg = JSON.parse(ev.data);
        if (msg.type === 'hello') return;
        if (['create', 'delete', 'update', 'clear'].includes(msg.type)) refreshScoped();
        if ((msg.type === 'clip' || msg.type === 'devices') && sheetKind === 'clipsync' && clipView) clipView.load();
        if (msg.type === 'clip' && msg.origin !== DEVICE_ID && sheetKind !== 'clipsync') toast(`「${msg.origin_name || '其他设备'}」复制了新内容`);
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
        h('button', { type: 'button', class: 'star-filter', id: 'batchToggle', 'data-act': 'batch-toggle' }, icon('check'), h('span', { text: '多选' })),
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
  window.__clip = { state, openEdit, openAdd, openAuth, openShare, openTags, setScope, setFilter, setQuery, setTag, setStarred, refreshScoped, isSensitive, enqueue };
})();
