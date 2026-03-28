import React, { useState, useEffect } from 'react';
import { RefreshCw, Download, Check, X, RotateCw } from 'lucide-react';

const CURRENT_VERSION = __APP_VERSION__;

// Get IPC renderer if in Electron
const ipcRenderer = (() => {
  try {
    if (window.require) return window.require('electron').ipcRenderer;
  } catch (e) {}
  return null;
})();

export function UpdateChecker() {
  const [status, setStatus] = useState('idle');
  const [latestVersion, setLatestVersion] = useState('');
  const [downloadPercent, setDownloadPercent] = useState(0);
  const [showToast, setShowToast] = useState(false);

  useEffect(() => {
    if (!ipcRenderer) return;

    const handler = (event, data) => {
      switch (data.status) {
        case 'checking':
          setStatus('checking');
          break;
        case 'available':
          setStatus('available');
          setLatestVersion(data.version);
          setShowToast(true);
          break;
        case 'uptodate':
          setStatus('uptodate');
          setTimeout(() => setStatus('idle'), 3000);
          break;
        case 'downloading':
          setStatus('downloading');
          setDownloadPercent(data.percent);
          setShowToast(true);
          break;
        case 'downloaded':
          setStatus('downloaded');
          setLatestVersion(data.version);
          setShowToast(true);
          break;
        case 'error':
          setStatus('error');
          setTimeout(() => setStatus('idle'), 4000);
          break;
      }
    };

    ipcRenderer.on('update-status', handler);
    return () => ipcRenderer.removeListener('update-status', handler);
  }, []);

  const checkForUpdate = () => {
    if (ipcRenderer) {
      ipcRenderer.send('check-for-update');
    }
  };

  const downloadUpdate = () => {
    if (ipcRenderer) {
      ipcRenderer.send('download-update');
    }
  };

  const installUpdate = () => {
    if (ipcRenderer) {
      ipcRenderer.send('install-update');
    }
  };

  const dismissToast = () => setShowToast(false);

  return (
    <>
      <div className="update-checker">
        {status === 'idle' && (
          <button className="update-btn" onClick={checkForUpdate} title="Проверить обновления">
            <RefreshCw size={12} />
            <span>v{CURRENT_VERSION}</span>
          </button>
        )}

        {status === 'checking' && (
          <button className="update-btn checking" disabled>
            <RefreshCw size={12} className="spin" />
          </button>
        )}

        {status === 'available' && (
          <button className="update-btn available" onClick={downloadUpdate} title={`Скачать ${latestVersion}`}>
            <Download size={12} />
            <span>{latestVersion}</span>
          </button>
        )}

        {status === 'downloading' && (
          <button className="update-btn downloading" disabled>
            <RefreshCw size={12} className="spin" />
            <span>{downloadPercent}%</span>
          </button>
        )}

        {status === 'downloaded' && (
          <button className="update-btn downloaded" onClick={installUpdate} title="Установить и перезапустить">
            <RotateCw size={12} />
            <span>Установить</span>
          </button>
        )}

        {status === 'uptodate' && (
          <button className="update-btn uptodate" disabled>
            <Check size={12} />
          </button>
        )}

        {status === 'error' && (
          <button className="update-btn error-state" onClick={checkForUpdate}>
            <X size={12} />
          </button>
        )}
      </div>

      {/* Toast notifications */}
      {showToast && status === 'available' && (
        <div className="update-toast">
          <div className="toast-content">
            <Download size={16} />
            <div className="toast-text">
              <strong>Доступно обновление {latestVersion}</strong>
              <span>Текущая: v{CURRENT_VERSION}</span>
            </div>
          </div>
          <div className="toast-actions">
            <button className="toast-download" onClick={() => { downloadUpdate(); dismissToast(); }}>Обновить</button>
            <button className="toast-dismiss" onClick={dismissToast}>Позже</button>
          </div>
        </div>
      )}

      {showToast && status === 'downloading' && (
        <div className="update-toast">
          <div className="toast-content">
            <RefreshCw size={16} className="spin" />
            <div className="toast-text">
              <strong>Загрузка обновления...</strong>
              <div className="progress-bar">
                <div className="progress-fill" style={{ width: `${downloadPercent}%` }}></div>
              </div>
            </div>
          </div>
        </div>
      )}

      {showToast && status === 'downloaded' && (
        <div className="update-toast">
          <div className="toast-content">
            <Check size={16} />
            <div className="toast-text">
              <strong>Обновление готово!</strong>
              <span>Версия {latestVersion} загружена</span>
            </div>
          </div>
          <div className="toast-actions">
            <button className="toast-download" onClick={installUpdate}>Перезапустить</button>
            <button className="toast-dismiss" onClick={dismissToast}>Позже</button>
          </div>
        </div>
      )}
    </>
  );
}
