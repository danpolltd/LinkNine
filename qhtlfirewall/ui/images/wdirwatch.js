(function(){
  window.WDirWatch = {
    mountInline: function(anchor){
      try {
        var el = typeof anchor==='string'?document.querySelector(anchor):anchor; if(!el) return false; ensure(); var node = make('Dir Watch');
        // Navigate to dirwatch action when clicked
        try {
          var inner = node.querySelector('.wcircle-inner');
          inner.style.cursor = 'pointer';
          inner.addEventListener('click', function(e){ e.preventDefault(); var base=(window.QHTL_SCRIPT||''); var url = base + '?action=dirwatch';
            try {
              var area = document.getElementById('qhtl-inline-area');
              if (window.jQuery) { jQuery(area).html('<div class="text-muted">Loading…</div>').load(url); }
              else { var x=new XMLHttpRequest(); x.open('GET', url, true); x.onreadystatechange=function(){ if(x.readyState===4 && x.status>=200 && x.status<300){ area.innerHTML=x.responseText; } }; x.send(); }
            } catch(_){ try{ window.location = url; } catch(_2){ location.href = url; } }
          });
        } catch(_){ }
        el.appendChild(node);
        return true;
      } catch(e){ return false; }
    }
  };
  function ensure(){ if(document.getElementById('wwidget-style')) return; var s=document.createElement('style'); s.id='wwidget-style'; s.textContent=[
    '.wcircle{ position:relative; width:100px; height:100px; border-radius:50%; display:inline-flex; align-items:center; justify-content:center; vertical-align:top; }',
    '.wcircle-outer{ position:absolute; inset:0; border-radius:50%; background: radial-gradient(circle at 30% 30%, #e3f9e7 0%, #b4f2c1 50%, #7fdc95 85%); box-shadow: 0 6px 18px rgba(0,0,0,0.25), inset 0 2px 6px rgba(255,255,255,0.6); }',
    '.wcircle-inner{ position:relative; width:80px; height:80px; border-radius:50%; border:2px solid #2f8f49; background: linear-gradient(180deg, #66e08a 0%, #34a853 100%); color:#fff; font-weight:700; display:flex; align-items:center; justify-content:center; user-select:none; box-shadow: inset 0 2px 6px rgba(255,255,255,0.35), 0 8px 16px rgba(52,168,83,0.35); }',
    '.wcircle-msg{ position:absolute; bottom:-22px; width:140px; left:50%; transform:translateX(-50%); text-align:center; font-size:12px; color:#333; text-shadow:0 1px 0 rgba(255,255,255,0.25); }'
  ].join('\n'); document.head.appendChild(s);} 
  function make(label){ var wrap=document.createElement('div'); wrap.className='wcircle'; var o=document.createElement('div'); o.className='wcircle-outer'; var i=document.createElement('div'); i.className='wcircle-inner'; i.textContent=label; var m=document.createElement('div'); m.className='wcircle-msg'; wrap.appendChild(o); wrap.appendChild(i); wrap.appendChild(m); return wrap; }
})();
