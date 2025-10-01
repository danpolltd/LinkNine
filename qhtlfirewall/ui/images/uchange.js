(function(){
  try{
    var btn = document.getElementById('qhtl-upgrade-changelog');
    if(!btn) return;
  var tri = btn.querySelector('.tri');
  function setFill(p){ if(!tri) return; p=Math.max(0,Math.min(100,p)); tri.style.transform = 'scale(var(--k)) scaleY(' + (p/100) + ')'; }
    btn.addEventListener('click', function(e){
  e.preventDefault(); btn.disabled=true; try{ btn.classList.add('running'); }catch(_){ }
      // Open changelog in a new small window and just play the animation once
      try{ var base=(window.QHTL_SCRIPT||'')|| ''; window.open(base+'?action=changelog','qhtl_changelog','width=680,height=520,noopener'); }catch(_){ }
  // No rising/fill animation for changelog; quick pulse only
  try{ explode(btn); }catch(_){}
  setTimeout(function(){ try{ btn.classList.remove('running'); }catch(_){} btn.disabled=false; }, 700);
    });
    function explode(el){
      try{ el.classList.add('expl'); setTimeout(function(){ el.classList.remove('expl'); }, 700); }catch(_){ }
    }
  }catch(e){}
})();
