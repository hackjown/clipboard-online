/* Clipboard Online — 端到端加密密码保险箱（类 1Password）
 * 加密规范 v1：
 *   - KDF：PBKDF2-HMAC-SHA256，随机 16 字节 salt，默认 200,000 次迭代，输出 256 位密钥
 *   - 加密：AES-256-GCM，每次保存生成全新 12 字节随机 IV，密文末尾附 16 字节认证标签
 *   - 优先使用浏览器原生 WebCrypto（HTTPS / localhost）；局域网明文 HTTP 下自动回退到同规范纯 JS 实现
 *   - 服务端仅存储密文信封，绝不接触主密码与任何明文；所有内容严格用 textContent 渲染
 */
(function (global) {
  'use strict';

  var DEFAULT_ITERS = 200000;
  var AUTO_LOCK_MS = 15 * 60 * 1000;
  var CLIP_CLEAR_MS = 30 * 1000;
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
  function hasSubtle() {
    return !!(global.crypto && global.crypto.subtle);
  }

  // ==================== 纯 JS 密码学原语（SHA-1 / SHA-256 / PBKDF2 / AES-256-GCM）====================
  // SHA-1（用于 RFC 6238 TOTP）
  function sha1(msg) {
    var len = msg.length;
    var bitLen = len * 8;
    var padLen = ((len + 9 + 63) & ~63);
    var buf = new Uint8Array(padLen);
    buf.set(msg);
    buf[len] = 0x80;
    var dv = new DataView(buf.buffer);
    dv.setUint32(padLen - 8, Math.floor(bitLen / 0x100000000), false);
    dv.setUint32(padLen - 4, bitLen >>> 0, false);
    var h0 = 0x67452301, h1 = 0xefcdab89, h2 = 0x98badcfe, h3 = 0x10325476, h4 = 0xc3d2e1f0;
    var w = new Int32Array(80);
    for (var i = 0; i < padLen; i += 64) {
      for (var t = 0; t < 16; t++) w[t] = dv.getInt32(i + t * 4, false);
      for (var t2 = 16; t2 < 80; t2++) {
        var v = w[t2 - 3] ^ w[t2 - 8] ^ w[t2 - 14] ^ w[t2 - 16];
        w[t2] = (v << 1) | (v >>> 31);
      }
      var a = h0, b = h1, c = h2, d = h3, e = h4;
      for (var j = 0; j < 80; j++) {
        var f, k;
        if (j < 20) { f = (b & c) | ((~b) & d); k = 0x5a827999; }
        else if (j < 40) { f = b ^ c ^ d; k = 0x6ed9eba1; }
        else if (j < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc; }
        else { f = b ^ c ^ d; k = 0xca62c1d6; }
        var temp = (((a << 5) | (a >>> 27)) + f + e + k + w[j]) | 0;
        e = d; d = c; c = (b << 30) | (b >>> 2); b = a; a = temp;
      }
      h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0; h4 = (h4 + e) | 0;
    }
    var out = new Uint8Array(20);
    var odv = new DataView(out.buffer);
    odv.setUint32(0, h0 >>> 0, false); odv.setUint32(4, h1 >>> 0, false);
    odv.setUint32(8, h2 >>> 0, false); odv.setUint32(12, h3 >>> 0, false); odv.setUint32(16, h4 >>> 0, false);
    return out;
  }

  // SHA-256（用于 TOTP-SHA256 及纯 JS PBKDF2 回退）
  var K256 = new Uint32Array([
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
  ]);
  function sha256(msg) {
    var len = msg.length;
    var bitLen = len * 8;
    var padLen = ((len + 9 + 63) & ~63);
    var buf = new Uint8Array(padLen);
    buf.set(msg);
    buf[len] = 0x80;
    var dv = new DataView(buf.buffer);
    dv.setUint32(padLen - 8, Math.floor(bitLen / 0x100000000), false);
    dv.setUint32(padLen - 4, bitLen >>> 0, false);
    var h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
    var h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;
    var w = new Uint32Array(64);
    for (var i = 0; i < padLen; i += 64) {
      for (var t = 0; t < 16; t++) w[t] = dv.getUint32(i + t * 4, false);
      for (var t2 = 16; t2 < 64; t2++) {
        var s0 = ((w[t2 - 15] >>> 7) | (w[t2 - 15] << 25)) ^ ((w[t2 - 15] >>> 18) | (w[t2 - 15] << 14)) ^ (w[t2 - 15] >>> 3);
        var s1 = ((w[t2 - 2] >>> 17) | (w[t2 - 2] << 15)) ^ ((w[t2 - 2] >>> 19) | (w[t2 - 2] << 13)) ^ (w[t2 - 2] >>> 10);
        w[t2] = (w[t2 - 16] + s0 + w[t2 - 7] + s1) >>> 0;
      }
      var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
      for (var j = 0; j < 64; j++) {
        var S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7));
        var ch = (e & f) ^ ((~e) & g);
        var temp1 = (h + S1 + ch + K256[j] + w[j]) >>> 0;
        var S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10));
        var maj = (a & b) ^ (a & c) ^ (b & c);
        var temp2 = (S0 + maj) >>> 0;
        h = g; g = f; f = e; e = (d + temp1) >>> 0;
        d = c; c = b; b = a; a = (temp1 + temp2) >>> 0;
      }
      h0 = (h0 + a) >>> 0; h1 = (h1 + b) >>> 0; h2 = (h2 + c) >>> 0; h3 = (h3 + d) >>> 0;
      h4 = (h4 + e) >>> 0; h5 = (h5 + f) >>> 0; h6 = (h6 + g) >>> 0; h7 = (h7 + h) >>> 0;
    }
    var out = new Uint8Array(32);
    var odv = new DataView(out.buffer);
    odv.setUint32(0, h0, false); odv.setUint32(4, h1, false); odv.setUint32(8, h2, false); odv.setUint32(12, h3, false);
    odv.setUint32(16, h4, false); odv.setUint32(20, h5, false); odv.setUint32(24, h6, false); odv.setUint32(28, h7, false);
    return out;
  }

  function hmac(hashFn, blockSize, keyBytes, msgBytes) {
    var k = keyBytes.length > blockSize ? hashFn(keyBytes) : keyBytes;
    var ipad = new Uint8Array(blockSize + msgBytes.length);
    var opad = new Uint8Array(blockSize + (hashFn === sha1 ? 20 : 32));
    for (var i = 0; i < blockSize; i++) {
      var kb = i < k.length ? k[i] : 0;
      ipad[i] = kb ^ 0x36;
      opad[i] = kb ^ 0x5c;
    }
    ipad.set(msgBytes, blockSize);
    opad.set(hashFn(ipad), blockSize);
    return hashFn(opad);
  }

  function pbkdf2Sha256Js(passwordBytes, saltBytes, iterations) {
    var block = new Uint8Array(saltBytes.length + 4);
    block.set(saltBytes);
    block[saltBytes.length + 3] = 1;
    var u = hmac(sha256, 64, passwordBytes, block);
    var out = new Uint8Array(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac(sha256, 64, passwordBytes, u);
      for (var j = 0; j < 32; j++) out[j] ^= u[j];
    }
    return out;
  }

  // AES-256 (FIPS 197) + GCM (NIST SP 800-38D) 纯 JS 回退
  var SBOX = new Uint8Array([
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
  ]);
  var RCON = new Uint8Array([0x00,0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36]);
  function xtime(a) { return ((a << 1) ^ (a & 0x80 ? 0x1b : 0)) & 0xff; }
  function aes256Expand(key) {
    var w = new Uint8Array(240);
    w.set(key);
    var rconI = 1;
    for (var i = 32; i < 240; i += 4) {
      var t0 = w[i - 4], t1 = w[i - 3], t2 = w[i - 2], t3 = w[i - 1];
      if ((i & 31) === 0) {
        var tmp = t0;
        t0 = SBOX[t1] ^ RCON[rconI++];
        t1 = SBOX[t2];
        t2 = SBOX[t3];
        t3 = SBOX[tmp];
      } else if ((i & 31) === 16) {
        t0 = SBOX[t0]; t1 = SBOX[t1]; t2 = SBOX[t2]; t3 = SBOX[t3];
      }
      w[i] = w[i - 32] ^ t0; w[i + 1] = w[i - 31] ^ t1; w[i + 2] = w[i - 30] ^ t2; w[i + 3] = w[i - 29] ^ t3;
    }
    return w;
  }
  function aes256EncryptBlock(rk, inp) {
    var s = new Uint8Array(16);
    for (var i = 0; i < 16; i++) s[i] = inp[i] ^ rk[i];
    for (var r = 1; r <= 14; r++) {
      // SubBytes + ShiftRows
      var t = new Uint8Array(16);
      t[0] = SBOX[s[0]]; t[1] = SBOX[s[5]]; t[2] = SBOX[s[10]]; t[3] = SBOX[s[15]];
      t[4] = SBOX[s[4]]; t[5] = SBOX[s[9]]; t[6] = SBOX[s[14]]; t[7] = SBOX[s[3]];
      t[8] = SBOX[s[8]]; t[9] = SBOX[s[13]]; t[10] = SBOX[s[2]]; t[11] = SBOX[s[7]];
      t[12] = SBOX[s[12]]; t[13] = SBOX[s[1]]; t[14] = SBOX[s[6]]; t[15] = SBOX[s[11]];
      if (r < 14) {
        for (var c = 0; c < 16; c += 4) {
          var a0 = t[c], a1 = t[c + 1], a2 = t[c + 2], a3 = t[c + 3];
          var u = a0 ^ a1 ^ a2 ^ a3;
          s[c] = a0 ^ u ^ xtime(a0 ^ a1);
          s[c + 1] = a1 ^ u ^ xtime(a1 ^ a2);
          s[c + 2] = a2 ^ u ^ xtime(a2 ^ a3);
          s[c + 3] = a3 ^ u ^ xtime(a3 ^ a0);
        }
      } else {
        s = t;
      }
      var off = r * 16;
      for (var k = 0; k < 16; k++) s[k] ^= rk[off + k];
    }
    return s;
  }
  function gfMul(x, y) {
    var z = new Uint8Array(16);
    var v = new Uint8Array(y);
    for (var i = 0; i < 16; i++) {
      var xi = x[i];
      for (var b = 7; b >= 0; b--) {
        if ((xi >> b) & 1) {
          for (var j = 0; j < 16; j++) z[j] ^= v[j];
        }
        var lsb = v[15] & 1;
        for (var j2 = 15; j2 > 0; j2--) v[j2] = (v[j2] >>> 1) | ((v[j2 - 1] & 1) << 7);
        v[0] >>>= 1;
        if (lsb) v[0] ^= 0xe1;
      }
    }
    return z;
  }
  function ghash(H, ct) {
    var y = new Uint8Array(16);
    for (var i = 0; i < ct.length; i += 16) {
      var end = Math.min(i + 16, ct.length);
      for (var j = 0; j < end - i; j++) y[j] ^= ct[i + j];
      y = gfMul(y, H);
    }
    // 64-bit AAD length (0) || 64-bit CT length in bits
    var lenBlk = new Uint8Array(16);
    var dv = new DataView(lenBlk.buffer);
    var bits = ct.length * 8;
    dv.setUint32(8, Math.floor(bits / 0x100000000), false);
    dv.setUint32(12, bits >>> 0, false);
    for (var k = 0; k < 16; k++) y[k] ^= lenBlk[k];
    return gfMul(y, H);
  }
  function gctr(rk, icb, inp) {
    var out = new Uint8Array(inp.length);
    var cb = new Uint8Array(icb);
    var dv = new DataView(cb.buffer);
    for (var i = 0; i < inp.length; i += 16) {
      var ks = aes256EncryptBlock(rk, cb);
      var n = Math.min(16, inp.length - i);
      for (var j = 0; j < n; j++) out[i + j] = inp[i + j] ^ ks[j];
      dv.setUint32(12, (dv.getUint32(12, false) + 1) >>> 0, false);
    }
    return out;
  }
  function aesGcmEncryptJs(keyBytes, iv12, plainBytes) {
    var rk = aes256Expand(keyBytes);
    var H = aes256EncryptBlock(rk, new Uint8Array(16));
    var j0 = new Uint8Array(16);
    j0.set(iv12, 0);
    j0[15] = 1;
    var icb = new Uint8Array(j0);
    icb[15] = 2;
    var ct = gctr(rk, icb, plainBytes);
    var s = ghash(H, ct);
    var tag = gctr(rk, j0, s);
    var out = new Uint8Array(ct.length + 16);
    out.set(ct, 0);
    out.set(tag, ct.length);
    return out;
  }
  function aesGcmDecryptJs(keyBytes, iv12, ctTagBytes) {
    if (ctTagBytes.length < 16) throw new Error('密文损坏');
    var ct = ctTagBytes.subarray(0, ctTagBytes.length - 16);
    var tag = ctTagBytes.subarray(ctTagBytes.length - 16);
    var rk = aes256Expand(keyBytes);
    var H = aes256EncryptBlock(rk, new Uint8Array(16));
    var j0 = new Uint8Array(16);
    j0.set(iv12, 0);
    j0[15] = 1;
    var s = ghash(H, ct);
    var expected = gctr(rk, j0, s);
    var diff = 0;
    for (var i = 0; i < 16; i++) diff |= (tag[i] ^ expected[i]);
    if (diff !== 0) throw new Error('主密码错误或数据已被篡改');
    var icb = new Uint8Array(j0);
    icb[15] = 2;
    return gctr(rk, icb, ct);
  }

  // ==================== 统一加密接口（优先 WebCrypto，HTTP 回退纯 JS）====================
  async function deriveKey(password, saltBytes, iterations, forceJs) {
    var pwBytes = te.encode(password);
    if (!forceJs && hasSubtle()) {
      var baseKey = await global.crypto.subtle.importKey('raw', pwBytes, 'PBKDF2', false, ['deriveKey']);
      var aesKey = await global.crypto.subtle.deriveKey(
        { name: 'PBKDF2', salt: saltBytes, iterations: iterations, hash: 'SHA-256' },
        baseKey,
        { name: 'AES-GCM', length: 256 },
        false,
        ['encrypt', 'decrypt']
      );
      return { mode: 'subtle', key: aesKey };
    }
    return { mode: 'js', key: pbkdf2Sha256Js(pwBytes, saltBytes, iterations) };
  }

  async function encryptVault(payloadObj, keyHandle, saltBytes, iterations) {
    var iv = randBytes(12);
    var plain = te.encode(JSON.stringify(payloadObj));
    var ct;
    if (keyHandle.mode === 'subtle') {
      var buf = await global.crypto.subtle.encrypt({ name: 'AES-GCM', iv: iv }, keyHandle.key, plain);
      ct = new Uint8Array(buf);
    } else {
      ct = aesGcmEncryptJs(keyHandle.key, iv, plain);
    }
    return {
      version: 1,
      kdf: 'PBKDF2-SHA256',
      iterations: iterations,
      salt: b64Encode(saltBytes),
      iv: b64Encode(iv),
      ct: b64Encode(ct),
      item_count: (payloadObj.items || []).length,
    };
  }

  async function decryptVault(envelope, keyHandle) {
    var iv = b64Decode(envelope.iv);
    var ct = b64Decode(envelope.ct);
    var plain;
    if (keyHandle.mode === 'subtle') {
      try {
        var buf = await global.crypto.subtle.decrypt({ name: 'AES-GCM', iv: iv }, keyHandle.key, ct);
        plain = new Uint8Array(buf);
      } catch (_) {
        throw new Error('主密码错误或数据已被篡改');
      }
    } else {
      plain = aesGcmDecryptJs(keyHandle.key, iv, ct);
    }
    var obj = JSON.parse(td.decode(plain));
    if (!obj || typeof obj !== 'object' || !Array.isArray(obj.items)) {
      throw new Error('密码库数据结构异常');
    }
    return obj;
  }

  // ==================== TOTP（RFC 6238，支持 otpauth:// 与裸 Base32）====================
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
      if (bits >= 8) {
        bits -= 8;
        out.push((val >>> bits) & 0xff);
      }
    }
    return out.length ? new Uint8Array(out) : null;
  }
  function parseOtp(raw) {
    var s = String(raw || '').trim();
    if (!s) return null;
    var secret = s, digits = 6, period = 30, algo = 'SHA1';
    if (/^otpauth:\/\//i.test(s)) {
      try {
        var u = new URL(s);
        secret = u.searchParams.get('secret') || '';
        digits = parseInt(u.searchParams.get('digits') || '6', 10) || 6;
        period = parseInt(u.searchParams.get('period') || '30', 10) || 30;
        algo = (u.searchParams.get('algorithm') || 'SHA1').toUpperCase();
      } catch (_) { return null; }
    }
    var key = base32Decode(secret);
    if (!key) return null;
    digits = Math.max(6, Math.min(8, digits));
    period = Math.max(10, Math.min(120, period));
    return { key: key, digits: digits, period: period, algo: algo };
  }
  function totpCode(raw, nowSec) {
    var cfg = parseOtp(raw);
    if (!cfg) return null;
    var t = nowSec != null ? nowSec : Math.floor(Date.now() / 1000);
    var counter = Math.floor(t / cfg.period);
    var msg = new Uint8Array(8);
    var dv = new DataView(msg.buffer);
    dv.setUint32(0, Math.floor(counter / 0x100000000), false);
    dv.setUint32(4, counter >>> 0, false);
    var mac = cfg.algo === 'SHA256' ? hmac(sha256, 64, cfg.key, msg) : hmac(sha1, 64, cfg.key, msg);
    var off = mac[mac.length - 1] & 0x0f;
    var bin = ((mac[off] & 0x7f) << 24) | ((mac[off + 1] & 0xff) << 16) | ((mac[off + 2] & 0xff) << 8) | (mac[off + 3] & 0xff);
    var mod = Math.pow(10, cfg.digits);
    var code = String(bin % mod);
    while (code.length < cfg.digits) code = '0' + code;
    return { code: code, remaining: cfg.period - (t % cfg.period), period: cfg.period, digits: cfg.digits };
  }

  // ==================== 强密码生成器 ====================
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
      var sep = opts.sep != null ? String(opts.sep) : '-';
      var picked = [];
      for (var i = 0; i < words; i++) {
        var w = WORDS[randInt(WORDS.length)];
        if (opts.capitalize !== false) w = w[0].toUpperCase() + w.slice(1);
        picked.push(w);
      }
      if (opts.addNumber !== false) picked[randInt(picked.length)] += String(randInt(90) + 10);
      return picked.join(sep);
    }
    var len = Math.max(8, Math.min(64, opts.length || 20));
    var pools = [];
    var noAmb = !!opts.noAmbiguous;
    var strip = function (s) { return noAmb ? s.replace(/[Il1O0]/g, '') : s; };
    if (opts.upper !== false) pools.push(strip('ABCDEFGHIJKLMNOPQRSTUVWXYZ'));
    if (opts.lower !== false) pools.push(strip('abcdefghijklmnopqrstuvwxyz'));
    if (opts.digits !== false) pools.push(strip('0123456789'));
    if (opts.symbols !== false) pools.push('!@#$%^&*()-_=+[]{}');
    if (!pools.length) pools.push('abcdefghijklmnopqrstuvwxyz0123456789');
    var all = pools.join('');
    var chars = [];
    pools.forEach(function (p) { if (chars.length < len) chars.push(p[randInt(p.length)]); });
    while (chars.length < len) chars.push(all[randInt(all.length)]);
    for (var j = chars.length - 1; j > 0; j--) {
      var k = randInt(j + 1);
      var tmp = chars[j]; chars[j] = chars[k]; chars[k] = tmp;
    }
    return chars.join('');
  }
  function passwordStrength(pw) {
    if (!pw) return { score: 0, label: '空', cls: 'weak' };
    var pool = 0;
    if (/[a-z]/.test(pw)) pool += 26;
    if (/[A-Z]/.test(pw)) pool += 26;
    if (/[0-9]/.test(pw)) pool += 10;
    if (/[^a-zA-Z0-9]/.test(pw)) pool += 32;
    var bits = pw.length * Math.log2(Math.max(pool, 2));
    if (bits < 40) return { score: 1, label: '偏弱', cls: 'weak' };
    if (bits < 60) return { score: 2, label: '一般', cls: 'fair' };
    if (bits < 80) return { score: 3, label: '较强', cls: 'good' };
    return { score: 4, label: '极强', cls: 'strong' };
  }

  // ==================== 1Password / Bitwarden / CSV 导入解析 ====================
  function makeId() {
    var b = randBytes(16);
    var hex = '';
    for (var i = 0; i < 16; i++) hex += (b[i] < 16 ? '0' : '') + b[i].toString(16);
    return hex;
  }
  function parseCsvRows(text) {
    var rows = [], row = [], cur = '', inQ = false;
    var s = String(text || '').replace(/^\uFEFF/, '');
    for (var i = 0; i < s.length; i++) {
      var ch = s[i];
      if (inQ) {
        if (ch === '"') {
          if (s[i + 1] === '"') { cur += '"'; i++; }
          else inQ = false;
        } else cur += ch;
      } else {
        if (ch === '"') inQ = true;
        else if (ch === ',') { row.push(cur); cur = ''; }
        else if (ch === '\r') { if (s[i + 1] === '\n') i++; row.push(cur); rows.push(row); row = []; cur = ''; }
        else if (ch === '\n') { row.push(cur); rows.push(row); row = []; cur = ''; }
        else cur += ch;
      }
    }
    if (cur.length || row.length) { row.push(cur); rows.push(row); }
    return rows.filter(function (r) { return r.some(function (c) { return c.trim() !== ''; }); });
  }
  function importFromCsv(text) {
    var rows = parseCsvRows(text);
    if (rows.length < 2) return [];
    var hdr = rows[0].map(function (c) { return c.trim().toLowerCase(); });
    var col = function (names) {
      for (var i = 0; i < names.length; i++) {
        var idx = hdr.indexOf(names[i]);
        if (idx >= 0) return idx;
      }
      return -1;
    };
    var iTitle = col(['title', 'name', '名称', '标题']);
    var iUrl = col(['url', 'website', 'login_uri', '网址', '网站']);
    var iUser = col(['username', 'login_username', 'user', '用户名', '账号']);
    var iPass = col(['password', 'login_password', 'pass', '密码']);
    var iOtp = col(['otpauth', 'one-time password', 'totp', 'login_totp', 'otp', '2fa', '一次性密码']);
    var iNotes = col(['notes', 'note', '备注']);
    var iTags = col(['tags', 'tag', '标签']);
    var iType = col(['type', 'category', '类型']);
    var now = Math.floor(Date.now() / 1000);
    var out = [];
    for (var r = 1; r < rows.length; r++) {
      var cells = rows[r];
      var get = function (idx) { return idx >= 0 && idx < cells.length ? cells[idx].trim() : ''; };
      var title = get(iTitle) || get(iUrl) || get(iUser) || ('条目 ' + r);
      var rawType = get(iType).toLowerCase();
      var kind = 'login';
      if (rawType.indexOf('note') >= 0 || rawType.indexOf('笔记') >= 0) kind = 'note';
      else if (rawType.indexOf('card') >= 0 || rawType.indexOf('卡') >= 0) kind = 'card';
      else if (rawType.indexOf('api') >= 0 || rawType.indexOf('key') >= 0 || rawType.indexOf('密钥') >= 0) kind = 'apikey';
      else if (!get(iUser) && !get(iPass) && !get(iUrl) && get(iNotes)) kind = 'note';
      var tagsRaw = get(iTags);
      var tags = tagsRaw ? tagsRaw.split(/[;,，]/).map(function (x) { return x.trim(); }).filter(Boolean).slice(0, 8) : [];
      out.push({
        id: makeId(), kind: kind, title: title, username: get(iUser), password: get(iPass),
        url: get(iUrl), totp: get(iOtp), notes: get(iNotes), fields: [], tags: tags,
        favorite: false, created_at: now, updated_at: now,
      });
    }
    return out;
  }
  function importFrom1PuxData(data) {
    var out = [], now = Math.floor(Date.now() / 1000);
    (data.accounts || []).forEach(function (acc) {
      (acc.vaults || []).forEach(function (v) {
        (v.items || []).forEach(function (it) {
          if (it.state && it.state !== 'active') return;
          var ov = it.overview || {};
          var det = it.details || {};
          var user = '', pass = '', totp = '', fields = [];
          (det.loginFields || []).forEach(function (f) {
            if (f.designation === 'username' && !user) user = f.value || '';
            else if (f.designation === 'password' && !pass) pass = f.value || '';
            else if (f.value) fields.push({ label: f.name || f.id || '字段', value: String(f.value), secret: f.fieldType === 'P' });
          });
          (det.sections || []).forEach(function (sec) {
            (sec.fields || []).forEach(function (f) {
              var val = f.value || {};
              if (val.totp && !totp) totp = String(val.totp);
              else if (val.concealed != null) fields.push({ label: f.title || '机密', value: String(val.concealed), secret: true });
              else if (val.string != null && val.string !== '') fields.push({ label: f.title || '字段', value: String(val.string), secret: false });
              else if (val.url != null && val.url !== '') fields.push({ label: f.title || '链接', value: String(val.url), secret: false });
            });
          });
          var cat = String(it.categoryUuid || '');
          var kind = cat === '003' ? 'note' : (cat === '002' ? 'card' : (cat === '112' ? 'apikey' : 'login'));
          var url = ov.url || ((ov.urls && ov.urls[0] && ov.urls[0].url) || '');
          out.push({
            id: makeId(), kind: kind, title: ov.title || url || '未命名条目',
            username: user, password: pass, url: url, totp: totp,
            notes: det.notesPlain || '', fields: fields,
            tags: Array.isArray(ov.tags) ? ov.tags.map(String).slice(0, 8) : [],
            favorite: it.favIndex > 0, created_at: it.createdAt || now, updated_at: it.updatedAt || now,
          });
        });
      });
    });
    return out;
  }
  function importFromBitwardenJson(obj) {
    var out = [], now = Math.floor(Date.now() / 1000);
    (obj.items || []).forEach(function (it) {
      var lg = it.login || {};
      var kind = it.type === 2 ? 'note' : (it.type === 3 ? 'card' : 'login');
      var url = (lg.uris && lg.uris[0] && lg.uris[0].uri) || '';
      var fields = (it.fields || []).map(function (f) {
        return { label: f.name || '字段', value: String(f.value || ''), secret: f.type === 1 };
      });
      out.push({
        id: makeId(), kind: kind, title: it.name || url || '未命名条目',
        username: lg.username || '', password: lg.password || '', url: url,
        totp: lg.totp || '', notes: it.notes || '', fields: fields, tags: [],
        favorite: !!it.favorite, created_at: now, updated_at: now,
      });
    });
    return out;
  }
  // 极简 ZIP 读取器（支持 1Password .1pux 内的 export.data，使用浏览器原生 DecompressionStream）
  async function extractZipFile(arrayBuf, targetName) {
    var bytes = new Uint8Array(arrayBuf);
    var dv = new DataView(arrayBuf);
    var eocd = -1;
    for (var i = bytes.length - 22; i >= Math.max(0, bytes.length - 65558); i--) {
      if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
    }
    if (eocd < 0) throw new Error('不是有效的 .1pux (ZIP) 文件');
    var cdOff = dv.getUint32(eocd + 16, true);
    var cdCount = dv.getUint16(eocd + 10, true);
    var pos = cdOff;
    for (var n = 0; n < cdCount; n++) {
      if (dv.getUint32(pos, true) !== 0x02014b50) break;
      var method = dv.getUint16(pos + 10, true);
      var compSz = dv.getUint32(pos + 20, true);
      var nameLen = dv.getUint16(pos + 28, true);
      var extraLen = dv.getUint16(pos + 30, true);
      var commLen = dv.getUint16(pos + 32, true);
      var locOff = dv.getUint32(pos + 42, true);
      var name = td.decode(bytes.subarray(pos + 46, pos + 46 + nameLen));
      pos += 46 + nameLen + extraLen + commLen;
      if (name === targetName) {
        var lName = dv.getUint16(locOff + 26, true);
        var lExtra = dv.getUint16(locOff + 28, true);
        var start = locOff + 30 + lName + lExtra;
        var slice = bytes.subarray(start, start + compSz);
        if (method === 0) return td.decode(slice);
        if (method === 8) {
          if (typeof DecompressionStream === 'undefined') throw new Error('当前浏览器不支持解压 .1pux，请导出为 CSV 后导入');
          var ds = new DecompressionStream('deflate-raw');
          var resp = new Response(new Blob([slice]).stream().pipeThrough(ds));
          return await resp.text();
        }
        throw new Error('不支持的 ZIP 压缩方式：' + method);
      }
    }
    throw new Error('压缩包中未找到 ' + targetName);
  }

  // ==================== Vault UI（纸与墨主题，全部 textContent 安全渲染）====================
  var KIND_LABEL = { login: '登录', note: '安全笔记', card: '银行卡片', idcard: '证件资料', apikey: 'API 密钥' };
  var KIND_BADGE = { login: '🔑', note: '📝', card: '💳', idcard: '🪪', apikey: '⚡' };

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function safeHref(url) {
    var s = String(url || '').trim();
    if (!s) return null;
    if (/^https?:\/\//i.test(s)) return s;
    if (/^[a-z0-9.-]+\.[a-z]{2,}(\/|$)/i.test(s)) return 'https://' + s;
    return null;
  }

  var ui = null; // 当前打开的模态状态

  function closeModal() {
    if (!ui) return;
    if (ui.totpTimer) clearInterval(ui.totpTimer);
    if (ui.lockTimer) clearTimeout(ui.lockTimer);
    document.removeEventListener('keydown', ui.onKey, true);
    // 清理内存中的密钥与明文
    ui.keyHandle = null;
    ui.data = null;
    ui.root.remove();
    document.body.classList.remove('pv-open');
    ui = null;
  }

  function resetAutoLock() {
    if (!ui) return;
    if (ui.lockTimer) clearTimeout(ui.lockTimer);
    if (ui.keyHandle) {
      ui.lockTimer = setTimeout(function () {
        if (!ui || !ui.keyHandle) return;
        ui.keyHandle = null;
        ui.data = null;
        ui.selectedId = null;
        ui.toast('长时间未操作，密码库已自动锁定');
        renderUnlock();
      }, AUTO_LOCK_MS);
    }
  }

  var clearClipTimer = null;
  var lastSecretCopied = null;
  async function copySecret(text, label, isSecret) {
    if (!text) return;
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) await navigator.clipboard.writeText(text);
      else {
        var ta = document.createElement('textarea');
        ta.value = text; ta.style.cssText = 'position:fixed;opacity:0';
        document.body.append(ta); ta.select(); document.execCommand('copy'); ta.remove();
      }
      if (isSecret) {
        lastSecretCopied = text;
        if (clearClipTimer) clearTimeout(clearClipTimer);
        clearClipTimer = setTimeout(function () {
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.readText ? navigator.clipboard.readText().then(function (cur) {
              if (cur === lastSecretCopied) navigator.clipboard.writeText('').catch(function () {});
            }).catch(function () { navigator.clipboard.writeText('').catch(function () {}); })
              : navigator.clipboard.writeText('').catch(function () {});
          }
          lastSecretCopied = null;
        }, CLIP_CLEAR_MS);
        ui && ui.toast((label || '机密内容') + '已复制 · 30s 后自动清空剪贴板');
      } else {
        ui && ui.toast((label || '内容') + '已复制');
      }
    } catch (_) {
      ui && ui.toast('复制失败，请手动选中复制', 'err');
    }
  }

  async function apiReq(url, opts) {
    opts = opts || {};
    var headers = { Accept: 'application/json' };
    var body = opts.body;
    if (body !== undefined) { headers['Content-Type'] = 'application/json'; body = JSON.stringify(body); }
    var r = await fetch(url, { method: opts.method || 'GET', credentials: 'same-origin', headers: headers, body: body });
    var d = await r.json().catch(function () { return {}; });
    return { ok: r.ok, status: r.status, d: d };
  }

  async function saveToServer() {
    if (!ui || !ui.keyHandle || !ui.data) return false;
    var env = await encryptVault(ui.data, ui.keyHandle, ui.saltBytes, ui.iterations);
    env.expected_rev = ui.rev;
    var res = await apiReq('/api/vault', { method: 'PUT', body: env });
    if (res.status === 409) {
      ui.toast('密码库已在其他设备更新，请重新解锁同步后再保存', 'err');
      if (res.d && res.d.vault) { ui.envelope = res.d.vault; ui.rev = res.d.vault.rev || 0; }
      return false;
    }
    if (!res.ok) {
      ui.toast((res.d && (res.d.error || res.d.detail)) || '保存失败', 'err');
      return false;
    }
    ui.envelope = res.d.vault;
    ui.rev = res.d.vault.rev || (ui.rev + 1);
    resetAutoLock();
    return true;
  }

  function renderHead(actions) {
    ui.headRight.replaceChildren();
    (actions || []).forEach(function (a) { ui.headRight.append(a); });
    var x = el('button', 'pv-btn pv-x', '✕');
    x.type = 'button'; x.setAttribute('aria-label', '关闭');
    x.onclick = closeModal;
    ui.headRight.append(x);
  }

  function renderSetup() {
    renderHead([]);
    ui.body.replaceChildren();
    var card = el('div', 'vt-auth');
    card.append(
      el('div', 'vt-hero-ico', '🔐'),
      el('h2', null, '创建密码保险箱'),
      el('p', 'vt-lead', '类 1Password 端到端加密保险箱：账号密码、2FA 动态验证码、安全笔记仅在你的设备本地加密（PBKDF2-SHA256 + AES-256-GCM），服务器只存密文。')
    );
    if (!hasSubtle()) {
      card.append(el('p', 'vt-warn', '当前为非 HTTPS 连接，已启用纯 JS AES-256-GCM 兼容模式；生产环境建议配合 HTTPS 使用。'));
    }
    var pw1 = el('input', 'vt-in'); pw1.type = 'password'; pw1.placeholder = '设置主密码（至少 8 位）'; pw1.autocomplete = 'new-password';
    var pw2 = el('input', 'vt-in'); pw2.type = 'password'; pw2.placeholder = '再次输入主密码'; pw2.autocomplete = 'new-password';
    var strBar = el('p', 'vt-hint', '主密码不会上传到服务器，遗忘后无法找回，请妥善记忆或导出加密备份。');
    pw1.oninput = function () {
      var s = passwordStrength(pw1.value);
      strBar.textContent = pw1.value ? ('密码强度：' + s.label + '（长度 ' + pw1.value.length + '）') : '主密码不会上传到服务器，遗忘后无法找回。';
    };
    var err = el('p', 'err'); err.hidden = true;
    var btn = el('button', 'btn btn--accent', '创建并解锁'); btn.type = 'submit';
    var form = el('form', 'vt-form');
    form.append(pw1, pw2, strBar, err, btn);
    form.onsubmit = async function (e) {
      e.preventDefault();
      err.hidden = true;
      if (pw1.value.length < 8) { err.textContent = '主密码至少需要 8 个字符'; err.hidden = false; return; }
      if (pw1.value !== pw2.value) { err.textContent = '两次输入的主密码不一致'; err.hidden = false; return; }
      btn.disabled = true; btn.textContent = '正在派生密钥…';
      try {
        var salt = randBytes(16);
        var kh = await deriveKey(pw1.value, salt, DEFAULT_ITERS);
        ui.keyHandle = kh; ui.saltBytes = salt; ui.iterations = DEFAULT_ITERS; ui.rev = 0;
        ui.data = { v: 1, items: [] };
        if (await saveToServer()) {
          ui.toast('密码库已创建');
          renderVault();
        }
      } catch (ex) {
        err.textContent = ex.message || String(ex); err.hidden = false;
      } finally {
        btn.disabled = false; btn.textContent = '创建并解锁';
      }
    };
    card.append(form);
    ui.body.append(card);
    pw1.focus();
  }

  function renderUnlock() {
    if (ui.totpTimer) { clearInterval(ui.totpTimer); ui.totpTimer = null; }
    renderHead([]);
    ui.body.replaceChildren();
    var env = ui.envelope || {};
    var card = el('div', 'vt-auth');
    card.append(
      el('div', 'vt-hero-ico', '🔒'),
      el('h2', null, '解锁密码保险箱'),
      el('p', 'vt-lead', '共 ' + (env.item_count || 0) + ' 条加密记录 · 仅在本地解密，15 分钟无操作自动锁定')
    );
    if (!hasSubtle()) {
      card.append(el('p', 'vt-warn', '当前为非 HTTPS 连接，已启用纯 JS AES-256-GCM 兼容模式；首次派生密钥约需 1–2 秒。'));
    }
    var pw = el('input', 'vt-in'); pw.type = 'password'; pw.placeholder = '输入主密码'; pw.autocomplete = 'current-password';
    var err = el('p', 'err'); err.hidden = true;
    var btn = el('button', 'btn btn--accent', '解锁'); btn.type = 'submit';
    var form = el('form', 'vt-form');
    form.append(pw, err, btn);
    form.onsubmit = async function (e) {
      e.preventDefault();
      err.hidden = true;
      if (!pw.value) { err.textContent = '请输入主密码'; err.hidden = false; return; }
      btn.disabled = true; btn.textContent = '正在解密…';
      try {
        // 拉取最新密文信封
        var latest = await apiReq('/api/vault');
        if (latest.ok && latest.d.exists && latest.d.vault) {
          ui.envelope = latest.d.vault;
          ui.rev = latest.d.vault.rev || 0;
        }
        var salt = b64Decode(ui.envelope.salt);
        var iters = ui.envelope.iterations || DEFAULT_ITERS;
        var kh = await deriveKey(pw.value, salt, iters);
        var dec = await decryptVault(ui.envelope, kh);
        ui.keyHandle = kh; ui.saltBytes = salt; ui.iterations = iters;
        ui.data = dec;
        pw.value = '';
        resetAutoLock();
        renderVault();
      } catch (ex) {
        err.textContent = ex.message || '解锁失败'; err.hidden = false;
      } finally {
        btn.disabled = false; btn.textContent = '解锁';
      }
    };
    var resetBtn = el('button', 'btn btn--ghost vt-reset-btn', '忘记主密码？重置密码库');
    resetBtn.type = 'button';
    resetBtn.onclick = function () { openResetPrompt(); };
    card.append(form, resetBtn);
    ui.body.append(card);
    pw.focus();
  }

  function openResetPrompt() {
    var accPw = prompt('⚠️ 重置将永久删除云端加密密码库且无法恢复！\n请输入你的【Clipboard 账号登录密码】以确认重置：');
    if (!accPw) return;
    apiReq('/api/vault', { method: 'DELETE', body: { password: accPw } }).then(function (r) {
      if (!r.ok) { ui.toast((r.d && (r.d.error || r.d.detail)) || '重置失败', 'err'); return; }
      ui.envelope = null; ui.rev = 0; ui.data = null; ui.keyHandle = null;
      ui.toast('密码库已重置');
      renderSetup();
    });
  }

  function renderVault() {
    resetAutoLock();
    var addBtn = el('button', 'pv-btn pv-btn--acc', '+ 新建'); addBtn.type = 'button'; addBtn.onclick = function () { openEditor(null); };
    var genBtn = el('button', 'pv-btn', '🎲 生成'); genBtn.type = 'button'; genBtn.onclick = openGenerator;
    var impBtn = el('button', 'pv-btn', '导入'); impBtn.type = 'button'; impBtn.onclick = openImporter;
    var expBtn = el('button', 'pv-btn', '备份'); expBtn.type = 'button'; expBtn.onclick = exportBackup;
    var chgBtn = el('button', 'pv-btn', '改主密'); chgBtn.type = 'button'; chgBtn.onclick = openChangeMaster;
    var lockBtn = el('button', 'pv-btn', '🔒 锁定'); lockBtn.type = 'button'; lockBtn.onclick = function () {
      ui.keyHandle = null; ui.data = null; ui.selectedId = null;
      ui.toast('密码库已锁定');
      renderUnlock();
    };
    renderHead([addBtn, genBtn, impBtn, expBtn, chgBtn, lockBtn]);

    ui.body.replaceChildren();
    var wrap = el('div', 'vt-shell');
    var bar = el('div', 'vt-bar');
    var qIn = el('input', 'vt-search'); qIn.type = 'search'; qIn.placeholder = '搜索名称、账号、网址、标签…'; qIn.value = ui.q || '';
    var filters = el('div', 'vt-cats');
    var catDefs = [
      ['all', '全部'], ['login', '登录'], ['2fa', '2FA'], ['note', '笔记'],
      ['card', '卡片'], ['idcard', '证件'], ['apikey', '密钥'], ['fav', '★ 收藏']
    ];
    catDefs.forEach(function (pair) {
      var b = el('button', 'pv-tab', pair[1]);
      b.type = 'button';
      b.setAttribute('aria-selected', (ui.cat || 'all') === pair[0] ? 'true' : 'false');
      b.onclick = function () {
        ui.cat = pair[0];
        Array.from(filters.children).forEach(function (c, i) { c.setAttribute('aria-selected', catDefs[i][0] === ui.cat ? 'true' : 'false'); });
        drawList();
      };
      filters.append(b);
    });
    bar.append(qIn, filters);

    var split = el('div', 'vt-split');
    var listPane = el('div', 'vt-list');
    var detailPane = el('div', 'vt-detail');
    split.append(listPane, detailPane);
    wrap.append(bar, split);
    ui.body.append(wrap);

    qIn.oninput = function () { ui.q = qIn.value.trim().toLowerCase(); drawList(); };

    function filteredItems() {
      var items = (ui.data && ui.data.items) || [];
      return items.filter(function (it) {
        var c = ui.cat || 'all';
        if (c === 'fav' && !it.favorite) return false;
        if (c === '2fa' && !it.totp) return false;
        if (c !== 'all' && c !== 'fav' && c !== '2fa' && (it.kind || 'login') !== c) return false;
        if (!ui.q) return true;
        var hay = [it.title, it.username, it.url, it.notes, (it.tags || []).join(' ')].join(' ').toLowerCase();
        return hay.indexOf(ui.q) >= 0;
      }).sort(function (a, b) {
        return (!!b.favorite - !!a.favorite) || ((b.updated_at || 0) - (a.updated_at || 0));
      });
    }

    function drawList() {
      var items = filteredItems();
      listPane.replaceChildren();
      if (!items.length) {
        listPane.append(el('p', 'vt-empty', ui.data.items.length ? '没有匹配的条目' : '密码库还是空的，点右上角「+ 新建」或「导入」添加第一条记录（支持 1Password CSV / .1pux）。'));
        if (!ui.selectedId) drawDetail(null);
        return;
      }
      var sel = items.find(function (x) { return x.id === ui.selectedId; }) || items[0];
      ui.selectedId = sel.id;
      items.forEach(function (it) {
        var row = el('div', 'vt-item' + (it.id === ui.selectedId ? ' on' : ''));
        row.onclick = function () {
          resetAutoLock();
          ui.selectedId = it.id;
          Array.from(listPane.children).forEach(function (n) { n.classList.remove('on'); });
          row.classList.add('on');
          drawDetail(it);
        };
        var av = el('span', 'vt-av', KIND_BADGE[it.kind || 'login'] || '🔑');
        var mid = el('div', 'vt-mid');
        var tLine = el('div', 'vt-it-t', (it.favorite ? '★ ' : '') + (it.title || '未命名'));
        var sub = el('div', 'vt-it-s', it.username || it.url || (KIND_LABEL[it.kind] || ''));
        mid.append(tLine, sub);
        var quick = el('div', 'vt-quick');
        if (it.totp) {
          var otp = totpCode(it.totp);
          if (otp) {
            var ob = el('button', 'vt-otp-pill', otp.code.slice(0, 3) + ' ' + otp.code.slice(3));
            ob.type = 'button'; ob.title = '点击复制验证码'; ob.dataset.totpRaw = it.totp;
            ob.onclick = function (e) { e.stopPropagation(); var cur = totpCode(it.totp); if (cur) copySecret(cur.code, '验证码', true); };
            quick.append(ob);
          }
        }
        if (it.password) {
          var cp = el('button', 'vt-mini', '密码');
          cp.type = 'button'; cp.title = '安全复制密码';
          cp.onclick = function (e) { e.stopPropagation(); copySecret(it.password, '密码', true); };
          quick.append(cp);
        }
        row.append(av, mid, quick);
        listPane.append(row);
      });
      drawDetail(sel);
    }

    function drawDetail(it) {
      detailPane.replaceChildren();
      if (!it) {
        detailPane.append(el('p', 'vt-empty', '选择左侧条目查看详情'));
        return;
      }
      var top = el('div', 'vt-det-head');
      var titleBox = el('div', 'vt-det-tb');
      titleBox.append(
        el('span', 'vt-kind-chip', (KIND_BADGE[it.kind] || '🔑') + ' ' + (KIND_LABEL[it.kind] || '登录')),
        el('h3', 'vt-det-title', it.title || '未命名')
      );
      var acts = el('div', 'vt-det-acts');
      var favBtn = el('button', 'btn sm', it.favorite ? '★ 已收藏' : '☆ 收藏');
      favBtn.type = 'button';
      favBtn.onclick = async function () {
        it.favorite = !it.favorite; it.updated_at = Math.floor(Date.now() / 1000);
        if (await saveToServer()) drawList();
      };
      var editBtn = el('button', 'btn sm', '编辑');
      editBtn.type = 'button';
      editBtn.onclick = function () { openEditor(it); };
      var delBtn = el('button', 'btn sm btn--danger', '删除');
      delBtn.type = 'button';
      delBtn.onclick = async function () {
        if (!confirm('确认删除「' + (it.title || '此条目') + '」？')) return;
        ui.data.items = ui.data.items.filter(function (x) { return x.id !== it.id; });
        ui.selectedId = null;
        if (await saveToServer()) { ui.toast('已删除'); drawList(); }
      };
      acts.append(favBtn, editBtn, delBtn);
      top.append(titleBox, acts);
      detailPane.append(top);

      function addFieldRow(label, value, opts) {
        opts = opts || {};
        if (!value) return;
        var row = el('div', 'vt-frow');
        row.append(el('div', 'vt-flbl', label));
        var valLine = el('div', 'vt-fval');
        var txt;
        if (opts.link) {
          var href = safeHref(value);
          if (href) {
            txt = el('a', 'vt-link', value); txt.href = href; txt.target = '_blank'; txt.rel = 'noopener noreferrer';
          } else txt = el('span', 'vt-txt', value);
        } else {
          txt = el('span', 'vt-txt' + (opts.mono ? ' mono' : ''), opts.secret ? '••••••••••••' : value);
        }
        valLine.append(txt);
        var btns = el('div', 'vt-fbtns');
        if (opts.secret) {
          var shown = false;
          var tog = el('button', 'vt-mini', '显示');
          tog.type = 'button';
          tog.onclick = function () { shown = !shown; txt.textContent = shown ? value : '••••••••••••'; tog.textContent = shown ? '隐藏' : '显示'; };
          btns.append(tog);
        }
        var cp = el('button', 'vt-mini', '复制');
        cp.type = 'button';
        cp.onclick = function () { copySecret(value, label, !!opts.secret); };
        btns.append(cp);
        valLine.append(btns);
        row.append(valLine);
        detailPane.append(row);
      }

      if (it.kind === 'card') {
        addFieldRow('持卡人姓名', it.username, { mono: false });
        addFieldRow('卡号', it.password, { secret: true, mono: true });
      } else if (it.kind === 'idcard') {
        addFieldRow('姓名 / 持有人', it.username, { mono: false });
        addFieldRow('证件号码', it.password, { secret: true, mono: true });
      } else if (it.kind === 'apikey') {
        addFieldRow('Key ID / 标识', it.username, { mono: true });
        addFieldRow('API 密钥 / Token', it.password, { secret: true, mono: true });
        addFieldRow('接口地址', it.url, { link: true });
      } else if (it.kind === 'note') {
        // notes displayed as main content
      } else {
        addFieldRow('用户名 / 账号', it.username, { mono: true });
        addFieldRow('密码', it.password, { secret: true, mono: true });
      }

      if (it.kind !== 'apikey' && it.kind !== 'card' && it.kind !== 'idcard' && it.totp) {
        var otp = totpCode(it.totp);
        var row = el('div', 'vt-frow vt-otp-box');
        row.append(el('div', 'vt-flbl', '两步验证码（TOTP）'));
        var line = el('div', 'vt-fval');
        var codeEl = el('span', 'vt-otp-big mono', otp ? (otp.code.slice(0, 3) + ' ' + otp.code.slice(3)) : '密钥格式无效');
        codeEl.dataset.totpDetail = it.totp;
        var remEl = el('span', 'vt-otp-rem mono', otp ? (otp.remaining + 's') : '');
        remEl.dataset.totpRem = it.totp;
        var cp2 = el('button', 'vt-mini', '复制');
        cp2.type = 'button';
        cp2.onclick = function () { var cur = totpCode(it.totp); if (cur) copySecret(cur.code, '验证码', true); };
        line.append(codeEl, remEl, cp2);
        row.append(line);
        detailPane.append(row);
      }
      if (it.kind === 'login' && it.url) {
        addFieldRow('网址', it.url, { link: true });
      }
      (it.fields || []).forEach(function (f) {
        addFieldRow(f.label || '自定义字段', f.value, { secret: !!f.secret, mono: !!f.secret });
      });
      if (it.notes) {
        var nrow = el('div', 'vt-frow');
        nrow.append(el('div', 'vt-flbl', it.kind === 'note' ? '笔记内容' : '备注 / 安全笔记'));
        nrow.append(el('pre', 'vt-notes', it.notes));
        detailPane.append(nrow);
      }
      if (it.tags && it.tags.length) {
        var trow = el('div', 'tags');
        it.tags.forEach(function (tg) { trow.append(el('span', 'tag', '#' + tg)); });
        detailPane.append(trow);
      }
    }

    drawList();
    if (ui.totpTimer) clearInterval(ui.totpTimer);
    ui.totpTimer = setInterval(function () {
      if (!ui || !ui.root) return;
      ui.root.querySelectorAll('[data-totp-raw]').forEach(function (n) {
        var o = totpCode(n.dataset.totpRaw);
        if (o) n.textContent = o.code.slice(0, 3) + ' ' + o.code.slice(3);
      });
      ui.root.querySelectorAll('[data-totp-detail]').forEach(function (n) {
        var o = totpCode(n.dataset.totpDetail);
        if (o) n.textContent = o.code.slice(0, 3) + ' ' + o.code.slice(3);
      });
      ui.root.querySelectorAll('[data-totp-rem]').forEach(function (n) {
        var o = totpCode(n.dataset.totpRem);
        if (o) n.textContent = o.remaining + 's';
      });
    }, 1000);
  }

  function openEditor(existing) {
    resetAutoLock();
    var isNew = !existing;
    var cur = existing ? JSON.parse(JSON.stringify(existing)) : {
      id: makeId(), kind: 'login', title: '', username: '', password: '', url: '', totp: '', notes: '', fields: [], tags: [], favorite: false,
    };
    var ov = el('div', 'vt-sub');
    var box = el('div', 'vt-sub-box');
    box.append(el('h3', null, isNew ? '新建条目' : '编辑条目'));
    var form = el('form', 'vt-form');

    var kindSel = el('select', 'vt-in');
    [['login', '🔑 登录账号'], ['note', '📝 安全笔记'], ['card', '💳 银行卡片'], ['idcard', '🪪 证件资料'], ['apikey', '⚡ API 密钥']].forEach(function (p) {
      var o = document.createElement('option'); o.value = p[0]; o.textContent = p[1];
      if (cur.kind === p[0]) o.selected = true;
      kindSel.append(o);
    });
    var fTitle = el('input', 'vt-in'); fTitle.placeholder = '名称（如 GitHub、阿里云）'; fTitle.value = cur.title || ''; fTitle.required = true;
    var fUser = el('input', 'vt-in'); fUser.placeholder = '用户名 / 邮箱 / 手机号'; fUser.value = cur.username || '';
    var pwWrap = el('div', 'vt-pw-row');
    var fPass = el('input', 'vt-in mono'); fPass.placeholder = '密码 / 密钥 / 卡号'; fPass.value = cur.password || '';
    var gBtn = el('button', 'btn sm', '🎲 生成'); gBtn.type = 'button';
    gBtn.onclick = function () { fPass.value = genPassword({ length: 20 }); };
    pwWrap.append(fPass, gBtn);
    var fUrl = el('input', 'vt-in'); fUrl.placeholder = '网址（如 https://github.com）'; fUrl.value = cur.url || '';
    var fTotp = el('input', 'vt-in mono'); fTotp.placeholder = 'TOTP 密钥或 otpauth://totp/...（可选）'; fTotp.value = cur.totp || '';
    var fTags = el('input', 'vt-in'); fTags.placeholder = '标签（逗号分隔，如 工作, 服务器）'; fTags.value = (cur.tags || []).join(', ');
    var fNotes = el('textarea', 'ta'); fNotes.rows = 4; fNotes.placeholder = '备注 / 恢复码 / 安全笔记'; fNotes.value = cur.notes || '';

    var fieldsBox = el('div', 'vt-cfields');
    function drawCustomFields() {
      fieldsBox.replaceChildren();
      (cur.fields || []).forEach(function (cf, idx) {
        var r = el('div', 'vt-cf-row');
        var lb = el('input', 'vt-in'); lb.placeholder = '字段名'; lb.value = cf.label || ''; lb.oninput = function () { cf.label = lb.value; };
        var vl = el('input', 'vt-in'); vl.placeholder = '字段值'; vl.value = cf.value || ''; vl.oninput = function () { cf.value = vl.value; };
        var sec = el('button', 'vt-mini', cf.secret ? '密文' : '明文'); sec.type = 'button';
        sec.onclick = function () { cf.secret = !cf.secret; sec.textContent = cf.secret ? '密文' : '明文'; };
        var rm = el('button', 'vt-mini', '✕'); rm.type = 'button';
        rm.onclick = function () { cur.fields.splice(idx, 1); drawCustomFields(); };
        r.append(lb, vl, sec, rm);
        fieldsBox.append(r);
      });
    }
    drawCustomFields();
    var addFieldBtn = el('button', 'btn sm', '+ 添加自定义字段'); addFieldBtn.type = 'button';
    addFieldBtn.onclick = function () { cur.fields = cur.fields || []; cur.fields.push({ label: '', value: '', secret: false }); drawCustomFields(); };

    var cancel = el('button', 'btn', '取消'); cancel.type = 'button'; cancel.onclick = function () { ov.remove(); };
    var save = el('button', 'btn btn--accent', '加密保存'); save.type = 'submit';
    var rowBtns = el('div', 'btn-row'); rowBtns.append(cancel, save);

    function updateFormFields() {
      var k = kindSel.value;
      if (k === 'note') {
        fTitle.placeholder = '笔记标题 *（如 服务器备忘）';
        fUser.hidden = true;
        pwWrap.hidden = true;
        fUrl.hidden = true;
        fTotp.hidden = true;
        fNotes.hidden = false;
        fNotes.rows = 8;
        fNotes.placeholder = '安全笔记内容 *';
      } else if (k === 'card') {
        fTitle.placeholder = '卡片名称 *（如 招商银行信用卡）';
        fUser.hidden = false;
        fUser.placeholder = '持卡人姓名';
        pwWrap.hidden = false;
        fPass.placeholder = '卡号';
        fUrl.hidden = true;
        fTotp.hidden = true;
        fNotes.hidden = false;
        fNotes.rows = 3;
        fNotes.placeholder = '备注（如 发卡行、客服电话等）';
      } else if (k === 'idcard') {
        fTitle.placeholder = '证件名称 *（如 居民身份证、护照、驾照）';
        fUser.hidden = false;
        fUser.placeholder = '姓名 / 持有人';
        pwWrap.hidden = false;
        fPass.placeholder = '证件号码 *';
        fUrl.hidden = true;
        fTotp.hidden = true;
        fNotes.hidden = false;
        fNotes.rows = 3;
        fNotes.placeholder = '备注说明（如 签发地、到期日等）';
      } else if (k === 'apikey') {
        fTitle.placeholder = '名称 *（如 OpenAI、AWS、GitHub Token）';
        fUser.hidden = false;
        fUser.placeholder = 'Key ID / Access Key（可选）';
        pwWrap.hidden = false;
        fPass.placeholder = 'API 密钥 / Secret Token *';
        fUrl.hidden = false;
        fUrl.placeholder = '接口地址 / 服务端点（如 https://api.openai.com）';
        fTotp.hidden = true;
        fNotes.hidden = false;
        fNotes.rows = 3;
        fNotes.placeholder = '备注说明（如 权限、配额、到期日等）';
      } else {
        fTitle.placeholder = '名称（如 GitHub、Google）';
        fUser.hidden = false;
        fUser.placeholder = '用户名 / 邮箱 / 手机号';
        pwWrap.hidden = false;
        fPass.placeholder = '密码';
        fUrl.hidden = false;
        fUrl.placeholder = '网址（如 https://github.com）';
        fTotp.hidden = false;
        fTotp.placeholder = 'TOTP 密钥或 otpauth://totp/...（可选）';
        fNotes.hidden = false;
        fNotes.rows = 4;
        fNotes.placeholder = '备注 / 恢复码 / 安全笔记';
      }
    }
    kindSel.onchange = updateFormFields;
    updateFormFields();

    form.append(kindSel, fTitle, fUser, pwWrap, fUrl, fTotp, fTags, fNotes, fieldsBox, addFieldBtn, rowBtns);
    form.onsubmit = async function (e) {
      e.preventDefault();
      var now = Math.floor(Date.now() / 1000);
      cur.kind = kindSel.value;
      cur.title = fTitle.value.trim() || '未命名';
      cur.username = cur.kind === 'note' ? '' : fUser.value.trim();
      cur.password = cur.kind === 'note' ? '' : fPass.value;
      cur.url = (cur.kind === 'login' || cur.kind === 'apikey') ? fUrl.value.trim() : '';
      cur.totp = (cur.kind === 'login') ? fTotp.value.trim() : '';
      cur.tags = fTags.value.split(/[,，;]/).map(function (x) { return x.trim(); }).filter(Boolean).slice(0, 8);
      cur.notes = fNotes.value;
      cur.fields = (cur.fields || []).filter(function (f) { return (f.label || f.value); });
      cur.updated_at = now;
      if (isNew) { cur.created_at = now; ui.data.items.unshift(cur); }
      else {
        var idx = ui.data.items.findIndex(function (x) { return x.id === cur.id; });
        if (idx >= 0) ui.data.items[idx] = cur;
      }
      save.disabled = true;
      if (await saveToServer()) {
        ui.selectedId = cur.id;
        ov.remove();
        ui.toast(isNew ? '已加密保存' : '已更新');
        renderVault();
      } else save.disabled = false;
    };
    box.append(form);
    ov.append(box);
    ov.onclick = function (e) { if (e.target === ov) ov.remove(); };
    ui.root.append(ov);
    fTitle.focus();
  }

  function openGenerator() {
    resetAutoLock();
    var ov = el('div', 'vt-sub');
    var box = el('div', 'vt-sub-box');
    box.append(el('h3', null, '随机强密码生成器'));
    var out = el('div', 'vt-gen-out mono');
    var st = el('p', 'vt-hint');
    var opts = { mode: 'random', length: 20, upper: true, lower: true, digits: true, symbols: true, noAmbiguous: false, words: 4 };
    function regen() {
      var pw = genPassword(opts);
      out.textContent = pw;
      var s = passwordStrength(pw);
      st.textContent = '强度：' + s.label + ' · 长度 ' + pw.length;
    }
    var modeRow = el('div', 'vt-cats');
    var mRand = el('button', 'pv-tab', '随机字符'); mRand.type = 'button'; mRand.setAttribute('aria-selected', 'true');
    var mPass = el('button', 'pv-tab', '易记词组'); mPass.type = 'button'; mPass.setAttribute('aria-selected', 'false');
    mRand.onclick = function () { opts.mode = 'random'; mRand.setAttribute('aria-selected', 'true'); mPass.setAttribute('aria-selected', 'false'); regen(); };
    mPass.onclick = function () { opts.mode = 'passphrase'; mPass.setAttribute('aria-selected', 'true'); mRand.setAttribute('aria-selected', 'false'); regen(); };
    modeRow.append(mRand, mPass);

    var lenLbl = el('label', 'vt-hint', '长度：20');
    var lenIn = document.createElement('input'); lenIn.type = 'range'; lenIn.min = '8'; lenIn.max = '48'; lenIn.value = '20';
    lenIn.oninput = function () { opts.length = Number(lenIn.value); opts.words = Math.max(3, Math.min(8, Math.round(opts.length / 5))); lenLbl.textContent = opts.mode === 'passphrase' ? ('词数：' + opts.words) : ('长度：' + opts.length); regen(); };

    var symLbl = el('label', 'vt-chk');
    var symCk = document.createElement('input'); symCk.type = 'checkbox'; symCk.checked = true;
    symCk.onchange = function () { opts.symbols = symCk.checked; regen(); };
    symLbl.append(symCk, document.createTextNode(' 包含符号（!@#$%…）'));

    var rBtn = el('button', 'btn', '换一个'); rBtn.type = 'button'; rBtn.onclick = regen;
    var cBtn = el('button', 'btn btn--accent', '安全复制'); cBtn.type = 'button'; cBtn.onclick = function () { copySecret(out.textContent, '生成的密码', true); };
    var xBtn = el('button', 'btn btn--ghost', '关闭'); xBtn.type = 'button'; xBtn.onclick = function () { ov.remove(); };
    var brow = el('div', 'btn-row'); brow.append(rBtn, cBtn, xBtn);
    box.append(modeRow, out, st, lenLbl, lenIn, symLbl, brow);
    ov.append(box);
    ov.onclick = function (e) { if (e.target === ov) ov.remove(); };
    ui.root.append(ov);
    regen();
  }

  function openImporter() {
    resetAutoLock();
    var ov = el('div', 'vt-sub');
    var box = el('div', 'vt-sub-box');
    box.append(
      el('h3', null, '导入密码'),
      el('p', 'vt-lead', '支持 1Password（.1pux / .csv）、Bitwarden（.json）、Chrome 密码（.csv）。文件仅在浏览器本地解析，加密后再上传。')
    );
    var fin = document.createElement('input');
    fin.type = 'file'; fin.accept = '.1pux,.csv,.json,text/csv,application/json';
    var msg = el('p', 'vt-hint', '选择导出文件…');
    var impBtn = el('button', 'btn btn--accent', '开始导入'); impBtn.type = 'button'; impBtn.disabled = true;
    var parsed = [];
    fin.onchange = async function () {
      var f = fin.files && fin.files[0];
      if (!f) return;
      msg.textContent = '正在本地解析…'; impBtn.disabled = true; parsed = [];
      try {
        if (/\.1pux$/i.test(f.name)) {
          var txt = await extractZipFile(await f.arrayBuffer(), 'export.data');
          parsed = importFrom1PuxData(JSON.parse(txt));
        } else if (/\.json$/i.test(f.name)) {
          var obj = JSON.parse(await f.text());
          if (obj.accounts) parsed = importFrom1PuxData(obj);
          else if (Array.isArray(obj.items)) parsed = importFromBitwardenJson(obj);
          else throw new Error('无法识别的 JSON 导出格式');
        } else {
          parsed = importFromCsv(await f.text());
        }
        msg.textContent = parsed.length ? ('已识别 ' + parsed.length + ' 条记录，确认后将合并并加密保存。') : '未识别到有效记录';
        impBtn.disabled = !parsed.length;
      } catch (ex) {
        msg.textContent = '解析失败：' + (ex.message || ex);
      }
    };
    impBtn.onclick = async function () {
      if (!parsed.length) return;
      impBtn.disabled = true;
      ui.data.items = parsed.concat(ui.data.items);
      if (await saveToServer()) {
        ov.remove();
        ui.toast('已导入 ' + parsed.length + ' 条加密记录');
        renderVault();
      } else impBtn.disabled = false;
    };
    var cancel = el('button', 'btn', '取消'); cancel.type = 'button'; cancel.onclick = function () { ov.remove(); };
    var brow = el('div', 'btn-row'); brow.append(cancel, impBtn);
    box.append(fin, msg, brow);
    ov.append(box);
    ov.onclick = function (e) { if (e.target === ov) ov.remove(); };
    ui.root.append(ov);
  }

  function exportBackup() {
    if (!ui || !ui.envelope) return;
    var blob = new Blob([JSON.stringify(ui.envelope, null, 2)], { type: 'application/json' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'clipboard-vault-encrypted-' + new Date().toISOString().slice(0, 10) + '.json';
    a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); }, 3000);
    ui.toast('已导出加密备份（需原主密码解密）');
  }

  function openChangeMaster() {
    resetAutoLock();
    var ov = el('div', 'vt-sub');
    var box = el('div', 'vt-sub-box');
    box.append(el('h3', null, '修改主密码'), el('p', 'vt-lead', '将使用新主密码与全新随机盐重新加密全部条目。'));
    var p1 = el('input', 'vt-in'); p1.type = 'password'; p1.placeholder = '新主密码（至少 8 位）'; p1.autocomplete = 'new-password';
    var p2 = el('input', 'vt-in'); p2.type = 'password'; p2.placeholder = '再次输入新主密码'; p2.autocomplete = 'new-password';
    var err = el('p', 'err'); err.hidden = true;
    var ok = el('button', 'btn btn--accent', '重新加密并保存'); ok.type = 'submit';
    var cancel = el('button', 'btn', '取消'); cancel.type = 'button'; cancel.onclick = function () { ov.remove(); };
    var brow = el('div', 'btn-row'); brow.append(cancel, ok);
    var form = el('form', 'vt-form'); form.append(p1, p2, err, brow);
    form.onsubmit = async function (e) {
      e.preventDefault(); err.hidden = true;
      if (p1.value.length < 8) { err.textContent = '新主密码至少 8 位'; err.hidden = false; return; }
      if (p1.value !== p2.value) { err.textContent = '两次输入不一致'; err.hidden = false; return; }
      ok.disabled = true; ok.textContent = '正在重新加密…';
      try {
        var newSalt = randBytes(16);
        var newKey = await deriveKey(p1.value, newSalt, DEFAULT_ITERS);
        var oldKey = ui.keyHandle, oldSalt = ui.saltBytes, oldIter = ui.iterations;
        ui.keyHandle = newKey; ui.saltBytes = newSalt; ui.iterations = DEFAULT_ITERS;
        if (await saveToServer()) {
          ov.remove();
          ui.toast('主密码已更新');
        } else {
          ui.keyHandle = oldKey; ui.saltBytes = oldSalt; ui.iterations = oldIter;
        }
      } catch (ex) { err.textContent = ex.message || String(ex); err.hidden = false; }
      finally { ok.disabled = false; ok.textContent = '重新加密并保存'; }
    };
    box.append(form);
    ov.append(box);
    ov.onclick = function (e) { if (e.target === ov) ov.remove(); };
    ui.root.append(ov);
    p1.focus();
  }

  async function open(opts) {
    opts = opts || {};
    closeModal();
    var root = el('div', 'pv vt-root');
    root.setAttribute('role', 'dialog'); root.setAttribute('aria-modal', 'true');
    var head = el('div', 'pv-head');
    var title = el('div', 'pv-title', '🔐 密码保险箱（E2EE）');
    var headRight = el('div', 'vt-head-r');
    head.append(title, headRight);
    var body = el('div', 'vt-body');
    body.append(el('p', 'vt-empty', '正在连接密码库…'));
    root.append(head, body);
    document.body.append(root);
    document.body.classList.add('pv-open');

    ui = {
      root: root, headRight: headRight, body: body,
      toast: opts.toast || function () {},
      envelope: null, rev: 0, keyHandle: null, saltBytes: null, iterations: DEFAULT_ITERS,
      data: null, selectedId: null, q: '', cat: 'all', totpTimer: null, lockTimer: null,
      onKey: function (e) {
        if (e.key === 'Escape') {
          var sub = root.querySelector('.vt-sub');
          if (sub) { e.preventDefault(); e.stopPropagation(); sub.remove(); return; }
          e.preventDefault(); e.stopPropagation(); closeModal();
        }
      },
    };
    document.addEventListener('keydown', ui.onKey, true);
    renderHead([]);

    var res = await apiReq('/api/vault');
    if (!ui) return;
    if (!res.ok) {
      body.replaceChildren(el('p', 'vt-empty', (res.d && (res.d.error || res.d.detail)) || '加载密码库失败（请确认已登录）'));
      return;
    }
    if (res.d.exists && res.d.vault) {
      ui.envelope = res.d.vault;
      ui.rev = res.d.vault.rev || 0;
      renderUnlock();
    } else {
      renderSetup();
    }
  }

  var api = {
    open: open,
    close: closeModal,
    crypto: {
      deriveKey: deriveKey,
      encryptVault: encryptVault,
      decryptVault: decryptVault,
      totpCode: totpCode,
      genPassword: genPassword,
      passwordStrength: passwordStrength,
      importFromCsv: importFromCsv,
      importFrom1PuxData: importFrom1PuxData,
      importFromBitwardenJson: importFromBitwardenJson,
      b64Encode: b64Encode,
      b64Decode: b64Decode,
      pbkdf2Sha256Js: pbkdf2Sha256Js,
      aesGcmEncryptJs: aesGcmEncryptJs,
      aesGcmDecryptJs: aesGcmDecryptJs,
    },
  };
  global.ClipVault = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
