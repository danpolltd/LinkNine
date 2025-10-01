(function(){
  try{
    var manual = document.getElementById('qhtl-upgrade-manual');
    var install = document.getElementById('qhtl-upgrade-install');
    function wire(btn, mode){ if(!btn) return; var tri = btn.querySelector('.tri'); var pct=0, t;
      function setFill(p){ if(!tri) return; p=Math.max(0,Math.min(100,p)); tri.style.transform = 'scaleY(' + (p/100) + ')'; }
      function explode(){ try{ btn.querySelector('.qhtl-tri-btn').classList.add('expl'); setTimeout(function(){ btn.querySelector('.qhtl-tri-btn').classList.remove('expl'); }, 700); }catch(_){ } }
  btn.addEventListener('click', function(e){ e.preventDefault(); btn.disabled=true; var shell = btn.querySelector('.qhtl-tri-btn') || btn; if(shell) shell.classList.add('running');
        pct=0; setFill(0);
        if(mode==='install'){
          // install: start api_start_upgrade then 10s animation and reload
          var base=(window.QHTL_SCRIPT||'')|| '';
          try{ fetch(base+'?action=api_start_upgrade&_=' + String(Date.now()), { method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded','X-Requested-With':'XMLHttpRequest'}, body:'start=1' }); }catch(_){ }
          t=setInterval(function(){ pct+=2; if(pct>=100){ pct=100; clearInterval(t); explode(); setTimeout(function(){ try{ location.reload(); }catch(_){} }, 800); } setFill(pct); }, 200);
        } else {
          // manual check: post manualcheck and animate only
          try{ fetch((window.QHTL_SCRIPT||'')||'', { method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded','X-Requested-With':'XMLHttpRequest'}, body:'action=manualcheck' }); }catch(_){ }
          t=setInterval(function(){ pct+=2; if(pct>=100){ pct=100; clearInterval(t); explode(); if(shell) shell.classList.remove('running'); btn.disabled=false; } setFill(pct); }, 200);
        }
      });
    }
    wire(manual, 'manual'); wire(install, 'install');
  }catch(e){}
})();
