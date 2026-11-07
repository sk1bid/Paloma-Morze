import { StrictMode, createElement } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import { task5DevelopmentEnabled } from './task5/development.js'

const root = createRoot(document.getElementById('root'));
const controller = new URLSearchParams(window.location.search).get('task5controller') === '1';
const developerLaunch = task5DevelopmentEnabled({ development: import.meta.env.DEV, previewBuild: import.meta.env.VITE_TASK5_DEV_TOOLS === '1', search: window.location.search });
if (controller) {
  if (developerLaunch) {
    import('./task5/DevelopmentController.jsx').then(module => root.render(createElement(StrictMode, null, createElement(module.DevelopmentController))));
  } else root.render(<p>Управление DEV недоступно в этой сборке.</p>);
} else {
  import('./App.jsx').then(module => root.render(createElement(StrictMode, null, createElement(module.default))));
}
