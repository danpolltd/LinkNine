(function(){
  try{
    var btn = document.getElementById('qhtl-upgrade-mshield');
    if(!btn) return;
    btn.addEventListener('click', function(e){
      e.preventDefault();
      try{ if (window.openPromoModal) { openPromoModal(); return; } }catch(_){ }
      try{ if (typeof window.qhtlActivateTab === 'function') { window.qhtlActivateTab('#moreplus'); } }catch(_){ }
    });
  }catch(e){}
})();
