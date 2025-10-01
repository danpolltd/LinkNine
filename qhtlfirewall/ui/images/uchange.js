(function(){
  try{
    var btn = document.getElementById('qhtl-upgrade-changelog');
    if(!btn) return;
  var tri = btn.querySelector('.tri');
  var pct = 0, t;
  function setFill(p){ if(!tri) return; p=Math.max(0,Math.min(100,p)); tri.style.transform = 'scale(var(--k)) scaleY(' + (p/100) + ')'; }
    btn.addEventListener('click', function(e){
  e.preventDefault(); btn.disabled=true; try{ btn.classList.add('running'); }catch(_){}
      // Open changelog in a new small window and just play the animation once
      try{ var base=(window.QHTL_SCRIPT||'')|| ''; window.open(base+'?action=changelog','qhtl_changelog','width=680,height=520,noopener'); }catch(_){ }
  pct=0; setFill(0); t=setInterval(function(){ pct+=4; if(pct>=100){ pct=100; clearInterval(t); try{ btn.classList.remove('running'); }catch(_){} explode(btn); } setFill(pct); }, 120);
    });
    function explode(el){
      try{ el.classList.add('expl'); setTimeout(function(){ el.classList.remove('expl'); }, 700); }catch(_){ }
    }
  }catch(e){}
})();
