(function(){
  try{
    var btn = document.getElementById('qhtl-upgrade-manual');
    if(!btn) return;
    var tri = btn.querySelector('.tri');
    var pct = 0, t;
    function setFill(p){ tri.style.setProperty('--p', Math.max(0,Math.min(100,p))); }
    btn.addEventListener('click', function(e){
      e.preventDefault(); btn.disabled=true; btn.classList.add('running');
      // Kick background manual check by posting to action=manualcheck (no navigation by using fetch)
      try{ fetch((window.QHTL_SCRIPT||'')||'', { method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded','X-Requested-With':'XMLHttpRequest'}, body:'action=manualcheck' }); }catch(_){ }
      // Animate triangle to 100% over ~10s
      pct=0; setFill(0); t=setInterval(function(){ pct+=2; if(pct>=100){ pct=100; clearInterval(t); btn.classList.remove('running'); explode(btn); } setFill(pct); }, 200);
    });
    function explode(el){
      try{
        el.classList.add('expl'); setTimeout(function(){ el.classList.remove('expl'); }, 700);
      }catch(_){ }
    }
  }catch(e){}
})();
