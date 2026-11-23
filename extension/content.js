/* Clipboard Vault Content Script：
 * - 智能识别登录表单（兼容 React / Vue / Angular 受控组件）
 * - 聚焦登录输入框时显示轻量悬浮 🔑 菜单（Shadow DOM 样式隔离，不污染页面）
 * - 监听登录提交，检测新账号密码并在扩展图标提示「+」一键保存
 */
(function () {
  'use strict';

  var nativeSetter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
  function setInputValue(el, val) {
    if (!el || val == null) return;
    el.focus();
    nativeSetter.call(el, val);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }

  function isVisible(el) {
    if (!el || el.disabled || el.readOnly) return false;
    var r = el.getBoundingClientRect();
    return r.width > 10 && r.height > 10 && getComputedStyle(el).visibility !== 'hidden';
  }

  function findFormInputs(anchor) {
    var root = (anchor && anchor.form) || document;
    var all = Array.from(root.querySelectorAll('input')).filter(isVisible);
    var pwFields = all.filter(function (i) { return i.type === 'password'; });
    var pw = (anchor && anchor.type === 'password') ? anchor : (pwFields[0] || null);
    var user = null;
    if (anchor && anchor.type !== 'password' && /^(text|email|tel|search)?$/i.test(anchor.type || 'text')) {
      user = anchor;
    } else {
      var cand = all.filter(function (i) {
        if (i === pw) return false;
        var t = (i.type || 'text').toLowerCase();
        if (['text', 'email', 'tel'].indexOf(t) < 0) return false;
        var hint = ((i.autocomplete || '') + ' ' + (i.name || '') + ' ' + (i.id || '') + ' ' + (i.placeholder || '')).toLowerCase();
        return /user|email|mail|login|account|phone|mobile|账号|邮箱|手机|用户名/.test(hint);
      });
      if (cand.length) user = cand[0];
      else if (pw) {
        var idx = all.indexOf(pw);
        for (var k = idx - 1; k >= 0; k--) {
          var tp = (all[k].type || 'text').toLowerCase();
          if (tp === 'text' || tp === 'email' || tp === 'tel') { user = all[k]; break; }
        }
      }
    }
    var otp = all.find(function (i) {
      if (i === pw || i === user) return false;
      var hint = ((i.autocomplete || '') + ' ' + (i.name || '') + ' ' + (i.id || '') + ' ' + (i.placeholder || '')).toLowerCase();
      return /one-time-code|totp|2fa|otp|mfa|验证码/.test(hint);
    }) || null;
    return { user: user, pw: pw, otp: otp };
  }

  function performAutofill(cred, anchor) {
    var f = findFormInputs(anchor);
    var filled = 0;
    if (cred.username && f.user) { setInputValue(f.user, cred.username); filled++; }
    if (cred.password && f.pw) { setInputValue(f.pw, cred.password); filled++; }
    if (cred.totpCode && f.otp) { setInputValue(f.otp, cred.totpCode); filled++; }
    if (cred.totpCode && !f.otp && navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(cred.totpCode).catch(function () {});
    }
    return filled;
  }

  // ---- Shadow DOM 悬浮填充菜单（仅在密码库已解锁且有当前站匹配项时出现）----
  var hostEl = null, activeInput = null;
  function hideMenu() {
    if (hostEl) { hostEl.remove(); hostEl = null; }
  }
  function showMenuFor(input, matches) {
    hideMenu();
    if (!matches || !matches.length || !isVisible(input)) return;
    activeInput = input;
    var rect = input.getBoundingClientRect();
    hostEl = document.createElement('div');
    hostEl.style.cssText = 'position:fixed;z-index:2147483647;left:' + Math.max(8, Math.min(rect.left, window.innerWidth - 270)) + 'px;top:' + Math.min(rect.bottom + 4, window.innerHeight - 200) + 'px;';
    var shadow = hostEl.attachShadow({ mode: 'open' });
    var style = document.createElement('style');
    style.textContent =
      '.box{min-width:240px;max-width:300px;background:#FAF6EC;color:#17140F;border:2px solid #17140F;border-radius:12px;' +
      'box-shadow:4px 4px 0 #17140F;font:13px/1.4 -apple-system,BlinkMacSystemFont,sans-serif;overflow:hidden}' +
      '.hdr{padding:6px 10px;background:#F3EDDF;border-bottom:1.5px solid #17140F;font-weight:800;font-size:11.5px;display:flex;justify-content:space-between;align-items:center}' +
      '.row{display:flex;align-items:center;gap:8px;width:100%;padding:8px 10px;border:0;background:transparent;text-align:left;cursor:pointer;color:inherit}' +
      '.row:hover{background:#F3EDDF}.t{font-weight:700;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' +
      '.s{font-size:11.5px;color:#6B6458;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.m{min-width:0;flex:1}' +
      '.otp{padding:2px 6px;border-radius:6px;background:#CDF26B;border:1px solid #17140F;font:700 11px/1 monospace}';
    var box = document.createElement('div');
    box.className = 'box';
    var hdr = document.createElement('div');
    hdr.className = 'hdr';
    hdr.textContent = '🔑 Clipboard Vault · 点击填充';
    box.append(hdr);
    matches.slice(0, 5).forEach(function (m) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'row';
      var mid = document.createElement('div');
      mid.className = 'm';
      var t = document.createElement('div'); t.className = 't'; t.textContent = m.title;
      var s = document.createElement('div'); s.className = 's'; s.textContent = m.username || '（无用户名）';
      mid.append(t, s);
      btn.append(mid);
      if (m.totpCode) {
        var o = document.createElement('span'); o.className = 'otp'; o.textContent = m.totpCode;
        btn.append(o);
      }
      btn.addEventListener('mousedown', function (e) {
        e.preventDefault();
        performAutofill(m, activeInput);
        hideMenu();
      });
      box.append(btn);
    });
    shadow.append(style, box);
    document.documentElement.append(hostEl);
  }

  function looksLikeLoginInput(el) {
    if (!el || el.tagName !== 'INPUT' || !isVisible(el)) return false;
    var t = (el.type || 'text').toLowerCase();
    if (t === 'password') return true;
    if (t !== 'text' && t !== 'email' && t !== 'tel') return false;
    var hint = ((el.autocomplete || '') + ' ' + (el.name || '') + ' ' + (el.id || '') + ' ' + (el.placeholder || '')).toLowerCase();
    if (/user|email|mail|login|account|phone|账号|邮箱|用户名/.test(hint)) {
      return !!document.querySelector('input[type="password"]');
    }
    return false;
  }

  document.addEventListener('focusin', function (e) {
    var el = e.target;
    if (!looksLikeLoginInput(el)) { hideMenu(); return; }
    try {
      chrome.runtime.sendMessage({ type: 'CS_GET_MATCHES' }, function (res) {
        if (chrome.runtime.lastError || !res || !res.unlocked || !res.matches.length) return;
        if (document.activeElement === el) showMenuFor(el, res.matches);
      });
    } catch (_) {}
  }, true);

  document.addEventListener('mousedown', function (e) {
    if (hostEl && e.target !== hostEl && e.target !== activeInput) hideMenu();
  }, true);
  window.addEventListener('scroll', hideMenu, true);

  // ---- 监听登录表单提交，提示保存新凭据 ----
  function captureLogin(anchor) {
    var f = findFormInputs(anchor);
    if (!f.pw || !f.pw.value) return;
    try {
      chrome.runtime.sendMessage({
        type: 'CS_LOGIN_SUBMITTED',
        title: document.title || location.hostname,
        url: location.href,
        username: f.user ? f.user.value : '',
        password: f.pw.value,
      });
    } catch (_) {}
  }
  document.addEventListener('submit', function (e) {
    captureLogin(e.target && e.target.querySelector ? e.target.querySelector('input[type="password"]') : null);
  }, true);
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && e.target && e.target.tagName === 'INPUT' && e.target.type === 'password') {
      captureLogin(e.target);
    }
  }, true);

  // ---- 响应 Popup 主动填充指令 ----
  chrome.runtime.onMessage.addListener(function (msg, _sender, sendResponse) {
    if (msg && msg.type === 'AUTOFILL') {
      var n = performAutofill(msg.cred || {}, activeInput);
      hideMenu();
      sendResponse({ ok: n > 0, filled: n });
    } else if (msg && msg.type === 'FILL_GENERATED_PW') {
      var f = findFormInputs(activeInput);
      if (f.pw) { setInputValue(f.pw, msg.password); sendResponse({ ok: true }); }
      else sendResponse({ ok: false });
    }
  });
})();
