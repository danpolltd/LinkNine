// frules.js - Rules (status) button
(function(){ if(window._fwFrulesLoaded) return; window._fwFrulesLoaded=1; var b=document.getElementById('fwb5'); if(!b) return; b.addEventListener('click',function(){ window.submitAction('status'); });})();
