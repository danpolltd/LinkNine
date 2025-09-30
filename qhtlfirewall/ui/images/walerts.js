(function(){
  // Alerts widget: expands into a rounded square and lists alert templates as links
  var STYLE_ID = 'walerts-style';
  var PANEL_ID = 'walerts-panel';
  var TRANSFER_DONE = false;

  function ensureStyles(){
    if (document.getElementById(STYLE_ID)) return;
    var s = document.createElement('style');
    s.id = STYLE_ID;
    s.textContent = [
      // Base circle (shared with other widgets but re-declared for safety)
      '.wcircle{ position:relative; width:100px; height:100px; border-radius:50%; display:inline-flex; align-items:center; justify-content:center; vertical-align:top; }',
      '.wcircle-outer{ position:absolute; inset:0; border-radius:50%; background: radial-gradient(circle at 30% 30%, #e3f9e7 0%, #b4f2c1 50%, #7fdc95 85%); box-shadow: 0 6px 18px rgba(0,0,0,0.25), inset 0 2px 6px rgba(255,255,255,0.6); }',
      '.wcircle-inner{ position:relative; width:80px; height:80px; border-radius:50%; border:2px solid #2f8f49; background: linear-gradient(180deg, #66e08a 0%, #34a853 100%); color:#fff; font-weight:700; display:flex; align-items:center; justify-content:center; user-select:none; box-shadow: inset 0 2px 6px rgba(255,255,255,0.35), 0 8px 16px rgba(52,168,83,0.35); cursor:pointer; }',
      '.wcircle-inner:hover{ filter: brightness(1.06); }',
      '.wcircle-msg{ position:absolute; bottom:-22px; width:140px; left:50%; transform:translateX(-50%); text-align:center; font-size:12px; color:#333; text-shadow:0 1px 0 rgba(255,255,255,0.25); }',
      // Expanding panel
  '#'+PANEL_ID+'{ position:absolute; top:0; left:0; width:100px; height:100px; border-radius:50%; background:#fff; box-shadow: 0 16px 36px rgba(0,0,0,0.25); overflow:hidden; border:1px solid rgba(0,0,0,0.08); transition: width .28s ease, height .28s ease, border-radius .28s ease, box-shadow .28s ease; z-index:1060; resize:none; }',
      '#'+PANEL_ID+'.expanded{ width:360px; border-radius:16px; }',
      '#'+PANEL_ID+' .walerts-body{ opacity:0; transform: translateY(6px); transition: opacity .22s ease .18s, transform .22s ease .18s; padding:12px; }',
      '#'+PANEL_ID+'.ready .walerts-body{ opacity:1; transform:none; }',
      '#'+PANEL_ID+' .walerts-title{ font-weight:700; color:#1f2937; margin:6px 6px 8px; font-size:14px; }',
      '#'+PANEL_ID+' .walerts-grid{ display:flex; flex-wrap:wrap; gap:6px 12px; max-height:220px; overflow:auto; padding:4px 6px 10px; }',
      '#'+PANEL_ID+' .walerts-link{ display:inline-block; font-size:12px; color:#2563eb; text-decoration:none; padding:2px 4px; border-radius:6px; }',
      '#'+PANEL_ID+' .walerts-link:hover{ background:#eef2ff; text-decoration:underline; }',
      '#'+PANEL_ID+' .walerts-sub{ color:#6b7280; font-size:11px; margin:2px 8px 8px; }',
      // Legacy row fade-out
      '.walerts-legacy-fade{ transition: opacity .25s ease, height .25s ease, margin .25s ease, padding .25s ease; opacity:0; height:0 !important; margin:0 !important; padding:0 !important; }'
    ].join('\n');
    document.head.appendChild(s);
  }

  function make(label){
    var wrap=document.createElement('div'); wrap.className='wcircle';
    var o=document.createElement('div'); o.className='wcircle-outer';
    var i=document.createElement('div'); i.className='wcircle-inner'; i.textContent=label;
    var m=document.createElement('div'); m.className='wcircle-msg'; m.textContent='';
    wrap.appendChild(o); wrap.appendChild(i); wrap.appendChild(m);
    return {wrap:wrap, outer:o, inner:i, msg:m};
  }

  function getTemplates(){
    // Prefer reading from existing legacy row to show a transfer effect, fallback to baked-in list
    var list = [];
    try {
      var sel = document.querySelector("select[name='template']");
      if (sel && sel.options && sel.options.length) {
        for (var k=0;k<sel.options.length;k++){ var opt=sel.options[k]; if (opt && opt.textContent) list.push(opt.textContent.trim()); }
      }
    } catch(_) {}
    if (list.length) return { source:'dom', values:list, legacySelect: document.querySelector("select[name='template']") };
    // Fallback to hard-coded list (must match backend list in DisplayUI.pm)
    list = [
      'alert.txt','tracking.txt','connectiontracking.txt','processtracking.txt','accounttracking.txt','usertracking.txt','sshalert.txt','webminalert.txt','sualert.txt','sudoalert.txt','uialert.txt','cpanelalert.txt','scriptalert.txt','filealert.txt','watchalert.txt','loadalert.txt','resalert.txt','integrityalert.txt','exploitalert.txt','relayalert.txt','portscan.txt','uidscan.txt','permblock.txt','netblock.txt','queuealert.txt','logfloodalert.txt','logalert.txt','modsecipdbcheck.txt'
    ];
    return { source:'fallback', values:list, legacySelect:null };
  }

  function baseUrl(){ try { return (window.QHTL_SCRIPT||'') || (document.location.pathname||''); } catch(_) { return ''; } }

  function navigateToTemplate(name){
    try {
      var url = baseUrl() + '?action=templates&template=' + encodeURIComponent(name);
      var area = document.getElementById('qhtl-inline-area');
      if (area) {
        var u = url + (url.indexOf('?')>-1?'&':'?') + 'ajax=1';
        if (window.jQuery) { jQuery(area).html('<div class="text-muted">Loading...</div>').load(u); }
        else { var x=new XMLHttpRequest(); x.open('GET', u, true); try{x.setRequestHeader('X-Requested-With','XMLHttpRequest');}catch(__){} x.onreadystatechange=function(){ if(x.readyState===4 && x.status>=200 && x.status<300){ area.innerHTML=x.responseText; } }; x.send(); }
      } else {
        window.location.href = url;
      }
    } catch(_) {}
  }

  function buildPanelContent(panel){
    var data = getTemplates();
    var body = document.createElement('div'); body.className='walerts-body';
    var title = document.createElement('div'); title.className='walerts-title'; title.textContent = 'Alert Templates';
    var sub = document.createElement('div'); sub.className='walerts-sub';
    sub.textContent = 'Choose a template to edit';
    var grid = document.createElement('div'); grid.className='walerts-grid';
    data.values.forEach(function(name){
      var a = document.createElement('a'); a.href='javascript:void(0)'; a.className='walerts-link'; a.textContent = name;
      a.addEventListener('click', function(e){ e.preventDefault(); navigateToTemplate(name); });
      grid.appendChild(a);
    });
    body.appendChild(title); body.appendChild(sub); body.appendChild(grid);
    panel.appendChild(body);

    // Perform transfer effect once: fade-out legacy row if present
    if (!TRANSFER_DONE && data.legacySelect) {
      try {
        var tr = data.legacySelect.closest('tr');
        if (tr) {
          // Slight highlight before fade
          tr.style.background = '#fff7d6';
          setTimeout(function(){ tr.classList.add('walerts-legacy-fade'); setTimeout(function(){ try{ tr.parentNode && tr.parentNode.removeChild(tr); }catch(_){} }, 280); }, 120);
        }
      } catch(_) {}
      TRANSFER_DONE = true;
    }
  }

  function expand(anchor, pieces){
    // Create panel overlay and animate from circle to rounded square
    var panel = document.getElementById(PANEL_ID);
    if (panel) { // Toggle close (use stored closer if available)
      try { if (anchor && anchor._walertsClose) { anchor._walertsClose(); return; } } catch(_){}
      try { panel.parentNode.removeChild(panel); } catch(_) {}
      try { pieces.outer.style.opacity='1'; pieces.inner.style.opacity='1'; } catch(_){}
      try { anchor.style.zIndex = ''; } catch(_){}
      return;
    }
    panel = document.createElement('div'); panel.id = PANEL_ID;
    // Place absolutely within anchor
    panel.style.position = 'absolute'; panel.style.top='0'; panel.style.left='0';
  anchor.style.position = 'relative';
  // Elevate anchor stacking context during expansion
  try { anchor.style.zIndex = '1060'; } catch(_){}
    anchor.appendChild(panel);

    // Hide circle during expansion
    try { pieces.outer.style.opacity='0'; pieces.inner.style.opacity='0'; } catch(_){}

    // Build content first but keep collapsed height
    buildPanelContent(panel);
    // Measure final height
    var body = panel.querySelector('.walerts-body');
    var targetHeight = Math.min(260, Math.max(160, (body ? (body.scrollHeight + 16) : 200)));

    // Define a graceful collapse/close with animation and listener cleanup
    var onDocClick = null, onKey = null;
    function doClose(){
      // remove global listeners
      try { document.removeEventListener('click', onDocClick, true); } catch(_){}
      try { document.removeEventListener('keydown', onKey, true); } catch(_){}
      try { panel.classList.remove('ready'); } catch(_){}
      // Animate collapse back to circle size
      try {
        panel.style.height = '100px';
        panel.classList.remove('expanded');
        // After transition completes, remove panel and restore bubble
        panel.addEventListener('transitionend', function onEnd2(){
          panel.removeEventListener('transitionend', onEnd2);
          try { panel.parentNode && panel.parentNode.removeChild(panel); } catch(_){}
          try { pieces.outer.style.opacity='1'; pieces.inner.style.opacity='1'; pieces.inner.style.transform='scale(1)'; } catch(_){}
          try { anchor.style.zIndex = ''; } catch(_){}
        });
      } catch(_) {
        // Fallback: immediate restore
        try { panel.parentNode && panel.parentNode.removeChild(panel); } catch(_){}
        try { pieces.outer.style.opacity='1'; pieces.inner.style.opacity='1'; pieces.inner.style.transform='scale(1)'; } catch(_){}
        try { anchor.style.zIndex = ''; } catch(_){}
      }
    }

    // Expose closer for toggle branch
    try { anchor._walertsClose = doClose; } catch(_){}

    // Outside-click and ESC to close
    onDocClick = function(e){ try { if (panel && !panel.contains(e.target) && !anchor.contains(e.target)) { doClose(); } } catch(_){} };
    onKey = function(e){ try { var k = e.key || e.keyCode; if (k === 'Escape' || k === 'Esc' || k === 27) { doClose(); } } catch(_){} };
    try { document.addEventListener('click', onDocClick, true); } catch(_){}
    try { document.addEventListener('keydown', onKey, true); } catch(_){}

    // Trigger expansion
    requestAnimationFrame(function(){
      panel.classList.add('expanded');
      panel.style.height = targetHeight + 'px';
      // When transition ends, mark ready to fade in contents
      panel.addEventListener('transitionend', function onEnd(){
        panel.removeEventListener('transitionend', onEnd);
        panel.classList.add('ready');
      });
    });
  }

  window.WAlerts = {
    mountInline: function(anchor){
      try {
        var el = typeof anchor==='string'?document.querySelector(anchor):anchor; if(!el) return false;
        ensureStyles();
        // Clear anchor and mount
        try { while(el.firstChild) el.removeChild(el.firstChild); } catch(_){}
        var pieces = make('Alerts');
        el.appendChild(pieces.wrap);
        // Click to expand/collapse
        pieces.inner.addEventListener('click', function(e){ e.preventDefault(); expand(el, pieces); });
        // Keyboard accessibility
        pieces.inner.setAttribute('role','button'); pieces.inner.setAttribute('tabindex','0');
        pieces.inner.addEventListener('keydown', function(e){ if(e.key==='Enter' || e.key===' '){ e.preventDefault(); expand(el, pieces); } });
        return true;
      } catch(e){ return false; }
    }
  };
})();
