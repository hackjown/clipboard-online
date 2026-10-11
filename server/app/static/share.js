(function(){
  var mark=document.getElementById('brandMark');
  mark.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M8 7v9a4 4 0 0 0 8 0V6a2.5 2.5 0 0 0-5 0v9.5a1 1 0 0 0 2 0V8"/></svg>';
  var token=location.pathname.split('/').filter(Boolean).pop();
  var root=document.getElementById('root');
  var base='/s/'+encodeURIComponent(token)+'/file';
  fetch('/api/share/'+encodeURIComponent(token)).then(function(r){return r.json().then(function(d){return {ok:r.ok,d:d};});})
  .then(function(r){
    if(!r.ok){ document.getElementById('status').textContent=(r.d&&(r.d.error||r.d.detail))||'分享无效'; return; }
    var d=r.d;
    var html='<div class="brand brand--big"><span class="brand-mark">'+mark.innerHTML+'</span><span class="brand-name">Clipboard<b>Share</b></span></div>';
    html+='<p class="chip chip--pub" style="display:inline-flex;margin:12px 0 8px">分享预览</p>';
    if(d.owner_username) html+='<p class="meta">来自 @'+esc(d.owner_username)+'</p>';
    if(d.type==='text'){
      html+='<pre class="share-text">'+esc(d.content)+'</pre>';
      html+='<button class="btn btn--ink btn--block" id="copy">复制文本</button>';
    } else {
      var src=base+'?inline=1';
      if(d.preview==='image') html+='<img class="share-img" id="pvimg" style="cursor:zoom-in" src="'+src+'" alt="">';
      else if(d.preview==='video') html+='<video class="share-media" controls playsinline preload="metadata" src="'+src+'"></video>';
      else if(d.preview==='audio') html+='<audio class="share-media" style="height:54px;background:none;border:0" controls preload="metadata" src="'+src+'"></audio>';
      else if(d.preview==='pdf') html+='<iframe class="share-pdf" src="'+src+'" title="PDF"></iframe>';
      else if(d.preview==='text') html+='<pre class="share-text" id="pvtext">加载中…</pre>';
      html+='<p class="fname">'+esc(d.filename)+'</p><p class="fsub">'+(d.ext||'').toUpperCase()+' · '+fmt(d.size)+'</p>';
      html+='<a class="btn btn--accent btn--block" href="'+base+'" download>下载文件</a>';
    }
    html+='<p style="margin-top:16px"><a href="/">返回剪贴板</a></p>';
    root.innerHTML=html;
    var b=document.getElementById('copy');
    if(b) b.onclick=function(){ navigator.clipboard.writeText(d.content).then(function(){b.textContent='已复制';}); };
    var im=document.getElementById('pvimg');
    if(im) im.onclick=function(){ window.ClipPreview.open([{name:d.filename,kind:'image',src:src,dl:base,size:d.size}],0); };
    var tx=document.getElementById('pvtext');
    if(tx) fetch(src,{headers:{Range:'bytes=0-204799'}}).then(function(x){return x.text();}).then(function(t){ tx.textContent=t; }).catch(function(){ tx.textContent='加载失败'; });
  }).catch(function(){ document.getElementById('status').textContent='加载失败'; });
  function esc(s){ return String(s||'').replace(/[&<>"']/g,function(c){return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]);}); }
  function fmt(n){ if(!n)return '0 B'; var u=['B','KB','MB','GB'],i=0,v=n; while(v>=1024&&i<u.length-1){v/=1024;i++;} return (v>=100||i===0?Math.round(v):v.toFixed(1))+' '+u[i]; }
})();
