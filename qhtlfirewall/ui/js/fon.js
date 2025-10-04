// fon.js - status (on/test/off) button logic & hold actions
(function(){
  if(window._fwFonLoaded) return; window._fwFonLoaded=1;
  var btn=document.getElementById('fwb1'); if(!btn) return;
  var lab=document.getElementById('fw-status-text');
  var hold={active:false,phase:0,count:3,timer:null,countInt:null,dimTimer:null};
  function startHold(){ if(!btn) return; try{ var cur=btn.classList.contains('fw-status-on')?'on':btn.classList.contains('fw-status-testing')?'testing':btn.classList.contains('fw-status-off')?'off':null; if(cur==='off'){ window.submitAction('enable'); return; } }catch(e){}
    clearHold(); hold.active=true; hold.phase=1; btn.classList.add('hold-counting'); if(lab) lab.textContent='3'; hold.count=3;
    hold.countInt=setInterval(function(){ hold.count--; if(hold.count<=0){ clearInterval(hold.countInt); hold.countInt=null; hold.phase=2; btn.classList.remove('hold-counting'); btn.classList.add('hold-warning'); if(lab) lab.textContent='Warning'; setTimeout(function(){ if(!hold.active||hold.phase!==2) return; hold.phase=3; btn.classList.remove('hold-warning'); btn.classList.add('hold-dimming'); if(lab) lab.textContent='Warning!'; hold.dimTimer=setTimeout(function(){ if(hold.active && hold.phase===3){ window.submitAction('disable'); } },3000); },600); } else { if(lab) lab.textContent=String(hold.count); } },800);
  }
  function clearHold(){ if(!btn) return; hold.active=false; hold.phase=0; hold.count=3; ['hold-counting','hold-warning','hold-dimming'].forEach(c=>btn.classList.remove(c)); if(hold.countInt){ clearInterval(hold.countInt); hold.countInt=null; } if(hold.dimTimer){ clearTimeout(hold.dimTimer); hold.dimTimer=null; }
    try{ var cur=(typeof window.QHTL_FW_STATUS==='string')?window.QHTL_FW_STATUS:''; if(cur && lab){ lab.textContent=cur==='on'?'On':cur==='testing'?'Testing':'Off'; } }catch(e){}
  }
  function releaseHold(){ if(!hold.active){ try{ var cur=btn.classList.contains('fw-status-on')?'on':btn.classList.contains('fw-status-testing')?'testing':btn.classList.contains('fw-status-off')?'off':null; if(cur==='off'){ window.submitAction('enable'); return; } }catch(e){} return; }
    if(hold.phase===3 && hold.dimTimer){ window.submitAction('restart'); } clearHold(); }
  ['mousedown','touchstart'].forEach(evt=>btn.addEventListener(evt,startHold));
  ['mouseup','mouseleave','touchend','touchcancel'].forEach(evt=>btn.addEventListener(evt,releaseHold));
  btn.addEventListener('contextmenu',e=>e.preventDefault());
  btn.addEventListener('keydown',e=>{ if(e.code==='Enter'||e.code==='Space'){ if(!hold.active) startHold(); }});
  btn.addEventListener('keyup',e=>{ if(e.code==='Enter'||e.code==='Space'){ releaseHold(); }});
})();
