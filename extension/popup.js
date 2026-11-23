/* Clipboard Vault Chrome/Edge Popup UI（全部 textContent 渲染）*/
(function () {
  'use strict';

  var app = document.getElementById('app');
  var hdrActs = document.getElementById('hdrActs');
  var toastEl = document.getElementById('toast');
  var toastTimer = null, totpTimer = null;
  var curTab = null, st = null, activeView = 'site', query = '';

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function toast(msg) {
    toastEl.textContent = msg;
    toastEl.hidden = false;
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toastEl.hidden = true; }, 2200);
  }
  function send(msg) {
    return new Promise(function (resolve) {
      chrome.runtime.sendMessage(msg, function (res) {
        if (chrome.runtime.lastError) resolve({ ok: false, error: chrome.runtime.lastError.message });
        else resolve(res || { ok: false, error: '无响应' });
      });
    });
  }
  async function getActiveTab() {
    var tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    return (tabs && tabs[0]) || null;
  }
  async function copyText(val, label) {
    if (!val) return;
    try {
      await navigator.clipboard.writeText(val);
      toast((label || '内容') + '已复制');
    } catch (_) { toast('复制失败'); }
  }
  async function autofillItem(it) {
    if (!curTab || !curTab.id) { toast('无法获取当前标签页'); return; }
    var otp = it.totp ? await VaultExtCrypto.totpCode(it.totp) : null;
    chrome.tabs.sendMessage(curTab.id, {
      type: 'AUTOFILL',
      cred: { username: it.username || '', password: it.password || '', totpCode: otp ? otp.code : '' },
    }, function (res) {
      if (chrome.runtime.lastError || !res || !res.ok) {
        copyText(it.password || it.username, '当前页未检测到输入框，密码');
      } else {
        toast('已自动填充' + (otp ? '（2FA 已处理）' : ''));
        setTimeout(function () { window.close(); }, 350);
      }
    });
  }

  async function refresh() {
    curTab = await getActiveTab();
    var r = await send({ type: 'GET_STATE', tabUrl: (curTab && curTab.url) || '' });
    if (!r.ok) { app.replaceChildren(el('p', 'err', r.error || '初始化失败')); return; }
    st = r;
    if (!st.loggedIn) renderLogin();
    else if (!st.unlocked) renderUnlock(false);
    else renderUnlocked();
  }

  function renderLogin() {
    if (totpTimer) { clearInterval(totpTimer); totpTimer = null; }
    hdrActs.replaceChildren();
    app.replaceChildren();
    var card = el('div', 'card');
    card.append(el('h2', null, '连接 Clipboard Online'), el('p', 'muted', '连接你自建的 Clipboard Online 服务器，使用账号或配对码登录。'));
    var srv = el('input', 'in'); srv.placeholder = '服务器地址，如 https://clip.example.com'; srv.value = st.serverUrl || '';
    var usr = el('input', 'in'); usr.placeholder = '用户名';
    var pw = el('input', 'in'); pw.type = 'password'; pw.placeholder = '账号密码';
    var err = el('p', 'err'); err.hidden = true;
    var btn = el('button', 'btn btn--acc btn--blk', '登录'); btn.type = 'submit';
    var form = el('form', 'card'); form.style.cssText = 'border:0;box-shadow:none;padding:0;background:transparent';
    form.append(srv, usr, pw, err, btn);
    form.onsubmit = async function (e) {
      e.preventDefault(); err.hidden = true; btn.disabled = true;
      var r = await send({ type: 'LOGIN', serverUrl: srv.value, username: usr.value, password: pw.value });
      btn.disabled = false;
      if (!r.ok) { err.textContent = r.error || '登录失败'; err.hidden = false; return; }
      toast('已登录 @' + r.username);
      refresh();
    };
    var pairIn = el('input', 'in'); pairIn.placeholder = '或粘贴网页生成的 clipboard://pair?... 配对链接';
    var pairBtn = el('button', 'btn btn--blk', '配对码一键登录'); pairBtn.type = 'button';
    pairBtn.onclick = async function () {
      err.hidden = true; pairBtn.disabled = true;
      var r = await send({ type: 'CLAIM_PAIR', serverUrl: srv.value, raw: pairIn.value });
      pairBtn.disabled = false;
      if (!r.ok) { err.textContent = r.error || '配对失败'; err.hidden = false; return; }
      toast('配对成功 @' + r.username);
      refresh();
    };
    card.append(form, el('p', 'sec-lbl', '快速配对'), pairIn, pairBtn);
    app.append(card);
  }

  function renderUnlock(createMode) {
    if (totpTimer) { clearInterval(totpTimer); totpTimer = null; }
    hdrActs.replaceChildren();
    var outBtn = el('button', 'btn btn--sm btn--ghost', '退出'); outBtn.type = 'button';
    outBtn.onclick = async function () { await send({ type: 'LOGOUT' }); refresh(); };
    hdrActs.append(outBtn);

    app.replaceChildren();
    var card = el('div', 'card');
    card.append(
      el('h2', null, createMode ? '创建密码保险箱' : '解锁密码保险箱'),
      el('p', 'muted', '@' + (st.username || '') + ' · ' + (createMode ? '尚未创建密码库，请设置主密码（至少 8 位），仅在本地加密。' : '输入主密码在本地解密（15 分钟无操作自动锁定）。'))
    );
    var pw = el('input', 'in'); pw.type = 'password'; pw.placeholder = createMode ? '设置主密码（至少 8 位）' : '输入主密码';
    var pw2 = el('input', 'in'); pw2.type = 'password'; pw2.placeholder = '再次输入主密码'; pw2.hidden = !createMode;
    var err = el('p', 'err'); err.hidden = true;
    var btn = el('button', 'btn btn--acc btn--blk', createMode ? '创建并解锁' : '解锁'); btn.type = 'submit';
    var form = el('form', 'card'); form.style.cssText = 'border:0;box-shadow:none;padding:0;background:transparent';
    form.append(pw, pw2, err, btn);
    form.onsubmit = async function (e) {
      e.preventDefault(); err.hidden = true;
      if (createMode && pw.value !== pw2.value) { err.textContent = '两次输入的主密码不一致'; err.hidden = false; return; }
      btn.disabled = true; btn.textContent = '正在派生密钥…';
      var r = await send({ type: 'UNLOCK', masterPassword: pw.value, createIfMissing: createMode });
      btn.disabled = false; btn.textContent = createMode ? '创建并解锁' : '解锁';
      if (r.needsSetup) { renderUnlock(true); return; }
      if (!r.ok) { err.textContent = r.error || '解锁失败'; err.hidden = false; return; }
      refresh();
    };
    card.append(form);
    app.append(card);
    pw.focus();
  }

  function renderUnlocked() {
    hdrActs.replaceChildren();
    var addB = el('button', 'btn btn--sm btn--acc', '+ 新建'); addB.type = 'button'; addB.onclick = function () { renderEditor(null); };
    var syncB = el('button', 'btn btn--sm', '同步'); syncB.type = 'button';
    syncB.onclick = async function () {
      var r = await send({ type: 'SYNC' });
      if (!r.ok) { toast(r.error || '同步失败'); refresh(); return; }
      toast('已同步最新版 (rev ' + r.rev + ')');
      refresh();
    };
    var lockB = el('button', 'btn btn--sm', '🔒'); lockB.type = 'button'; lockB.title = '立即锁定';
    lockB.onclick = async function () { await send({ type: 'LOCK' }); refresh(); };
    hdrActs.append(addB, syncB, lockB);

    app.replaceChildren();

    // 检测到刚刚提交的新登录凭据 -> 一键保存横幅
    if (st.pendingSave) {
      var ps = st.pendingSave;
      var ban = el('div', 'banner');
      ban.append(
        el('b', null, '发现新登录：' + ps.title),
        el('p', 'muted', (ps.username || '（无用户名）') + ' · ' + VaultExtCrypto.extractHost(ps.url))
      );
      var saveP = el('button', 'btn btn--sm btn--acc', '加密保存到保险箱'); saveP.type = 'button';
      saveP.onclick = async function () {
        var r = await send({ type: 'SAVE_ITEM', item: { kind: 'login', title: ps.title, url: ps.url, username: ps.username, password: ps.password, totp: '', notes: '', fields: [], tags: [], favorite: false } });
        if (!r.ok) { toast(r.error || '保存失败'); return; }
        toast('已保存到密码库');
        refresh();
      };
      var disP = el('button', 'btn btn--sm btn--ghost', '忽略'); disP.type = 'button';
      disP.onclick = async function () { await send({ type: 'DISMISS_PENDING' }); refresh(); };
      var br = el('div', 'row'); br.append(saveP, disP);
      ban.append(br);
      app.append(ban);
    }

    var search = el('input', 'in'); search.type = 'search'; search.placeholder = '搜索名称、账号、网址…'; search.value = query;
    var tabs = el('div', 'tabs');
    var defs = [['site', '当前网站 (' + st.matches.length + ')'], ['all', '全部'], ['2fa', '2FA'], ['gen', '生成器']];
    defs.forEach(function (d) {
      var b = el('button', 'tab', d[1]); b.type = 'button';
      b.setAttribute('aria-selected', activeView === d[0] ? 'true' : 'false');
      b.onclick = function () { activeView = d[0]; renderUnlocked(); };
      tabs.append(b);
    });
    var body = el('div'); body.style.cssText = 'display:flex;flex-direction:column;gap:8px';
    app.append(search, tabs, body);
    search.oninput = function () { query = search.value.trim().toLowerCase(); if (query && activeView === 'site') activeView = 'all'; drawBody(); };

    async function drawBody() {
      body.replaceChildren();
      if (activeView === 'gen') {
        var opts = { mode: 'random', length: 20, symbols: true };
        var out = el('div', 'gen-out', VaultExtCrypto.genPassword(opts));
        var lenLbl = el('p', 'muted', '长度：20');
        var rng = document.createElement('input'); rng.type = 'range'; rng.min = '8'; rng.max = '48'; rng.value = '20';
        rng.oninput = function () { opts.length = Number(rng.value); lenLbl.textContent = '长度：' + opts.length; out.textContent = VaultExtCrypto.genPassword(opts); };
        var r1 = el('button', 'btn btn--sm', '随机字符'); r1.type = 'button'; r1.onclick = function () { opts.mode = 'random'; out.textContent = VaultExtCrypto.genPassword(opts); };
        var r2 = el('button', 'btn btn--sm', '易记词组'); r2.type = 'button'; r2.onclick = function () { opts.mode = 'passphrase'; out.textContent = VaultExtCrypto.genPassword(opts); };
        var r3 = el('button', 'btn btn--sm', '换一个'); r3.type = 'button'; r3.onclick = function () { out.textContent = VaultExtCrypto.genPassword(opts); };
        var mrow = el('div', 'row'); mrow.append(r1, r2, r3);
        var cp = el('button', 'btn btn--acc', '复制密码'); cp.type = 'button'; cp.onclick = function () { copyText(out.textContent, '密码'); };
        var fill = el('button', 'btn btn--ink', '填入当前页'); fill.type = 'button';
        fill.onclick = function () {
          if (!curTab || !curTab.id) return;
          chrome.tabs.sendMessage(curTab.id, { type: 'FILL_GENERATED_PW', password: out.textContent }, function (r) {
            if (chrome.runtime.lastError || !r || !r.ok) copyText(out.textContent, '未检测到密码框，已复制');
            else { toast('已填入密码框'); setTimeout(function () { window.close(); }, 300); }
          });
        };
        var brow = el('div', 'row'); brow.append(cp, fill);
        var c = el('div', 'card'); c.append(out, mrow, lenLbl, rng, brow);
        body.append(c);
        return;
      }

      var items = activeView === 'site' ? (st.matches || []) : ((st.data && st.data.items) || []);
      if (activeView === '2fa') items = items.filter(function (x) { return !!x.totp; });
      if (query) {
        items = items.filter(function (x) {
          return [x.title, x.username, x.url, x.notes, (x.tags || []).join(' ')].join(' ').toLowerCase().indexOf(query) >= 0;
        });
      }
      if (!items.length) {
        body.append(el('p', 'empty', activeView === 'site' ? '当前网站没有保存的账号。点右上角「+ 新建」可快速保存当前网站。' : '没有匹配的条目'));
        return;
      }
      for (var i = 0; i < items.length; i++) {
        (function (it) {
          var card = el('div', 'item');
          var mid = el('div', 'item-m');
          mid.append(el('div', 'item-t', (it.favorite ? '★ ' : '') + (it.title || '未命名')), el('div', 'item-s', it.username || it.url || ''));
          mid.onclick = function () { renderEditor(it); };
          var acts = el('div', 'item-a');
          if (it.totp) {
            var ob = el('button', 'otp', '…'); ob.type = 'button'; ob.dataset.totp = it.totp; ob.title = '点击复制 2FA';
            ob.onclick = async function () { var o = await VaultExtCrypto.totpCode(it.totp); if (o) copyText(o.code, '验证码'); };
            acts.append(ob);
          }
          if (activeView === 'site' && (it.username || it.password)) {
            var fb = el('button', 'btn btn--sm btn--acc', '填充'); fb.type = 'button';
            fb.onclick = function () { autofillItem(it); };
            acts.append(fb);
          } else if (it.password) {
            var cp = el('button', 'btn btn--sm', '密码'); cp.type = 'button';
            cp.onclick = function () { copyText(it.password, '密码'); };
            acts.append(cp);
          }
          card.append(mid, acts);
          body.append(card);
        })(items[i]);
      }
      updateTotps();
    }

    async function updateTotps() {
      var nodes = body.querySelectorAll('[data-totp]');
      for (var i = 0; i < nodes.length; i++) {
        var o = await VaultExtCrypto.totpCode(nodes[i].dataset.totp);
        if (o) nodes[i].textContent = o.code.slice(0, 3) + ' ' + o.code.slice(3) + ' · ' + o.remaining + 's';
      }
    }

    drawBody();
    if (totpTimer) clearInterval(totpTimer);
    totpTimer = setInterval(updateTotps, 1000);
  }

  function renderEditor(existing) {
    if (totpTimer) { clearInterval(totpTimer); totpTimer = null; }
    var isNew = !existing;
    var tabUrl = (curTab && curTab.url && /^https?:\/\//i.test(curTab.url)) ? curTab.url : '';
    var tabHost = VaultExtCrypto.extractHost(tabUrl);
    var cur = existing ? JSON.parse(JSON.stringify(existing)) : {
      kind: 'login', title: tabHost || '', url: tabUrl, username: '', password: '', totp: '', notes: '', fields: [], tags: [], favorite: false,
    };
    app.replaceChildren();
    var card = el('div', 'card');
    card.append(el('h2', null, isNew ? '新建加密条目' : '查看 / 编辑条目'));

    var kindSel = el('select', 'in');
    [['login', '🔑 登录账号'], ['note', '📝 安全笔记'], ['card', '💳 银行卡片'], ['idcard', '🪪 证件资料'], ['apikey', '⚡ API 密钥']].forEach(function (p) {
      var o = document.createElement('option'); o.value = p[0]; o.textContent = p[1];
      if (cur.kind === p[0]) o.selected = true;
      kindSel.append(o);
    });

    var tIn = el('input', 'in'); tIn.placeholder = '名称'; tIn.value = cur.title || '';
    var uIn = el('input', 'in'); uIn.placeholder = '用户名 / 邮箱'; uIn.value = cur.username || '';
    var pIn = el('input', 'in mono'); pIn.placeholder = '密码'; pIn.value = cur.password || '';
    var gBtn = el('button', 'btn btn--sm', '🎲'); gBtn.type = 'button'; gBtn.title = '生成强密码';
    gBtn.onclick = function () { pIn.value = VaultExtCrypto.genPassword({ length: 20 }); };
    var cBtn = el('button', 'btn btn--sm', '复制'); cBtn.type = 'button';
    cBtn.onclick = function () { copyText(pIn.value, '密码'); };
    var pRow = el('div', 'row'); pIn.style.flex = '1'; pRow.append(pIn, gBtn, cBtn);
    var urlIn = el('input', 'in'); urlIn.placeholder = '网址'; urlIn.value = cur.url || '';
    var otpIn = el('input', 'in mono'); otpIn.placeholder = 'TOTP 密钥或 otpauth://（可选）'; otpIn.value = cur.totp || '';
    var nIn = el('textarea', 'ta'); nIn.placeholder = '备注'; nIn.value = cur.notes || '';
    var err = el('p', 'err'); err.hidden = true;

    function updateFields() {
      var k = kindSel.value;
      if (k === 'note') {
        tIn.placeholder = '笔记标题 *（如 服务器备忘）';
        uIn.hidden = true; pRow.hidden = true; urlIn.hidden = true; otpIn.hidden = true;
        nIn.hidden = false; nIn.rows = 8; nIn.placeholder = '安全笔记内容 *';
      } else if (k === 'card') {
        tIn.placeholder = '卡片名称 *（如 招行信用卡）';
        uIn.hidden = false; uIn.placeholder = '持卡人姓名';
        pRow.hidden = false; pIn.placeholder = '卡号';
        urlIn.hidden = true; otpIn.hidden = true;
        nIn.hidden = false; nIn.rows = 3; nIn.placeholder = '备注（如 发卡行、客服电话等）';
      } else if (k === 'idcard') {
        tIn.placeholder = '证件名称 *（如 居民身份证、护照）';
        uIn.hidden = false; uIn.placeholder = '姓名 / 持有人';
        pRow.hidden = false; pIn.placeholder = '证件号码 *';
        urlIn.hidden = true; otpIn.hidden = true;
        nIn.hidden = false; nIn.rows = 3; nIn.placeholder = '备注说明';
      } else if (k === 'apikey') {
        tIn.placeholder = '名称 *（如 OpenAI、AWS Token）';
        uIn.hidden = false; uIn.placeholder = 'Key ID / Access Key（可选）';
        pRow.hidden = false; pIn.placeholder = 'API 密钥 / Secret Token *';
        urlIn.hidden = false; urlIn.placeholder = '接口地址 / 服务端点';
        otpIn.hidden = true;
        nIn.hidden = false; nIn.rows = 3; nIn.placeholder = '备注说明';
      } else {
        tIn.placeholder = '名称（如 GitHub、Google）';
        uIn.hidden = false; uIn.placeholder = '用户名 / 邮箱';
        pRow.hidden = false; pIn.placeholder = '密码';
        urlIn.hidden = false; urlIn.placeholder = '网址';
        otpIn.hidden = false; otpIn.placeholder = 'TOTP 密钥或 otpauth://（可选）';
        nIn.hidden = false; nIn.rows = 3; nIn.placeholder = '备注';
      }
    }
    kindSel.onchange = updateFields;
    updateFields();

    var back = el('button', 'btn', '返回'); back.type = 'button'; back.onclick = function () { renderUnlocked(); };
    var fillB = el('button', 'btn btn--ink', '填充'); fillB.type = 'button';
    fillB.onclick = function () { autofillItem({ username: uIn.value, password: pIn.value, totp: otpIn.value }); };
    var saveB = el('button', 'btn btn--acc', '加密保存'); saveB.type = 'button';
    saveB.onclick = async function () {
      cur.kind = kindSel.value;
      cur.title = tIn.value.trim() || VaultExtCrypto.extractHost(urlIn.value) || '未命名';
      cur.username = cur.kind === 'note' ? '' : uIn.value.trim();
      cur.password = cur.kind === 'note' ? '' : pIn.value;
      cur.url = (cur.kind === 'login' || cur.kind === 'apikey') ? urlIn.value.trim() : '';
      cur.totp = (cur.kind === 'login') ? otpIn.value.trim() : '';
      cur.notes = nIn.value;
      saveB.disabled = true; err.hidden = true;
      var r = await send({ type: 'SAVE_ITEM', item: cur });
      saveB.disabled = false;
      if (!r.ok) { err.textContent = r.error || '保存失败'; err.hidden = false; return; }
      toast('已加密保存');
      refresh();
    };
    var row = el('div', 'row'); row.append(back, fillB, saveB);
    card.append(kindSel, tIn, uIn, pRow, urlIn, otpIn, nIn, err, row);
    if (!isNew) {
      var del = el('button', 'btn btn--sm btn--ghost', '删除此条目'); del.type = 'button'; del.style.color = 'var(--danger)';
      del.onclick = async function () {
        if (!confirm('确认删除「' + cur.title + '」？')) return;
        var r = await send({ type: 'DELETE_ITEM', id: cur.id });
        if (!r.ok) { toast(r.error || '删除失败'); return; }
        toast('已删除');
        refresh();
      };
      card.append(del);
    }
    app.append(card);
  }

  refresh();
})();
