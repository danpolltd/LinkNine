// fconfig.js - Config button
(function(){ if(window._fwFconfigLoaded) return; window._fwFconfigLoaded=1; var b=document.getElementById('fwb2'); if(!b) return; b.addEventListener('click',function(){ window.submitAction('conf'); });})();
