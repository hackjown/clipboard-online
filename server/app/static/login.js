(function () {
  var mark = document.getElementById('brandMark');
  mark.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M8 7v9a4 4 0 0 0 8 0V6a2.5 2.5 0 0 0-5 0v9.5a1 1 0 0 0 2 0V8"/></svg>';
  var f = document.getElementById('f'), err = document.getElementById('err'), go = document.getElementById('go');
  f.addEventListener('submit', function (e) {
    e.preventDefault();
    go.disabled = true; err.hidden = true;
    fetch('/login', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ password: document.getElementById('pw').value }), credentials: 'same-origin' })
      .then(function (r) { return r.json().then(function (d) { return { ok: r.ok, d: d }; }); })
      .then(function (r) {
        if (r.ok) { location.href = '/'; return; }
        err.textContent = (r.d && (r.d.error || r.d.detail)) || '登录失败';
        err.hidden = false; go.disabled = false;
      })
      .catch(function () { err.textContent = '网络错误，请重试'; err.hidden = false; go.disabled = false; });
  });
})();
