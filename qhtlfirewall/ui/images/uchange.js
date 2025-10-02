(function(){
  try{
    var triBtn = document.getElementById('qhtl-upgrade-changelog');
    var plainBtn = document.getElementById('qhtl-upgrade-changelog-plain');
    var btn = triBtn || plainBtn;
    if(!btn) return;
    var targetId = 'qhtl-upgrade-inline-area';
    function loadInline(){
      var area = document.getElementById(targetId);
      var base = (window.QHTL_SCRIPT||'')|| '';
      var url = base + '?action=changelog&ajax=1';
      if (area) {
        if (window.jQuery) {
          try { jQuery(area).html('<div class="text-muted">Loading...</div>').load(url); } catch(_jq) { fallbackNav(); }
        } else {
          try {
            var x = new XMLHttpRequest();
            x.open('GET', url, true);
            try { x.setRequestHeader('X-Requested-With','XMLHttpRequest'); } catch(_hdr) {}
            x.onreadystatechange = function(){ if (x.readyState===4) { if (x.status>=200 && x.status<300) { area.innerHTML = x.responseText; } else { fallbackNav(); } } };
            x.send(null);
          } catch(_xhr) { fallbackNav(); }
        }
      } else { fallbackNav(); }
    }
    function fallbackNav(){ try { var base=(window.QHTL_SCRIPT||'')|| ''; window.location = base + '?action=changelog'; } catch(_) {} }
    function pulse(el){ try{ el.classList.add('expl'); setTimeout(function(){ el.classList.remove('expl'); }, 700); }catch(_){ } }
    function onClick(e){ e.preventDefault(); try{ btn.disabled=true; }catch(_){ } try{ btn.classList.add('running'); }catch(_){ } loadInline(); try{ pulse(btn); }catch(_){ } setTimeout(function(){ try{ btn.classList.remove('running'); }catch(_){} try{ btn.disabled=false; }catch(_2){} }, 700); return false; }
    btn.addEventListener('click', onClick);
  }catch(e){}
})();
