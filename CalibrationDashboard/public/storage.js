const DATABASE = 'ciggy-motion-review-v1';
let database;
async function open() {
  if (!database) database = new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE, 1);
    request.onupgradeneeded = () => request.result.createObjectStore('sessions', { keyPath: 'id' });
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(new Error('Your browser could not open saved recordings. Allow site storage or use another browser.'));
  });
  return database;
}
export async function loadSessions() {
  const db = await open();
  return new Promise((resolve, reject) => {
    const request = db.transaction('sessions').objectStore('sessions').getAll();
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(new Error('Saved recordings could not be read.'));
  });
}
export async function saveSessions(sessions, removedIDs = []) {
  const db = await open();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction('sessions', 'readwrite');
    const store = transaction.objectStore('sessions');
    removedIDs.forEach(id => store.delete(id));
    sessions.forEach(session => store.put(session));
    transaction.oncomplete = resolve;
    transaction.onabort = transaction.onerror = () => reject(new Error('Your changes could not be saved. Export a backup or free browser storage.'));
  });
}
