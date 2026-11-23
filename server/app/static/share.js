(function(){
  var mark=document.getElementById('brandMark');
  mark.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M8 7v9a4 4 0 0 0 8 0V6a2.5 2.5 0 0 0-5 0v9.5a1 1 0 0 0 2 0V8"/></svg>';
  var token=location.pathname.split('/').filter(Boolean).pop();
  var root=document.getElementById('root');
  var base='/s/'+encodeURIComponent(token)+'/file';
  var pass='';

  function qPass(sep){ return pass ? (sep+'p='+encodeURIComponent(pass)) : ''; }

  function loadShare(pw){
    pass=pw||'';
    var headers=pass?{'X-Share-Password':pass}:{};
    fetch('/api/share/'+encodeURIComponent(token),{headers:headers})
      .then(function(r){return r.json().then(function(d){return {ok:r.ok,d:d};});})
      .then(function(r){
        if(!r.ok){
          root.innerHTML='<div class="brand brand--big"><span class="brand-mark">'+mark.innerHTML+'</span><span class="brand-name">Clipboard<b>Share</b></span></div>'
            +'<p class="err" style="margin:18px 0">'+esc((r.d&&(r.d.error||r.d.detail))||'分享无效或已过期')+'</p>'
            +'<p><a href="/">返回剪贴板</a></p>';
          return;
        }
        var d=r.d;
        if(d.locked){
          var html='<div class="brand brand--big"><span class="brand-mark">'+mark.innerHTML+'</span><span class="brand-name">Clipboard<b>Share</b></span></div>';
          html+='<p class="chip chip--priv" style="display:inline-flex;margin:12px 0 8px">🔒 需要提取码</p>';
          if(d.owner_username) html+='<p class="meta">来自 @'+esc(d.owner_username)+'</p>';
          html+='<form id="pwForm" class="auth-form" style="margin-top:12px">'
            +'<label class="field"><span>提取码</span><input id="pwIn" type="password" placeholder="输入分享提取码" autocomplete="off" required></label>'
            +(pass?'<p class="err">提取码不正确，请重试</p>':'')
            +'<button class="btn btn--accent btn--block" type="submit">解锁查看</button></form>';
          html+='<p style="margin-top:16px"><a href="/">返回剪贴板</a></p>';
          root.innerHTML=html;
          var f=document.getElementById('pwForm'), inp=document.getElementById('pwIn');
          inp.focus();
          f.onsubmit=function(e){ e.preventDefault(); loadShare(inp.value.trim()); };
          return;
        }
        var html='<div class="brand brand--big"><span class="brand-mark">'+mark.innerHTML+'</span><span class="brand-name">Clipboard<b>Share</b></span></div>';
        html+='<p class="chip chip--pub" style="display:inline-flex;margin:12px 0 8px">分享预览</p>';
        if(d.max_views){
          var leftTxt=d.views_left===0?'本次查看后即焚毁':'剩余 '+d.views_left+' / '+d.max_views+' 次';
          html+=' <span class="exp-pill warn" style="margin-left:6px">🔥 '+esc(leftTxt)+'</span>';
        }
        if(d.owner_username) html+='<p class="meta">来自 @'+esc(d.owner_username)+'</p>';
        if(d.type==='text'){
          html+='<pre class="share-text">'+esc(d.content)+'</pre>';
          html+='<button class="btn btn--ink btn--block" id="copy">复制文本</button>';
        } else {
          var dlUrl=base+qPass('?');
          var src=base+'?inline=1'+qPass('&');
          if(d.preview==='image') html+='<img class="share-img" id="pvimg" style="cursor:zoom-in" src="'+src+'" alt="">';
          else if(d.preview==='video') html+='<video class="share-media" controls playsinline preload="metadata" src="'+src+'"></video>';
          else if(d.preview==='audio') html+='<audio class="share-media" style="height:54px;background:none;border:0" controls preload="metadata" src="'+src+'"></audio>';
          else if(d.preview==='pdf') html+='<iframe class="share-pdf" src="'+src+'" title="PDF"></iframe>';
          else if(d.preview==='text') html+='<pre class="share-text" id="pvtext">加载中…</pre>';
          else if(d.preview==='archive') html+='<button class="btn btn--ink btn--block" id="pvarch" type="button" style="margin:8px 0">查看压缩包目录</button>';
          else if(d.preview==='office') html+='<button class="btn btn--ink btn--block" id="pvoffice" type="button" style="margin:8px 0">预览 Office / 表格文档</button>';
          html+='<p class="fname">'+esc(d.filename)+'</p><p class="fsub">'+(d.ext||'').toUpperCase()+' · '+fmt(d.size)+'</p>';
          if(d.note) html+='<p class="meta" style="margin:4px 0 10px">备注：'+esc(d.note)+'</p>';
          html+='<a class="btn btn--accent btn--block" href="'+dlUrl+'" download>下载文件</a>';
        }
        html+='<p style="margin-top:16px"><a href="/">返回剪贴板</a></p>';
        root.innerHTML=html;
        var b=document.getElementById('copy');
        if(b) b.onclick=function(){ navigator.clipboard.writeText(d.content).then(function(){b.textContent='已复制';}); };
        var im=document.getElementById('pvimg');
        if(im) im.onclick=function(){ window.ClipPreview.open([{name:d.filename,kind:'image',src:src,dl:dlUrl,size:d.size}],0); };
        var pa=document.getElementById('pvarch');
        if(pa) pa.onclick=function(){ window.ClipPreview.open([{name:d.filename,kind:'archive',archive:'/s/'+encodeURIComponent(token)+'/archive'+qPass('?'),dl:dlUrl,size:d.size}],0); };
        var po=document.getElementById('pvoffice');
        if(po) po.onclick=function(){ window.ClipPreview.open([{name:d.filename,kind:'office',office:'/s/'+encodeURIComponent(token)+'/office'+qPass('?'),dl:dlUrl,size:d.size}],0); };
        var tx=document.getElementById('pvtext');
        if(tx) fetch(src,{headers:{Range:'bytes=0-204799'}}).then(function(x){return x.text();}).then(function(t){ tx.textContent=t; }).catch(function(){ tx.textContent='加载失败'; });
      }).catch(function(){ document.getElementById('status').textContent='加载失败'; });
  }
  loadShare('');
  function esc(s){ return String(s||'').replace(/[&<>"']/g,function(c){return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]);}); }
  function fmt(n){ if(!n)return '0 B'; var u=['B','KB','MB','GB'],i=0,v=n; while(v>=1024&&i<u.length-1){v/=1024;i++;} return (v>=100||i===0?Math.round(v):v.toFixed(1))+' '+u[i]; }
})();
