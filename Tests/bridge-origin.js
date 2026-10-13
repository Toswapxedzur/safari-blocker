// Actual generated Safari socket receiver; no native peer/provider acceptance.
'use strict';
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), assert = require('node:assert/strict');
const root = path.join(__dirname, '..', 'extension');
const source = fs.readFileSync(path.join(root, 'background.js'), 'utf8');
const begin = source.indexOf('const cbConnection = {'), end = source.indexOf('\n};\n\n// Classifier requests share', begin);
assert(begin >= 0 && end > begin);
const snapshots = [], sockets = [];let gets = 0;
class Socket { static OPEN = 1;constructor() { this.readyState = 1;sockets.push(this); }close() {} }
const context = vm.createContext({ console, navigator: { userAgent: 'Safari' }, WebSocket: Socket,
  CB_FIXED_ADDRESS: 'ws://fixture.invalid', CB_CONNECTION_PROTOCOL_VERSION: 4, CB_CONNECTION_BURST_WINDOW_MS: 5000,
  CB_CONNECTION_PING_MS: 20000, cbJoinsSent: new Set(), setTimeout: () => 1, setInterval: () => 1, clearTimeout() {}, clearInterval() {},
  cbClassifierHub: { rejectAll() {} }, cbActivity: { beginSettingsConnection() {}, refreshSettings() { gets++; },
    async applyNativeSettingsSnapshot(body, generation) { snapshots.push({ body: JSON.parse(JSON.stringify(body)), generation }); } } });
context.self = context;
vm.runInContext(fs.readFileSync(path.join(root, 'bridge-protocol.js'), 'utf8'), context);
vm.runInContext(source.slice(begin, end + 3) + ';globalThis.connection=cbConnection;', context);
const receiver = context.connection;receiver.setStatus = patch => { receiver.status = { ...receiver.status, ...patch }; };
receiver.connect();const first = sockets.at(-1), obsoleteReceive = first.onmessage;
first.onmessage({ data: JSON.stringify({ kind: 'welcome', v: 4, hubProgram: 'macapp', peers: [], activitySettingsNotifications: true }) });
assert.equal(receiver.activitySettingsNotifications, true);assert.equal(gets, 1);
const body = { settings: { byCategory: { 'web-visit': { enabled: true }, 'content-watched': { enabled: false } } },
  epoch: 'F9E22CB3-6D62-4251-A995-D8CF84E75C79', revision: 7, changedAtMs: 123456.75 };
first.onmessage({ data: JSON.stringify({ kind: 'activity-settings-updated', body }) });
assert.deepEqual(snapshots[0].body, body);assert.equal(snapshots[0].generation, receiver.activitySettingsConnectionGeneration);
console.log('PASS generated Safari native-hub frame preserves capability and complete provenance metadata');
receiver.connect();obsoleteReceive({ data: JSON.stringify({ kind: 'activity-settings-updated', body: { ...body, revision: 8 } }) });
assert.equal(snapshots.length, 1);
console.log('PASS obsolete Safari socket cannot forward Activity authority after reconnect');
const classifier = sockets.at(-1);classifier.onmessage({ data: JSON.stringify({ kind: 'welcome', v: 4, hubProgram: 'classifier', peers: [], activitySettingsNotifications: true }) });
classifier.onmessage({ data: JSON.stringify({ kind: 'activity-settings-updated', body }) });
assert.equal(receiver.activitySettingsNotifications, false);assert.equal(snapshots.length, 1);assert.equal(gets, 1);
console.log('PASS classifier-origin welcome and push cannot authorize Safari Activity capture');
console.log('__CB_TEST_RESULT__: OK (generated socket-source fixture only, no native/provider runtime acceptance)');
