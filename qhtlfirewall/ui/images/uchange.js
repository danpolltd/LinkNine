(function(){
  try{
    var btn = document.getElementById('qhtl-upgrade-changelog');
    if(!btn) return;
    var tri = btn.querySelector('.tri');
    var pct = 0, t;
    function setFill(p){ tri.style.setProperty('--p', Math.max(0,Math.min(100,p))); }
    btn.addEventListener('click', function(e){
      e.preventDefault(); btn.disabled=true; btn.classList.add('running');
      // Open changelog in a new small window and just play the animation once
      try{ var base=(window.QHTL_SCRIPT||'')|| ''; window.open(base+'?action=changelog','qhtl_changelog','width=680,height=520,noopener'); }catch(_){ }
      pct=0; setFill(0); t=setInterval(function(){ pct+=4; if(pct>=100){ pct=100; clearInterval(t); btn.classList.remove('running'); explode(btn); } setFill(pct); }, 120);
    });
    function explode(el){
      try{ el.classList.add('expl'); setTimeout(function(){ el.classList.remove('expl'); }, 700); }catch(_){ }
    }
  }catch(e){}
})();
