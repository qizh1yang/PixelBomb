/**
 * GameVersionManager — 基于 manifest.json 的版本检测
 *
 * - 轮询 /manifest.json 比对 version 字段
 * - 检测到新版本 → 显示更新 UI → SW skipWaiting + 重载
 */
(function () {
  'use strict';

  function GameVersionManager(options) {
    options = options || {};
    this.checkInterval = options.checkInterval || 2 * 60 * 1000;
    this.timer = null;
    this.isUpdating = false;
    this.localVersion = this._getLocalVersion();
  }

  GameVersionManager.prototype._getLocalVersion = function () {
    if (window.__GAME_VERSION__) return window.__GAME_VERSION__;
    return 'loaded-' + Date.now();
  };

  GameVersionManager.prototype.init = function () {
    console.log('[VersionManager] 本地版本: ' + this.localVersion);
    this._registerSW();
    this._startPolling();
    this._listenSW();
  };

  GameVersionManager.prototype._registerSW = function () {
    if (!('serviceWorker' in navigator)) return;
    var self = this;
    window.addEventListener('load', function () {
      navigator.serviceWorker.register('/sw.js', { scope: '/' })
        .then(function (reg) {
          console.log('[VersionManager] SW 已注册');
          if (reg.waiting) self._onNewVersion();
        })
        .catch(function (e) { console.error('[VersionManager] SW 注册失败:', e); });
    });
  };

  GameVersionManager.prototype._startPolling = function () {
    var self = this;
    if (this.timer) clearInterval(this.timer);
    setTimeout(function () { self._check(); }, 10000);
    this.timer = setInterval(function () { self._check(); }, this.checkInterval);
  };

  GameVersionManager.prototype._check = function () {
    if (this.isUpdating) return;
    var self = this;
    fetch('/manifest.json?v=' + Date.now(), { cache: 'no-cache' })
      .then(function (res) { return res.ok ? res.json() : Promise.reject(); })
      .then(function (manifest) {
        if (manifest.version && manifest.version !== self.localVersion) {
          console.log('[VersionManager] 新版本: ' + self.localVersion + ' → ' + manifest.version);
          window.__NEW_VERSION__ = manifest.version;
          self._onNewVersion();
        }
      }).catch(function () {});
  };

  GameVersionManager.prototype._onNewVersion = function () {
    this.isUpdating = true;
    this._showUI();
  };

  GameVersionManager.prototype._showUI = function () {
    var id = 'game-update-dialog';
    if (document.getElementById(id)) return;
    var newVer = window.__NEW_VERSION__ || '最新';

    var d = document.createElement('div');
    d.id = id;
    d.style.cssText = 'position:fixed;top:0;left:0;width:100vw;height:100vh;background:rgba(0,0,0,0.85);display:flex;align-items:center;justify-content:center;z-index:99999;font-family:sans-serif;color:#fff;text-align:center;backdrop-filter:blur(8px);';

    d.innerHTML =
      '<div style="background:#1e1e24;padding:40px;border-radius:16px;box-shadow:0 10px 30px rgba(0,0,0,0.5);max-width:400px;width:90%;">' +
      '<h2 style="margin-top:0;color:#00e5ff;font-size:22px;">游戏版本已更新</h2>' +
      '<p style="color:#b0bec5;font-size:14px;line-height:1.6;margin-bottom:30px;">检测到新版本 <b style="color:#00e5ff;">' + newVer + '</b>，建议立即重启。</p>' +
      '<button id="btn-update-now" style="background:linear-gradient(135deg,#00b0ff,#00e5ff);border:none;padding:12px 30px;border-radius:25px;color:#121214;font-weight:bold;cursor:pointer;font-size:16px;width:100%;">立即重启</button>' +
      '<button id="btn-update-later" style="background:transparent;border:1px solid #37474f;padding:10px 20px;border-radius:25px;color:#90a4ae;margin-top:15px;cursor:pointer;font-size:14px;width:100%;">稍后（对局结束后生效）</button>' +
      '</div>';

    document.body.appendChild(d);

    var self = this;
    document.getElementById('btn-update-now').addEventListener('click', function () { self._reload(); });
    document.getElementById('btn-update-later').addEventListener('click', function () {
      d.remove();
      self.isUpdating = false;
      self._idleReload();
    });
  };

  GameVersionManager.prototype._reload = function () {
    console.log('[VersionManager] 触发重载');
    if (navigator.serviceWorker && navigator.serviceWorker.controller) {
      navigator.serviceWorker.getRegistration().then(function (reg) {
        if (reg && reg.waiting) reg.waiting.postMessage({ type: 'SKIP_WAITING' });
        else window.location.reload(true);
      });
    } else {
      window.location.reload(true);
    }
  };

  GameVersionManager.prototype._idleReload = function () {
    var self = this;
    var handler = function (e) {
      if (e.data === 'GAME_MATCH_FINISHED' || (e.data && e.data.type === 'GAME_MATCH_FINISHED')) {
        console.log('[VersionManager] 对局结束, 自动重载');
        window.removeEventListener('message', handler);
        self._reload();
      }
    };
    window.addEventListener('message', handler);
  };

  GameVersionManager.prototype._listenSW = function () {
    if (!('serviceWorker' in navigator)) return;
    var refreshing = false;
    navigator.serviceWorker.addEventListener('controllerchange', function () {
      if (!refreshing) { refreshing = true; window.location.reload(true); }
    });
  };

  window.versionManager = new GameVersionManager();
  window.versionManager.init();
})();
