// Reports failed requests of the embedded page (method, host, status only; no
// bodies, headers or query strings) so a hanging login can be told apart from
// a blocked host.
const String kMovixNetProbe = '''
(function () {
  if (window.__tbNetProbe) return;
  window.__tbNetProbe = true;
  function send(o) {
    try { window.chrome.webview.postMessage(o); } catch (e) {}
  }
  function where(u) {
    try {
      var a = new URL(u, location.href);
      return a.host + a.pathname.slice(0, 48);
    } catch (e) { return String(u).slice(0, 48); }
  }
  var f = window.fetch;
  if (f) {
    window.fetch = function (input, init) {
      var u = typeof input === 'string' ? input : (input && input.url);
      var m = (init && init.method) || 'GET';
      return f.apply(this, arguments).then(function (r) {
        if (!r.ok) send({k: 'fetch', m: m, u: where(u), s: r.status});
        return r;
      }, function (e) {
        send({k: 'fetch-error', m: m, u: where(u), e: String(e).slice(0, 80)});
        throw e;
      });
    };
  }
  var open = XMLHttpRequest.prototype.open;
  var sendX = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (m, u) {
    this.__m = m; this.__u = u;
    return open.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function () {
    var x = this;
    x.addEventListener('loadend', function () {
      if (x.status === 0 || x.status >= 400) {
        send({k: 'xhr', m: x.__m, u: where(x.__u), s: x.status});
      }
    });
    return sendX.apply(this, arguments);
  };
  window.addEventListener('error', function (e) {
    var t = e.target;
    if (t && (t.src || t.href)) send({k: 'resource', u: where(t.src || t.href)});
    else send({k: 'js', e: String(e.message).slice(0, 120)});
  }, true);
  window.addEventListener('unhandledrejection', function (e) {
    send({k: 'reject', e: String(e.reason).slice(0, 120)});
  });
})();
''';
