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
})();
