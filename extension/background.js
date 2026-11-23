/* Clipboard Vault MV3 Service Worker：
 * - 解锁后的对称密钥与明文仅保存在 chrome.storage.session（纯内存会话存储，浏览器关闭自动清除，绝不落盘）
 * - 15 分钟无操作通过 chrome.alarms 自动锁定
 * - content script 仅按当前页面域名获取匹配账号，不暴露整个密码库
 */
importScripts('crypto.js');

var LOCK_ALARM = 'vault-auto-lock';
var AUTO_LOCK_MIN = 15;

function normalizeBase(raw) {
  var s = String(raw || '').trim().replace(/\/+$/, '');
  if (s && !/^https?:\/\//i.test(s)) s = 'https://' + s;
  return s;
}

async function getAuth() {
  var d = await chrome.storage.local.get(['serverUrl', 'token', 'username']);
  return { serverUrl: d.serverUrl || '', token: d.token || '', username: d.username || '' };
}

async function getSession() {
  var d = await chrome.storage.session.get(['keyB64', 'saltB64', 'iterations', 'rev', 'data', 'pendingSave']);
  return d || {};
}

async function touchLockAlarm() {
  await chrome.alarms.clear(LOCK_ALARM);
  await chrome.alarms.create(LOCK_ALARM, { delayInMinutes: AUTO_LOCK_MIN });
}

async function lockVault() {
  await chrome.alarms.clear(LOCK_ALARM);
  await chrome.storage.session.remove(['keyB64', 'saltB64', 'iterations', 'rev', 'data']);
  await updateActiveBadge();
}

async function apiFetch(serverUrl, token, path, opts) {
  opts = opts || {};
  var headers = { Accept: 'application/json' };
  if (token) headers.Authorization = 'Bearer ' + token;
  var body = opts.body;
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify(body);
  }
  var r = await fetch(normalizeBase(serverUrl) + path, {
    method: opts.method || 'GET',
    headers: headers,
    body: body,
  });
  var d = await r.json().catch(function () { return {}; });
  return { ok: r.ok, status: r.status, d: d };
}

function findMatches(items, pageUrl) {
  if (!Array.isArray(items) || !pageUrl) return [];
  var scored = [];
  items.forEach(function (it) {
    var sc = VaultExtCrypto.matchScore(it.url, pageUrl);
    if (sc > 0) scored.push({ sc: sc, it: it });
  });
  scored.sort(function (a, b) {
    return (b.sc - a.sc) || (!!b.it.favorite - !!a.it.favorite) || ((b.it.updated_at || 0) - (a.it.updated_at || 0));
  });
  return scored.map(function (x) { return x.it; });
}

async function updateBadgeForTab(tab) {
  if (!tab || !tab.id) return;
  var sess = await getSession();
  if (sess.pendingSave && tab.url && VaultExtCrypto.matchScore(sess.pendingSave.url, tab.url) > 0) {
    await chrome.action.setBadgeText({ tabId: tab.id, text: '+' });
    await chrome.action.setBadgeBackgroundColor({ tabId: tab.id, color: '#FF4F2B' });
    return;
  }
  if (!sess.data || !tab.url || !/^https?:\/\//i.test(tab.url)) {
    await chrome.action.setBadgeText({ tabId: tab.id, text: '' });
    return;
  }
  var m = findMatches(sess.data.items, tab.url);
  await chrome.action.setBadgeText({ tabId: tab.id, text: m.length ? String(m.length) : '' });
  await chrome.action.setBadgeBackgroundColor({ tabId: tab.id, color: '#17140F' });
}

async function updateActiveBadge() {
  try {
    var tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tabs && tabs[0]) await updateBadgeForTab(tabs[0]);
  } catch (_) {}
}

chrome.alarms.onAlarm.addListener(function (alarm) {
  if (alarm && alarm.name === LOCK_ALARM) lockVault();
});
chrome.tabs.onActivated.addListener(async function (info) {
  try { await updateBadgeForTab(await chrome.tabs.get(info.tabId)); } catch (_) {}
});
chrome.tabs.onUpdated.addListener(function (tabId, changeInfo, tab) {
  if (changeInfo.status === 'complete' || changeInfo.url) updateBadgeForTab(tab);
});

async function saveVaultData(newData) {
  var auth = await getAuth();
  var sess = await getSession();
  if (!auth.token || !sess.keyB64 || !sess.saltB64) throw new Error('密码库已锁定，请先解锁');
  var keyBytes = VaultExtCrypto.b64Decode(sess.keyB64);
  var saltBytes = VaultExtCrypto.b64Decode(sess.saltB64);
  var iters = sess.iterations || VaultExtCrypto.DEFAULT_ITERS;
  var env = await VaultExtCrypto.encryptVault(newData, keyBytes, saltBytes, iters);
  env.expected_rev = sess.rev || 0;
  var res = await apiFetch(auth.serverUrl, auth.token, '/api/vault', { method: 'PUT', body: env });
  if (res.status === 409) throw new Error('密码库已在其他设备更新，请点「同步」刷新后再试');
  if (!res.ok) throw new Error((res.d && (res.d.error || res.d.detail)) || ('保存失败 HTTP ' + res.status));
  var newRev = (res.d.vault && res.d.vault.rev) || ((sess.rev || 0) + 1);
  await chrome.storage.session.set({ data: newData, rev: newRev });
  await touchLockAlarm();
  await updateActiveBadge();
  return { ok: true, rev: newRev, data: newData };
}

chrome.runtime.onMessage.addListener(function (msg, sender, sendResponse) {
  (async function () {
    var type = msg && msg.type;
    if (type === 'GET_STATE') {
      var auth = await getAuth();
      var sess = await getSession();
      var tabUrl = msg.tabUrl || '';
      var matches = sess.data ? findMatches(sess.data.items, tabUrl) : [];
      return {
        ok: true,
        loggedIn: !!(auth.serverUrl && auth.token),
        serverUrl: auth.serverUrl,
        username: auth.username,
        unlocked: !!(sess.keyB64 && sess.data),
        data: sess.data || null,
        rev: sess.rev || 0,
        matches: matches,
        pendingSave: sess.pendingSave || null,
      };
    }

    if (type === 'LOGIN') {
      var srv = normalizeBase(msg.serverUrl);
      if (!srv) throw new Error('请输入服务器地址');
      var res = await apiFetch(srv, '', '/api/login', {
        method: 'POST',
        body: { username: String(msg.username || '').trim(), password: String(msg.password || '') },
      });
      if (!res.ok) throw new Error((res.d && (res.d.error || res.d.detail)) || '登录失败');
      var user = res.d.user || {};
      await chrome.storage.local.set({ serverUrl: srv, token: res.d.token, username: user.username || msg.username });
      await lockVault();
      return { ok: true, username: user.username || msg.username };
    }

    if (type === 'CLAIM_PAIR') {
      var raw = String(msg.raw || '').trim();
      var srv2 = normalizeBase(msg.serverUrl || '');
      var code = raw;
      if (/^clipboard:\/\/pair/i.test(raw)) {
        var u = new URL(raw);
        srv2 = normalizeBase(u.searchParams.get('server') || srv2);
        code = (u.searchParams.get('code') || '').trim();
      }
      if (!srv2 || !code) throw new Error('请填写有效的配对链接或服务器地址+配对码');
      var r2 = await apiFetch(srv2, '', '/api/pair/claim', { method: 'POST', body: { code: code } });
      if (!r2.ok) throw new Error((r2.d && (r2.d.error || r2.d.detail)) || '配对失败');
      var u2 = r2.d.user || {};
      await chrome.storage.local.set({ serverUrl: srv2, token: r2.d.token, username: u2.username || '' });
      await lockVault();
      return { ok: true, username: u2.username || '' };
    }

    if (type === 'LOGOUT') {
      await lockVault();
      await chrome.storage.local.remove(['token', 'username']);
      await chrome.storage.session.remove(['pendingSave']);
      return { ok: true };
    }

    if (type === 'UNLOCK') {
      var auth3 = await getAuth();
      if (!auth3.token) throw new Error('请先登录账号');
      var vr = await apiFetch(auth3.serverUrl, auth3.token, '/api/vault');
      if (!vr.ok) throw new Error((vr.d && (vr.d.error || vr.d.detail)) || '读取密码库失败');
      if (!vr.d.exists || !vr.d.vault) {
        if (!msg.createIfMissing) return { ok: false, needsSetup: true };
        var pw = String(msg.masterPassword || '');
        if (pw.length < 8) throw new Error('主密码至少需要 8 位');
        var newSalt = VaultExtCrypto.randBytes(16);
        var newKey = await VaultExtCrypto.deriveKeyBytes(pw, newSalt, VaultExtCrypto.DEFAULT_ITERS);
        var initData = { v: 1, items: [] };
        await chrome.storage.session.set({
          keyB64: VaultExtCrypto.b64Encode(newKey),
          saltB64: VaultExtCrypto.b64Encode(newSalt),
          iterations: VaultExtCrypto.DEFAULT_ITERS,
          rev: 0,
          data: initData,
        });
        await saveVaultData(initData);
        return { ok: true, created: true };
      }
      var env = vr.d.vault;
      var salt = VaultExtCrypto.b64Decode(env.salt);
      var iters = env.iterations || VaultExtCrypto.DEFAULT_ITERS;
      var keyBytes = await VaultExtCrypto.deriveKeyBytes(String(msg.masterPassword || ''), salt, iters);
      var dec = await VaultExtCrypto.decryptVault(env, keyBytes);
      await chrome.storage.session.set({
        keyB64: VaultExtCrypto.b64Encode(keyBytes),
        saltB64: env.salt,
        iterations: iters,
        rev: env.rev || 0,
        data: dec,
      });
      await touchLockAlarm();
      await updateActiveBadge();
      return { ok: true, rev: env.rev || 0 };
    }

    if (type === 'SYNC') {
      var auth4 = await getAuth();
      var sess4 = await getSession();
      if (!auth4.token || !sess4.keyB64) throw new Error('请先解锁密码库');
      var vr4 = await apiFetch(auth4.serverUrl, auth4.token, '/api/vault');
      if (!vr4.ok || !vr4.d.exists) throw new Error('拉取失败');
      var env4 = vr4.d.vault;
      if (env4.salt !== sess4.saltB64) {
        await lockVault();
        throw new Error('主密码已在其他设备变更，请重新输入新主密码解锁');
      }
      var dec4 = await VaultExtCrypto.decryptVault(env4, VaultExtCrypto.b64Decode(sess4.keyB64));
      await chrome.storage.session.set({ data: dec4, rev: env4.rev || 0 });
      await touchLockAlarm();
      await updateActiveBadge();
      return { ok: true, data: dec4, rev: env4.rev || 0 };
    }

    if (type === 'LOCK') {
      await lockVault();
      return { ok: true };
    }

    if (type === 'SAVE_ITEM') {
      var sess5 = await getSession();
      if (!sess5.data) throw new Error('密码库已锁定');
      var items = (sess5.data.items || []).slice();
      var item = msg.item;
      var now = Math.floor(Date.now() / 1000);
      if (!item.id) {
        item.id = VaultExtCrypto.makeId();
        item.created_at = now;
        item.updated_at = now;
        items.unshift(item);
      } else {
        item.updated_at = now;
        var idx = items.findIndex(function (x) { return x.id === item.id; });
        if (idx >= 0) items[idx] = item; else items.unshift(item);
      }
      var saved = await saveVaultData({ v: 1, items: items });
      await chrome.storage.session.remove(['pendingSave']);
      return saved;
    }

    if (type === 'DELETE_ITEM') {
      var sess6 = await getSession();
      if (!sess6.data) throw new Error('密码库已锁定');
      var items6 = (sess6.data.items || []).filter(function (x) { return x.id !== msg.id; });
      return await saveVaultData({ v: 1, items: items6 });
    }

    if (type === 'DISMISS_PENDING') {
      await chrome.storage.session.remove(['pendingSave']);
      await updateActiveBadge();
      return { ok: true };
    }

    // Content script 按当前页面域名请求匹配账号（最小暴露原则）
    if (type === 'CS_GET_MATCHES') {
      var pageUrl = (sender && sender.tab && sender.tab.url) || '';
      var sess7 = await getSession();
      if (!sess7.data || !pageUrl) return { ok: true, unlocked: false, matches: [] };
      await touchLockAlarm();
      var matched = findMatches(sess7.data.items, pageUrl);
      var out = [];
      for (var i = 0; i < matched.length; i++) {
        var it = matched[i];
        var otp = it.totp ? await VaultExtCrypto.totpCode(it.totp) : null;
        out.push({
          id: it.id,
          title: it.title || it.url || '未命名',
          username: it.username || '',
          password: it.password || '',
          totpCode: otp ? otp.code : '',
        });
      }
      return { ok: true, unlocked: true, matches: out };
    }

    // Content script 检测到新登录表单提交 -> 暂存为待保存提示
    if (type === 'CS_LOGIN_SUBMITTED') {
      var sess8 = await getSession();
      if (!sess8.data) return { ok: true };
      var u8 = String(msg.username || '').trim();
      var p8 = String(msg.password || '');
      var url8 = (sender && sender.tab && sender.tab.url) || msg.url || '';
      if (!p8 || !/^https?:\/\//i.test(url8)) return { ok: true };
      var existing = findMatches(sess8.data.items, url8).find(function (x) {
        return (x.username || '').toLowerCase() === u8.toLowerCase() && x.password === p8;
      });
      if (existing) return { ok: true };
      var pending = {
        title: msg.title || VaultExtCrypto.extractHost(url8) || '新登录',
        url: url8,
        username: u8,
        password: p8,
      };
      await chrome.storage.session.set({ pendingSave: pending });
      if (sender && sender.tab) await updateBadgeForTab(sender.tab);
      return { ok: true };
    }

    return { ok: false, error: '未知指令' };
  })()
    .then(function (r) { sendResponse(r); })
    .catch(function (e) { sendResponse({ ok: false, error: (e && e.message) || String(e) }); });
  return true;
});
