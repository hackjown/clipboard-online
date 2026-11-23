/* Clipboard Vault Extension — 加密、TOTP、密码生成与域名匹配（与 Web vault.js / Flutter vault_crypto.dart 字节级互通）*/
(function (global) {
  'use strict';

  var DEFAULT_ITERS = 200000;
  var te = new TextEncoder();
  var td = new TextDecoder();

  function b64Encode(bytes) {
    var bin = '';
    for (var i = 0; i < bytes.length; i += 0x8000) {
      bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    }
    return btoa(bin);
  }
  function b64Decode(str) {
    var bin = atob(str);
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  function randBytes(n) {
    var b = new Uint8Array(n);
    global.crypto.getRandomValues(b);
    return b;
  }
  function makeId() {
    var b = randBytes(16), hex = '';
    for (var i = 0; i < 16; i++) hex += (b[i] < 16 ? '0' : '') + b[i].toString(16);
    return hex;
  }

  async function deriveKeyBytes(password, saltBytes, iterations) {
    var baseKey = await global.crypto.subtle.importKey('raw', te.encode(password), 'PBKDF2', false, ['deriveBits']);
    var bits = await global.crypto.subtle.deriveBits(
      { name: 'PBKDF2', salt: saltBytes, iterations: iterations, hash: 'SHA-256' },
      baseKey,
      256
    );
    return new Uint8Array(bits);
  }

  async function importAesKey(keyBytes) {
    return global.crypto.subtle.importKey('raw', keyBytes, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
  }

  async function encryptVault(payloadObj, keyBytes, saltBytes, iterations) {
    var iv = randBytes(12);
    var aesKey = await importAesKey(keyBytes);
    var plain = te.encode(JSON.stringify(payloadObj));
    var buf = await global.crypto.subtle.encrypt({ name: 'AES-GCM', iv: iv }, aesKey, plain);
    return {
      version: 1,
      kdf: 'PBKDF2-SHA256',
      iterations: iterations || DEFAULT_ITERS,
      salt: b64Encode(saltBytes),
      iv: b64Encode(iv),
      ct: b64Encode(new Uint8Array(buf)),
      item_count: (payloadObj.items || []).length,
    };
  }

  async function decryptVault(envelope, keyBytes) {
    var iv = b64Decode(envelope.iv);
    var ct = b64Decode(envelope.ct);
    var aesKey = await importAesKey(keyBytes);
    var buf;
    try {
      buf = await global.crypto.subtle.decrypt({ name: 'AES-GCM', iv: iv }, aesKey, ct);
    } catch (_) {
      throw new Error('主密码错误或数据已被篡改');
    }
    var obj = JSON.parse(td.decode(new Uint8Array(buf)));
    if (!obj || typeof obj !== 'object' || !Array.isArray(obj.items)) {
      throw new Error('密码库数据结构异常');
    }
    return obj;
  }

  // ---- RFC 6238 TOTP（使用 WebCrypto HMAC-SHA1/SHA256）----
  var B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  function base32Decode(str) {
    var s = String(str || '').toUpperCase().replace(/[^A-Z2-7]/g, '');
    if (!s) return null;
    var bits = 0, val = 0, out = [];
    for (var i = 0; i < s.length; i++) {
      var idx = B32.indexOf(s[i]);
      if (idx < 0) continue;
      val = (val << 5) | idx;
      bits += 5;
      if (bits >= 8) { bits -= 8; out.push((val >>> bits) & 0xff); }
    }
    return out.length ? new Uint8Array(out) : null;
  }
  function parseOtp(raw) {
    var s = String(raw || '').trim();
    if (!s) return null;
    var secret = s, digits = 6, period = 30, algo = 'SHA-1';
    if (/^otpauth:\/\//i.test(s)) {
      try {
        var u = new URL(s);
        secret = u.searchParams.get('secret') || '';
        digits = parseInt(u.searchParams.get('digits') || '6', 10) || 6;
        period = parseInt(u.searchParams.get('period') || '30', 10) || 30;
        var a = (u.searchParams.get('algorithm') || 'SHA1').toUpperCase();
        algo = a === 'SHA256' ? 'SHA-256' : (a === 'SHA512' ? 'SHA-512' : 'SHA-1');
      } catch (_) { return null; }
    }
    var key = base32Decode(secret);
    if (!key) return null;
    return { key: key, digits: Math.max(6, Math.min(8, digits)), period: Math.max(10, Math.min(120, period)), algo: algo };
  }
  async function totpCode(raw, nowSec) {
    var cfg = parseOtp(raw);
    if (!cfg) return null;
    var t = nowSec != null ? nowSec : Math.floor(Date.now() / 1000);
    var counter = Math.floor(t / cfg.period);
    var msg = new Uint8Array(8);
    var dv = new DataView(msg.buffer);
    dv.setUint32(0, Math.floor(counter / 0x100000000), false);
    dv.setUint32(4, counter >>> 0, false);
    var k = await global.crypto.subtle.importKey('raw', cfg.key, { name: 'HMAC', hash: cfg.algo }, false, ['sign']);
    var sig = new Uint8Array(await global.crypto.subtle.sign('HMAC', k, msg));
    var off = sig[sig.length - 1] & 0x0f;
    var bin = ((sig[off] & 0x7f) << 24) | ((sig[off + 1] & 0xff) << 16) | ((sig[off + 2] & 0xff) << 8) | (sig[off + 3] & 0xff);
    var mod = Math.pow(10, cfg.digits);
    var code = String(bin % mod);
    while (code.length < cfg.digits) code = '0' + code;
    return { code: code, remaining: cfg.period - (t % cfg.period), period: cfg.period, digits: cfg.digits };
  }

  // ---- 强密码生成器 ----
  var WORDS = [
    'amber','anchor','apple','atlas','bamboo','beacon','berry','breeze','bridge','canyon',
    'cedar','cloud','cobalt','comet','coral','crane','crystal','delta','drift','ember',
    'falcon','fern','fjord','flame','forest','frost','garden','glacier','granite','harbor',
    'horizon','indigo','island','ivory','jasper','jungle','kernel','lagoon','lantern','laurel',
    'lemon','lotus','lunar','mango','maple','meadow','meteor','mint','mist','nebula',
    'nectar','oak','oasis','ocean','olive','onyx','orbit','orchid','otter','pebble',
    'pepper','phoenix','pine','planet','plume','prism','quartz','rain','raven','reef',
    'ridge','river','robin','saffron','sage','sail','sand','saturn','shadow','shell',
    'sierra','silver','sky','slate','solar','spark','spruce','star','stone','storm',
    'summit','sun','swift','timber','topaz','trail','tulip','valley','velvet','zephyr'
  ];
  function randInt(max) {
    if (max <= 1) return 0;
    var limit = Math.floor(0x100000000 / max) * max;
    var arr = new Uint32Array(1);
    while (true) {
      global.crypto.getRandomValues(arr);
      if (arr[0] < limit) return arr[0] % max;
    }
  }
  function genPassword(opts) {
    opts = opts || {};
    if (opts.mode === 'passphrase') {
      var words = Math.max(3, Math.min(8, opts.words || 4));
      var picked = [];
      for (var i = 0; i < words; i++) {
        var w = WORDS[randInt(WORDS.length)];
        picked.push(w[0].toUpperCase() + w.slice(1));
      }
      picked[randInt(picked.length)] += String(randInt(90) + 10);
      return picked.join('-');
    }
    var len = Math.max(8, Math.min(64, opts.length || 20));
    var pools = [];
    if (opts.upper !== false) pools.push('ABCDEFGHIJKLMNOPQRSTUVWXYZ');
    if (opts.lower !== false) pools.push('abcdefghijklmnopqrstuvwxyz');
    if (opts.digits !== false) pools.push('0123456789');
    if (opts.symbols !== false) pools.push('!@#$%^&*()-_=+[]{}');
    if (!pools.length) pools.push('abcdefghijklmnopqrstuvwxyz0123456789');
    var all = pools.join('');
    var chars = pools.map(function (p) { return p[randInt(p.length)]; });
    while (chars.length < len) chars.push(all[randInt(all.length)]);
    for (var j = chars.length - 1; j > 0; j--) {
      var k = randInt(j + 1);
      var t = chars[j]; chars[j] = chars[k]; chars[k] = t;
    }
    return chars.join('');
  }

  // ---- 安全域名匹配（精确主机 > 根域名匹配，绝不误匹配 evilgithub.com）----
  var MULTI_TLDS = { 'co.uk':1,'com.cn':1,'net.cn':1,'org.cn':1,'gov.cn':1,'com.hk':1,'com.tw':1,'co.jp':1,'com.au':1 };
  function extractHost(rawUrl) {
    var s = String(rawUrl || '').trim();
    if (!s) return '';
    if (!/^https?:\/\//i.test(s)) s = 'https://' + s;
    try { return new URL(s).hostname.toLowerCase().replace(/^www\./, ''); }
    catch (_) { return ''; }
  }
  function baseDomain(host) {
    if (!host) return '';
    if (/^\d+\.\d+\.\d+\.\d+$/.test(host) || host === 'localhost' || host.indexOf(':') >= 0) return host;
    var parts = host.split('.');
    if (parts.length <= 2) return host;
    var tail2 = parts.slice(-2).join('.');
    if (MULTI_TLDS[tail2] && parts.length >= 3) return parts.slice(-3).join('.');
    return tail2;
  }
  function matchScore(itemUrl, pageUrl) {
    var ih = extractHost(itemUrl);
    var ph = extractHost(pageUrl);
    if (!ih || !ph) return 0;
    if (ih === ph) return 3;
    var ib = baseDomain(ih), pb = baseDomain(ph);
    if (ib && ib === pb) return 2;
    return 0;
  }

  var exp = {
    DEFAULT_ITERS: DEFAULT_ITERS,
    b64Encode: b64Encode,
    b64Decode: b64Decode,
    randBytes: randBytes,
    makeId: makeId,
    deriveKeyBytes: deriveKeyBytes,
    encryptVault: encryptVault,
    decryptVault: decryptVault,
    totpCode: totpCode,
    genPassword: genPassword,
    extractHost: extractHost,
    baseDomain: baseDomain,
    matchScore: matchScore,
  };
  global.VaultExtCrypto = exp;
  if (typeof module !== 'undefined' && module.exports) module.exports = exp;
})(typeof self !== 'undefined' ? self : globalThis);
