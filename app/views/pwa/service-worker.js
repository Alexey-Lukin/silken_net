// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ⚠️ ІНЕРТНИЙ [UI.18]: цей worker ніде не реєструється (нуль `navigator.serviceWorker`
// у дереві), і активація його — Phase 2 за окремим присудом. Тут живе лише КОНТРАКТ
// офлайн-черги; те, що робить контракт чесним (ідемпотентність), відвантажено обома
// половинами одразу, щоб у день реєстрації не довелось довіряти пам'яті.
//
// ⛔ Знято як мертве — не відбудовувати без споживача:
//   · `CACHE_NAME` — оголошувався й ніде не вживався, а `caches.match()` ходив у
//     сховище, яке ніхто не наповнював: офлайн-читання не існувало, зате
//     `respondWith(undefined)` перетворював будь-який офлайн-GET на мережеву
//     помилку замість власної офлайн-сторінки браузера;
//   · слухач `FORCE_SYNC` — єдиний можливий шлях флашу на iOS (Safari не має
//     Background Sync) — не мав ЖОДНОГО відправника, тобто обіцяв підтримку,
//     якої не було. Обовʼязок переїхав у чекбокс реєстрації `[ex-ARCH.16]`.
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
  if (event.request.method === 'POST' && event.request.url.includes('/maintenance_records')) {
    event.respondWith(handleOfflinePost(event.request));
  }
  // Решту не чіпаємо СВІДОМО: власного кешу цей worker не веде, тож будь-яка
  // «network-first, fallback to cache» гілка тут віддавала б `undefined`.
  // Не викликати `respondWith` = браузер обробляє запит сам, включно з власною
  // офлайн-поведінкою.
});

async function handleOfflinePost(request) {
  // 🔑 Ключ ідемпотентності народжується ДО першої спроби й переживає ВСІ повтори.
  // Саме перша спроба є найнебезпечнішою: якщо сервер прийняв запис, а відповідь
  // загубилась у дорозі, `fetch` кидає — ми йдемо в офлайн-гілку й ставимо в чергу
  // запит, який УЖЕ виконано. Без спільного ключа флаш створив би другий запис про
  // те саме втручання, а на записах обслуговування рахується `critical_unmaintained?`
  // у слешинг-тракті. Тому ключ ставиться на запит, а не на повтор.
  const idempotencyKey = crypto.randomUUID();
  const keyedHeaders = new Headers(request.headers);
  keyedHeaders.set('Idempotency-Key', idempotencyKey);
  const keyedRequest = new Request(request, { headers: keyedHeaders });
  const clonedRequest = keyedRequest.clone();

  try {
    // 1. Спроба відправити дані на Королеву (онлайн)
    return await fetch(keyedRequest);
  } catch (error) {
    // 2. ЗВ'ЯЗКУ НЕМАЄ: Запускаємо Кенозис (Офлайн-збереження)

    // Парсимо payload. Оскільки це Rails Turbo, це найчастіше FormData або JSON
    let payload;
    const contentType = clonedRequest.headers.get('content-type') || '';
    const isJson = contentType.includes('application/json');

    if (isJson) {
      payload = await clonedRequest.json();
    } else {
      const formData = await clonedRequest.formData();
      payload = Object.fromEntries(formData.entries());
    }

    // Зберігаємо запит у локальний банк пам'яті.
    // `isJson` зберігається ОКРЕМИМ полем, бо на флаші заголовок `content-type`
    // доводиться викидати (нижче), і після цього відновити форму тіла нізвідки.
    await saveToQueue({
      url: clonedRequest.url,
      headers: [...clonedRequest.headers.entries()],
      payload: payload,
      isJson: isJson,
      idempotencyKey: idempotencyKey,
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

async function flushQueue() {
  const queue = await getQueue();
  if (queue.length === 0) return;

  for (const item of queue) {
    try {
      const headers = new Headers(item.headers);

      // Той САМИЙ ключ, що й на першій спробі — інакше сервер не має чим
      // упізнати повтор, і вся конструкція вироджується в лічильник дублів.
      if (item.idempotencyKey) {
        headers.set('Idempotency-Key', item.idempotencyKey);
      }

      // ⚠️ `content-type` збереженого запиту ВИКИДАЄМО для не-JSON: у multipart
      // він несе boundary ПЕРШОГО тіла, а `createFormData` будує нове зі своїм —
      // явно заданий заголовок заважає браузеру перегенерувати boundary, і сервер
      // не розбирає тіло взагалі. Тобто повтор запису з фото падав би завжди,
      // а це рівно доказовий випадок.
      if (!item.isJson) {
        headers.delete('content-type');
      }

      // Формуємо запит із збережених даних
      const response = await fetch(item.url, {
        method: 'POST',
        headers: headers,
        body: item.isJson
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
