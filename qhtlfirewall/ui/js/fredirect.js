// fredirect.js - Redirect button
(function(){ if(window._fwFredirectLoaded) return; window._fwFredirectLoaded=1; var b=document.getElementById('fwb7'); if(!b) return; b.addEventListener('click',function(){ window.submitAction('redirect'); });})();
