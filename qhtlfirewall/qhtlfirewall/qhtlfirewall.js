// Scoped UI behavior for QhtLink Firewall within WHM (Jupiter)
(function () {
  'use strict';

  var app = document.getElementById('qhtlf-app') || document;

  function onReady(fn) {
    if (document.readyState !== 'loading') {
      fn();
    } else {
      document.addEventListener('DOMContentLoaded', fn);
    }
  }

  function scrollBottom() {
    return document.documentElement.scrollHeight - window.scrollY - window.innerHeight;
  }

  onReady(function () {
    var loader = document.getElementById('loader');
    if (loader) loader.style.display = 'none';

    var docsLink = document.getElementById('docs-link');
    if (docsLink) docsLink.style.display = 'none';

    var topLink = document.getElementById('toplink');
    var botLink = document.getElementById('botlink');

    function updateAffordances() {
      if (botLink) botLink.style.display = (window.scrollY > 500 ? 'block' : 'none');
      if (topLink) topLink.style.display = (scrollBottom() > 500 ? 'block' : 'none');
    }

    updateAffordances();
    window.addEventListener('scroll', updateAffordances);

    if (botLink) {
      botLink.addEventListener('click', function () {
        window.scrollTo({ top: 0, behavior: 'smooth' });
      });
    }
    if (topLink) {
      topLink.addEventListener('click', function () {
        window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'smooth' });
      });
    }
  });

  // Sparkle effect on hover for elements with .qhtlf-sparkle
  function sparkle(el) {
    var rect = el.getBoundingClientRect();
    var colors = ['#ffd166', '#f4978e', '#c2f970', '#9d4edd', '#4cc9f0'];

    function createParticle(x, y) {
      var p = document.createElement('span');
      p.className = 'qhtlf-sparkle-particle';
      var color = colors[(Math.random() * colors.length) | 0];
      p.style.background = color;
      el.appendChild(p);

      // Place at relative position within button
      var localX = x - rect.left;
      var localY = y - rect.top;
      p.style.left = localX + 'px';
      p.style.top = localY + 'px';

      // Random direction and distance (~25px radius)
      var angle = Math.random() * Math.PI * 2;
      var distance = 15 + Math.random() * 10; // 15-25px
      var tx = Math.cos(angle) * distance;
      var ty = Math.sin(angle) * distance;

      // Animate using CSS transforms
      var duration = 400 + Math.random() * 250; // 400-650ms
      var start = performance.now();

      function frame(now) {
        var t = (now - start) / duration;
        if (t > 1) t = 1;
        // ease-out
        var ease = 1 - Math.pow(1 - t, 3);
        p.style.transform = 'translate(' + (tx * ease) + 'px,' + (ty * ease) + 'px) scale(' + (1 - 0.5 * ease) + ')';
        p.style.opacity = String(1 - ease);
        if (t < 1) {
          requestAnimationFrame(frame);
        } else {
          if (p && p.parentNode) p.parentNode.removeChild(p);
        }
      }
      requestAnimationFrame(frame);
    }

    function onMove(e) {
      rect = el.getBoundingClientRect();
      var x = e.clientX;
      var y = e.clientY;
      // spawn a few particles per move
      for (var i = 0; i < 3; i++) createParticle(x, y);
    }

    function onEnter() {
      el.addEventListener('mousemove', onMove);
    }

    function onLeave() {
      el.removeEventListener('mousemove', onMove);
    }

    el.addEventListener('mouseenter', onEnter);
    el.addEventListener('mouseleave', onLeave);
  }

  onReady(function () {
    var sparkles = document.querySelectorAll('.qhtlf-sparkle');
    for (var i = 0; i < sparkles.length; i++) sparkle(sparkles[i]);
  });
})();
