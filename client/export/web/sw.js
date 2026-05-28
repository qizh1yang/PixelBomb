/**
 * Service Worker — 基于 manifest.json 的版本化缓存
 *
 * - manifest.json / index.html → Network-First (永不过期缓存)
 * - game.{hash}.* → Cache-First (不可变, URL 唯一)
 * - 旧版本缓存 → activate 时自动清理
 */
(function () {
  'use strict';

  var CORE_ASSETS = [
    '/', '/index.html', '/manifest.json', '/version-detector.js',
    '/index.js', '/index.audio.position.worklet.js', '/index.audio.worklet.js',
    '/index.icon.png', '/index.apple-touch-icon.png', '/index.png'
  ];

  function fetchVersion() {
    return fetch('/manifest.json?v=' + Date.now(), { cache: 'no-cache' })
      .then(function (res) { return res.ok ? res.json() : Promise.reject(); })
      .then(function (m) { return m.version || 'unknown'; })
      .catch(function () { return 'default-v1'; });
  }

  function cacheName(v) { return 'pb-cache-' + v; }

  function isVersionedAsset(pathname) {
    return /\/game\.[a-f0-9]{7,}\.(pck|wasm)$/i.test(pathname) ||
           /\/game\.\d{8}-\d{6}\.(pck|wasm)$/i.test(pathname);
  }

  self.addEventListener('install', function (event) {
    console.log('[SW] install');
    event.waitUntil(
      fetchVersion().then(function (version) {
        return caches.open(cacheName(version)).then(function (cache) {
          return Promise.all(CORE_ASSETS.map(function (url) {
            var fetchUrl = url === '/' ? url : url + '?v=' + version;
            return fetch(fetchUrl, { cache: 'no-cache' }).then(function (res) {
              if (res.ok) return cache.put(url, res);
            }).catch(function () {});
          }));
        });
      }).then(function () { return self.skipWaiting(); })
    );
  });

  self.addEventListener('activate', function (event) {
    console.log('[SW] activate');
    event.waitUntil(
      fetchVersion().then(function (currentVersion) {
        var active = cacheName(currentVersion);
        return caches.keys().then(function (keys) {
          return Promise.all(keys.map(function (k) {
            if (k.startsWith('pb-cache-') && k !== active) {
              console.log('[SW] 清理旧缓存: ' + k);
              return caches.delete(k);
            }
          }));
        });
      }).then(function () { return self.clients.claim(); })
    );
  });

  self.addEventListener('fetch', function (event) {
    var url = new URL(event.request.url);

    // Network-First: 入口 + 版本检测文件
    if (url.pathname === '/' ||
        url.pathname.endsWith('index.html') ||
        url.pathname.endsWith('manifest.json') ||
        url.pathname.endsWith('sw.js') ||
        url.pathname.endsWith('version-detector.js')) {
      event.respondWith(fetch(event.request));
      return;
    }

    // Cache-First: 版本化不可变资源
    if (isVersionedAsset(url.pathname)) {
      event.respondWith(
        caches.match(event.request, { ignoreSearch: true }).then(function (cached) {
          return cached || fetch(event.request).then(function (res) {
            if (res.ok) {
              var clone = res.clone();
              caches.open('pb-cache-versioned').then(function (c) { c.put(event.request, clone); });
            }
            return res;
          });
        })
      );
      return;
    }

    // Cache-First + 网络回填
    event.respondWith(
      caches.match(event.request, { ignoreSearch: true }).then(function (cached) {
        return cached || fetch(event.request).then(function (res) {
          if (res.ok && res.type === 'basic') {
            var clone = res.clone();
            fetchVersion().then(function (v) {
              return caches.open(cacheName(v));
            }).then(function (c) { c.put(event.request, clone); });
          }
          return res;
        });
      })
    );
  });

  self.addEventListener('message', function (event) {
    if (event.data && event.data.type === 'SKIP_WAITING') {
      console.log('[SW] SKIP_WAITING');
      self.skipWaiting();
    }
  });
})();
