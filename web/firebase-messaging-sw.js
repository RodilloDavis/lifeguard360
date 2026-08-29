// web/firebase-messaging-sw.js
//
// Firebase Cloud Messaging service worker for Flutter Web.
// This file MUST live at the root of your project's `web/` folder
// (i.e. alongside web/index.html), so it is served at:
//   http://<host>/firebase-messaging-sw.js
//
// It is plain JavaScript — Flutter does not compile it, it is copied
// as-is into the web build output.

importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

// Same values as DefaultFirebaseOptions.web in lib/firebase_options.dart
firebase.initializeApp({
  apiKey: 'AIzaSyCk9_Lc6Osz3Xs1WhYKzF3CfUpTImn1704',
  authDomain: 'lifeguard-cefd9.firebaseapp.com',
  databaseURL:
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app',
  projectId: 'lifeguard-cefd9',
  storageBucket: 'lifeguard-cefd9.firebasestorage.app',
  messagingSenderId: '579792179500',
  appId: '1:579792179500:web:3bd106cbfd68d985705c89',
  measurementId: 'G-BK036BXCJ0',
});

const messaging = firebase.messaging();

// Handles push notifications that arrive while the web app/tab is
// in the background or closed.
messaging.onBackgroundMessage((payload) => {
  console.log(
    '[firebase-messaging-sw.js] Received background message:',
    payload,
  );

  const notificationTitle =
    payload.notification?.title || 'LifeGuard360';
  const notificationOptions = {
    body: payload.notification?.body || '',
    icon: '/icons/Icon-192.png',
    data: payload.data || {},
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
