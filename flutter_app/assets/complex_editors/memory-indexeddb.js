import * as memory from '/vendor/fake-indexeddb/build/esm/index.js';
// PPTist uses Dexie for temporary editing history. Keep its real API semantics
// in memory; durable note recovery remains the application's responsibility.
for (const name of ['indexedDB','IDBCursor','IDBCursorWithValue','IDBDatabase','IDBFactory','IDBIndex','IDBKeyRange','IDBObjectStore','IDBOpenDBRequest','IDBRequest','IDBTransaction','IDBVersionChangeEvent']) {
  Object.defineProperty(window, name, {value: memory[name], writable: false, configurable: false});
}
Object.defineProperty(window,'webkitIndexedDB',{value:memory.indexedDB,writable:false,configurable:false});
Object.defineProperty(window,'__BookStarkMemoryIndexedDB',{value:true,writable:false,configurable:false});
