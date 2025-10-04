// fallow.js - Allow button
(function(){ if(window._fwFallowLoaded) return; window._fwFallowLoaded=1; var b=document.getElementById('fwb4'); if(!b) return; b.addEventListener('click',function(){ window.submitAction('allow'); });})();
