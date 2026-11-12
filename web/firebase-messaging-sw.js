// Firebase Cloud Messaging service worker for the Hishobkr web app.
// Must be served from the site root (/firebase-messaging-sw.js): the Firebase
// web SDK registers it there by default. nginx maps that path to this file
// inside the /login/ build. SDK version matches firebase_core_web's JS SDK.
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyA2dsni3Rb52O7ZcNczmC9Vvqo3hE-sI-0',
  appId: '1:329235285394:web:56bd453690fa9cd5336d4b',
  messagingSenderId: '329235285394',
  projectId: 'hishobkr-pos',
  authDomain: 'hishobkr-pos.firebaseapp.com',
  storageBucket: 'hishobkr-pos.firebasestorage.app',
});

// Messages with a `notification` payload are shown by the SDK automatically
// while the tab is in the background; foreground ones go to onMessage in Dart.
const messaging = firebase.messaging();

// Clicking a notification focuses the open app tab, or opens it.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if (c.url.includes('/login/') && 'focus' in c) return c.focus();
      }
      return clients.openWindow('/login/');
    }),
  );
});
