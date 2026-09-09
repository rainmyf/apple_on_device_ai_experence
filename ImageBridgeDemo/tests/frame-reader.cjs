const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = path.join(__dirname, '../HarmonyOS/entry/src/main/ets/protocol/FrameReader.ets');
assert.ok(fs.existsSync(file), 'production FrameReader must exist');
const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
const mod = {exports:{}};
new Function('exports', 'require', 'module', code)(mod.exports, require, mod);
const {FrameReader} = mod.exports;
const packet = Buffer.from([3,0,0,0,11,22,33]);
for(let split=0;split<=packet.length;split++) {
 const reader = new FrameReader();
 let image = reader.push(new Uint8Array(packet.subarray(0,split)));
 image = reader.push(new Uint8Array(packet.subarray(split))) || image;
 assert.deepEqual([...image], [11,22,33]);
}
let reader = new FrameReader();
for(const byte of packet) reader.push(new Uint8Array([byte]));
assert.equal(reader.complete, true);
for(const size of [0,20*1024*1024+1,0xffffffff]) {
 const header = Buffer.alloc(4); header.writeUInt32LE(size);
 assert.throws(()=>new FrameReader().push(new Uint8Array(header)), /size/);
}
assert.throws(()=>new FrameReader().push(new Uint8Array([...packet,1])), /trailing/);
assert.throws(()=>reader.push(new Uint8Array([1])), /trailing/);
const partial=new FrameReader(); assert.equal(partial.push(new Uint8Array([3,0,0,0,1])),undefined); assert.equal(partial.complete,false);
console.log('PASS: 8 fragment boundaries, bytewise input, 3 bad lengths, trailing data, incomplete payload');
const limitedHeader = Buffer.alloc(4); limitedHeader.writeUInt32LE(65537);
assert.throws(()=>new FrameReader(65536).push(new Uint8Array(limitedHeader)), /size/);
const exact = Buffer.alloc(4 + 65536, 65); exact.writeUInt32LE(65536);
assert.equal(new FrameReader(65536).push(new Uint8Array(exact)).length, 65536);
console.log('PASS: message-specific 64 KiB bound without changing image bound');
