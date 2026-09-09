import React from 'react';
import ReactDOM from 'react-dom/client';
import { RouterProvider } from './router';
import { App } from './App';
import './styles/app.css';
import './styles/simulator.css';
import './styles/polish.css';
import './console/console.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <RouterProvider>
      <App />
    </RouterProvider>
  </React.StrictMode>
);
