const CACHE_NAME = 'silken-net-matrix-v1';
const DB_NAME = 'SilkenNetDB';
const DB_VERSION = 1;
const STORE_NAME = 'maintenance_sync_queue';

// =========================================================================
// 1. БАНК ПАМ'ЯТІ (IndexedDB Setup)
// =========================================================================
function initDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onerror = (e) => reject('Помилка імпланту IndexedDB: ' + e.target.error);
    request.onsuccess = (e) => resolve(e.target.result);
    request.onupgradeneeded = (e) => {
      const db = e.target.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME, { keyPath: 'id', autoIncrement: true });
      }
    };
  });
}

async function saveToQueue(data) {
  const db = await initDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readwrite');
    const store = tx.objectStore(STORE_NAME);
    store.add(data).onsuccess = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

async function getQueue() {
  const db = await initDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readonly');
    const store = tx.objectStore(STORE_NAME);
    const request = store.getAll();
    request.onsuccess = () => resolve(request.result);
    tx.onerror = () => reject(tx.error);
  });
}

async function deleteFromQueue(id) {
  const db = await initDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readwrite');
    tx.objectStore(STORE_NAME).delete(id).onsuccess = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

// =========================================================================
// 2. ЖИТТЄВИЙ ЦИКЛ SERVICE WORKER
// =========================================================================
self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

// =========================================================================
// 3. ПЕРЕХОПЛЕННЯ ТРАФІКУ (The Zero-Lag Protocol)
// =========================================================================
self.addEventListener('fetch', (event) => {
  // Ловимо тільки POST-запити до нашого API створення записів обслуговування
  if (event.request.method === 'POST' && event.request.url.includes('/api/v1/maintenance_records')) {
    event.respondWith(handleOfflinePost(event.request));
  } else {
    // Стандартна логіка для інших запитів: Network-first, fallback to Cache
    event.respondWith(
      fetch(event.request).catch(() => caches.match(event.request))
    );
  }
});

async function handleOfflinePost(request) {
  const clonedRequest = request.clone();
  
  try {
    // 1. Спроба відправити дані на Королеву (онлайн)
    return await fetch(request);
  } catch (error) {
    // 2. ЗВ'ЯЗКУ НЕМАЄ: Запускаємо Кенозис (Офлайн-збереження)
    
    // Парсимо payload. Оскільки це Rails Turbo, це найчастіше FormData або JSON
    let payload;
    const contentType = clonedRequest.headers.get('content-type') || '';
    
    if (contentType.includes('application/json')) {
      payload = await clonedRequest.json();
    } else {
      const formData = await clonedRequest.formData();
      payload = Object.fromEntries(formData.entries());
    }

    // Зберігаємо запит у локальний банк пам'яті
    await saveToQueue({
      url: clonedRequest.url,
      headers: [...clonedRequest.headers.entries()],
      payload: payload,
      timestamp: new Date().getTime()
    });

    // Реєструємо системний тригер на відновлення зв'язку
    if ('sync' in self.registration) {
      await self.registration.sync.register('sync-maintenance');
    }

    // 3. Відповідаємо Turbo Streams фейковим успіхом.
    // Для UI це виглядає як миттєве збереження (Zero-Lag).
    return new Response(JSON.stringify({
      status: "queued",
      message: "⚡ Офлайн. Запис заархівовано. Синхронізація очікує на сигнал Королеви."
    }), {
      headers: { 'Content-Type': 'application/json' },
      status: 202 // HTTP 202 Accepted
    });
  }
}

// =========================================================================
// 4. СИНХРОНІЗАЦІЯ З БЕКЕНДОМ (Background Sync)
// =========================================================================
self.addEventListener('sync', (event) => {
  if (event.tag === 'sync-maintenance') {
    console.log("📡 [Background Sync] Зв'язок відновлено. Скидання буфера...");
    event.waitUntil(flushQueue());
  }
});

// Додатковий fallback для iOS (Safari не підтримує Background Sync)
self.addEventListener('message', (event) => {
  if (event.data === 'FORCE_SYNC') {
    event.waitUntil(flushQueue());
  }
});

async function flushQueue() {
  const queue = await getQueue();
  if (queue.length === 0) return;

  for (const item of queue) {
    try {
      const headers = new Headers(item.headers);
      
      // Формуємо запит із збережених даних
      const response = await fetch(item.url, {
        method: 'POST',
        headers: headers,
        body: headers.get('content-type').includes('application/json') 
                ? JSON.stringify(item.payload) 
                : createFormData(item.payload)
      });

      if (response.ok) {
        // Запис прийнято бекендом — видаляємо з локального імпланту
        await deleteFromQueue(item.id);
        notifyClients("Офлайн-дані успішно завантажені в Матрицю.");
      }
    } catch (err) {
      console.error('🛑 [Sync Error] Королева недоступна. Повтор пізніше.', err);
      throw err; // Прокидаємо помилку, щоб Service Worker спробував ще раз
    }
  }
}

// Утиліта: перетворення Object назад у FormData для Rails-контролера
function createFormData(obj) {
  const formData = new FormData();
  for (const key in obj) {
    formData.append(key, obj[key]);
  }
  return formData;
}

// Трансляція повідомлень на відкриті вкладки PWA
function notifyClients(message) {
  self.clients.matchAll().then(clients => {
    clients.forEach(client => client.postMessage({ type: 'SYNC_SUCCESS', message }));
  });
}
