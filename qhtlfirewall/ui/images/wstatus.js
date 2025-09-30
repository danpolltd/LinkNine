(function(){
  // Lightweight circular popup controller: 100px outer ring, 80px inner green button
  var api = {};
  var popupId = 'wstatus-popup';
  var outerId = 'wstatus-outer';
  var innerId = 'wstatus-inner';
  var msgId = 'wstatus-msg';
  var anchorSelector = '#wstatus-anchor';
  var restartFlag = '/var/lib/qhtlfirewall/qhtlwaterfall.restart';

  function ensureStyles(){
    if (document.getElementById('wstatus-style')) return;
    var s = document.createElement('style');
    s.id = 'wstatus-style';
    s.textContent = [
      '#'+popupId+'{ position:absolute; width:100px; height:100px; border-radius:50%; display:flex; align-items:center; justify-content:center; z-index:1050;}',
      '#'+popupId+'.inline{ position:relative; }',
      '#'+outerId+'{ position:absolute; inset:0; border-radius:50%; background: radial-gradient(circle at 30% 30%, #e3f9e7 0%, #b4f2c1 50%, #7fdc95 85%); box-shadow: 0 6px 18px rgba(0,0,0,0.25), inset 0 2px 6px rgba(255,255,255,0.6); }',
      '#'+innerId+'{ position:relative; width:80px; height:80px; border-radius:50%; border:2px solid #2f8f49; color:#fff; font-weight:700; display:flex; align-items:center; justify-content:center; cursor:pointer; user-select:none; box-shadow: inset 0 2px 6px rgba(255,255,255,0.35), 0 8px 16px rgba(52,168,83,0.35); transition: background 3s linear; }',
      // State colors
      '#'+innerId+'.state-green{ background: linear-gradient(180deg, #66e08a 0%, #34a853 100%); }',
      '#'+innerId+'.state-orange{ background: linear-gradient(180deg, #fbbf24 0%, #f59e0b 100%); }',
      '#'+innerId+'.state-red{ background: linear-gradient(180deg, #ef4444 0%, #dc2626 100%); }',
      '#'+innerId+'.fast{ transition: background .25s ease; }',
      '#'+innerId+':hover{ filter: brightness(1.06); }',
      '#'+msgId+'{ position:absolute; bottom:-22px; width:140px; left:50%; transform:translateX(-50%); text-align:center; font-size:12px; color:#333; text-shadow:0 1px 0 rgba(255,255,255,0.25); }',
      /* Generic class-based styles for additional stub widgets */
      '.wcircle{ position:relative; width:100px; height:100px; border-radius:50%; display:inline-flex; align-items:center; justify-content:center; vertical-align:top; }',
      '.wcircle-outer{ position:absolute; inset:0; border-radius:50%; background: radial-gradient(circle at 30% 30%, #e3f9e7 0%, #b4f2c1 50%, #7fdc95 85%); box-shadow: 0 6px 18px rgba(0,0,0,0.25), inset 0 2px 6px rgba(255,255,255,0.6); }',
      '.wcircle-inner{ position:relative; width:80px; height:80px; border-radius:50%; border:2px solid #2f8f49; background: linear-gradient(180deg, #66e08a 0%, #34a853 100%); color:#fff; font-weight:700; display:flex; align-items:center; justify-content:center; user-select:none; box-shadow: inset 0 2px 6px rgba(255,255,255,0.35), 0 8px 16px rgba(52,168,83,0.35); }',
      '.wcircle-inner:hover{ filter: brightness(1.06); }',
      '.wcircle-msg{ position:absolute; bottom:-22px; width:140px; left:50%; transform:translateX(-50%); text-align:center; font-size:12px; color:#333; text-shadow:0 1px 0 rgba(255,255,255,0.25); }'
    ].join('\n');
    document.head.appendChild(s);
  }

  function findAnchor(){
    return document.querySelector(anchorSelector) || document.querySelector('.qhtl-bubble-bg') || document.body;
  }

  function remove(){
    try { var el = document.getElementById(popupId); if (el && el.parentNode) el.parentNode.removeChild(el); } catch(_){}
    try { window.clearTimeout(api._timer); } catch(_){}
    try { window.clearInterval(api._pollTimer); } catch(_){}
    api._timer = null; api._pollTimer = null; api._state = null;
  }

  function centerNearAnchor(container){
    var host = findAnchor();
    var rect = (host.getBoundingClientRect ? host.getBoundingClientRect() : {left:0,top:0});
    // Prefer placing near the left of Status row; fallback to center of host
    var left = (rect.left || 0) + 10;
    var top  = (rect.top  || 0) + 10;
    try {
      var scX = (window.scrollX||window.pageXOffset||0);
      var scY = (window.scrollY||window.pageYOffset||0);
      container.style.left = (left + scX) + 'px';
      container.style.top  = (top + scY) + 'px';
      container.style.position = host === document.body ? 'fixed' : 'absolute';
      if (host !== document.body) {
        // attach inside host to keep within the UI bubble
        host.appendChild(container);
        container.style.left = '10px';
        container.style.top = '10px';
      } else {
        document.body.appendChild(container);
      }
    } catch(_) { document.body.appendChild(container); }
  }

  function render(opts){
    opts = opts || {};
    var inline = !!opts.inline;
    var inlineAnchor = opts.anchor || null;
    ensureStyles();
    remove();
    var host = inline ? (inlineAnchor || findAnchor()) : findAnchor();
    var wrap = document.createElement('div');
    wrap.id = popupId;
    wrap.setAttribute('role','dialog');
    wrap.setAttribute('aria-label','Waterfall status');
    wrap.style.pointerEvents = 'auto';
    if (inline) { wrap.className = 'inline'; }

  var outer = document.createElement('div'); outer.id = outerId;
  var inner = document.createElement('div'); inner.id = innerId; inner.textContent = 'On'; inner.className = 'state-green';
    var msg = document.createElement('div'); msg.id = msgId; msg.textContent = '';

    wrap.appendChild(outer); wrap.appendChild(inner); wrap.appendChild(msg);
    if (inline) {
      try { host.appendChild(wrap); } catch(_) { document.body.appendChild(wrap); }
    } else {
      centerNearAnchor(wrap);
    }

    function setBusy(text){ inner.textContent = text; inner.style.cursor='wait'; inner.setAttribute('aria-busy','true'); }
    function setReady(text){ inner.textContent = text; inner.style.cursor='pointer'; inner.removeAttribute('aria-busy'); }

    // state helpers
    function colorGreen(){ inner.classList.remove('state-orange','state-red'); inner.classList.add('state-green','fast'); setTimeout(function(){ inner.classList.remove('fast'); }, 260); }
    function colorOrange(){ inner.classList.remove('state-green','state-red'); inner.classList.add('state-orange'); }
    function colorRed(){ inner.classList.remove('state-green','state-orange'); inner.classList.add('state-red','fast'); setTimeout(function(){ inner.classList.remove('fast'); }, 260); }

    // Track daemon state
    var state = { running: true };

    function doCountdownThenAct(isStart){
      // After hold completes, count 3..1 while staying orange
      colorOrange();
      var n = 3; setBusy(String(n));
      api._timer = setInterval(function(){
        n--; if (n>0) { inner.textContent = String(n); return; }
        window.clearInterval(api._timer); api._timer = null;
        if (isStart) { setBusy('Starting'); colorOrange(); }
        else { setBusy('Restarting'); colorRed(); }
        // Signal restart/start via existing action path; prefer ajax to avoid nav
        try {
          if (window.jQuery) {
            jQuery.ajax({ url: (window.QHTL_SCRIPT||'') + '?action=qhtlwaterfallrestart', method: 'POST', dataType: 'html', timeout: 15000 })
              .always(function(){ startPoll(isStart); });
          } else {
            var x=new XMLHttpRequest(); x.open('POST', (window.QHTL_SCRIPT||'') + '?action=qhtlwaterfallrestart', true); x.onreadystatechange=function(){ if(x.readyState===4){ startPoll(isStart); } }; x.send();
          }
        } catch(_) { startPoll(isStart); }
      }, 1000);
    }

    function startPoll(isStart){
      // Poll the status endpoint until success phrase appears or 8s timeout
      var started = Date.now();
      function check(){
        var urlJson = (window.QHTL_SCRIPT||'') + '?action=status_json';
        var urlHtml = (window.QHTL_SCRIPT||'') + '?action=qhtlwaterfallstatus';
        try {
          if (window.jQuery) {
            jQuery.ajax({ url:urlJson, method:'GET', dataType:'json', timeout:6000 })
              .done(function(json){ if (isRunningJSON(json)) { onOK(); } })
              .fail(function(){ jQuery.ajax({ url:urlHtml, method:'GET', dataType:'html', timeout:6000 }).done(function(html){ if (isOk(html)) { onOK(); } }); });
          } else {
            var x=new XMLHttpRequest(); x.open('GET', urlJson, true); x.onreadystatechange=function(){ if(x.readyState===4){ if(x.status>=200 && x.status<300){ try{ var j=JSON.parse(x.responseText||'{}'); if(isRunningJSON(j)){ onOK(); return; } }catch(e){} } var y=new XMLHttpRequest(); y.open('GET', urlHtml, true); y.onreadystatechange=function(){ if(y.readyState===4 && y.status>=200 && y.status<300){ if(isOk(y.responseText||'')){ onOK(); } } }; y.send(); } }; x.send();
          }
        } catch(_){}
        if (Date.now() - started > 8000) { onTimeout(isStart); }
      }
      api._pollTimer = setInterval(check, 1000); check();
    }

    function isOk(html){
      try { return /qhtlwaterfall\s+status|running|active/i.test(String(html||'')); } catch(_) { return false; }
    }
    function isRunningJSON(j){ try { return !!(j && (j.running===1 || j.running===true)); } catch(e){ return false; } }
    function onOK(){ try { window.clearInterval(api._pollTimer); } catch(_){} api._pollTimer=null; state.running = true; colorGreen(); setReady('On'); msg.textContent=''; try { refreshHeaderStatus(); } catch(_){} }
    function onTimeout(isStart){ try { window.clearInterval(api._pollTimer); } catch(_){} api._pollTimer=null; state.running = false; colorRed(); setReady('Start'); msg.textContent = isStart ? 'Start timed out' : 'Restart timed out'; }

    // Initial status detection
    function initStatus(){
      var urlJson = (window.QHTL_SCRIPT||'') + '?action=status_json';
      try{
        if (window.jQuery){
          jQuery.ajax({ url:urlJson, method:'GET', dataType:'json', timeout:6000 })
            .done(function(j){ if(isRunningJSON(j)){ state.running=true; colorGreen(); setReady('On'); } else { state.running=false; colorRed(); setReady('Start'); } })
            .fail(function(){ /* leave default */ });
        } else {
          var x=new XMLHttpRequest(); x.open('GET', urlJson, true); x.onreadystatechange=function(){ if(x.readyState===4 && x.status>=200 && x.status<300){ try{ var j=JSON.parse(x.responseText||'{}'); if(isRunningJSON(j)){ state.running=true; colorGreen(); setReady('On'); } else { state.running=false; colorRed(); setReady('Start'); } }catch(e){} } }; x.send();
        }
      }catch(e){}
    }

    // Press-and-hold for 3s, then run countdown and action
    (function(){
      var holdTimer=null, held=false;
      function startHold(){ if(inner.getAttribute('aria-busy')==='true') return; held=false; colorOrange(); holdTimer=setTimeout(function(){ held=true; doCountdownThenAct(!state.running); }, 3000); }
      function cancelHold(){ if(holdTimer){ clearTimeout(holdTimer); holdTimer=null; } if(!held){ // revert to idle color/text
          if(state.running){ colorGreen(); setReady('On'); } else { colorRed(); setReady('Start'); }
        }
      }
      inner.addEventListener('pointerdown', function(e){ e.preventDefault(); startHold(); });
      inner.addEventListener('pointerup', function(e){ e.preventDefault(); cancelHold(); });
      inner.addEventListener('pointercancel', function(){ cancelHold(); });
      inner.addEventListener('mouseleave', function(){ cancelHold(); });
      // Touch fallback
      inner.addEventListener('touchstart', function(e){ e.preventDefault(); startHold(); }, {passive:false});
      inner.addEventListener('touchend', function(e){ e.preventDefault(); cancelHold(); }, {passive:false});
    })();
    initStatus();
    if (!inline) {
      // allow click outside to dismiss
      setTimeout(function(){
        function outside(e){ try{ if (!wrap.contains(e.target)) { remove(); document.removeEventListener('click', outside, true); } }catch(_){} }
        document.addEventListener('click', outside, true);
      }, 0);
    }

    api._state = { visible:true };
    return wrap;
  }

  function refreshHeaderStatus(){
    try {
      var el = document.getElementById('qhtl-status-btn');
      if (!el) return;
      // Fetch status badge via hidden request and map to class/background
      var url = (window.QHTL_SCRIPT||'') + '?action=qhtlwaterfallstatus';
      if (window.jQuery) {
        jQuery.ajax({ url:url, method:'GET', dataType:'html', timeout:6000 })
          .done(function(html){ updateFromHTML(el, html); });
      } else {
        var x=new XMLHttpRequest(); x.open('GET', url, true); x.onreadystatechange=function(){ if(x.readyState===4 && x.status>=200 && x.status<300){ updateFromHTML(el, x.responseText||''); } }; x.send();
      }
    } catch(_){}
  }
  function updateFromHTML(el, html){
    var txt = (/Disabled|Stopped/i.test(html)) ? 'Disabled' : (/Testing/i.test(html) ? 'Testing' : 'Enabled');
    el.textContent = txt; el.classList.remove('success','warning','danger');
    if (/Disabled|Stopped/i.test(txt)) { el.classList.add('danger'); }
    else if (/Testing/i.test(txt)) { el.classList.add('warning'); }
    else { el.classList.add('success'); }
  }

  api.open = function(){ try { var node = render({ inline: false }); return !!node; } catch(e){ return false; } };
  api.mountInline = function(anchor){ try { var el = anchor; if (typeof anchor === 'string') { el = document.querySelector(anchor); } if(el){ try { while(el.firstChild) el.removeChild(el.firstChild); } catch(_){} } return !!render({ inline: true, anchor: el }); } catch(e){ return false; } };
  api.close = function(){ remove(); };

  // auto-wire global
  window.WStatus = api;
})();
