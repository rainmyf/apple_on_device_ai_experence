const assert=require('node:assert/strict');const fs=require('node:fs');
const ts=require('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source=fs.readFileSync(__dirname+'/../HarmonyOS/entry/src/main/ets/protocol/BatchFrameReader.ets','utf8');
const m={exports:{}};new Function('exports','module',ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText)(m.exports,m);
const {BatchFrameReader}=m.exports;const u=n=>{let b=Buffer.alloc(4);b.writeUInt32LE(n);return b};const header=n=>Buffer.concat([Buffer.from('IBAT'),u(n)]);const frame=Buffer.concat([header(2),u(3),Buffer.from([1,2,3])]);
for(let i=0;i<=frame.length;i++){let r=new BatchFrameReader();let b=r.push(frame.subarray(0,i));b=r.push(frame.subarray(i))||b;assert.deepEqual([...b],[1,2,3]);assert.throws(()=>r.push(u(1)),/ACK/);r.acknowledge();assert.deepEqual([...r.push(Buffer.concat([u(1),Buffer.from([4])]))],[4]);assert.equal(r.isLast,true);r.acknowledge();assert.equal(r.complete,true);}
for(const n of [0,21,0xffffffff])assert.throws(()=>new BatchFrameReader().push(header(n)),/count/);
for(const n of [0,20*1024*1024+1])assert.throws(()=>new BatchFrameReader().push(Buffer.concat([header(1),u(n)])),/size/);
let r=new BatchFrameReader();assert.throws(()=>r.push(Buffer.concat([frame,Buffer.from([1])])),/ACK/);
r=new BatchFrameReader();r.push(header(6));for(let i=0;i<5;i++){r.push(Buffer.concat([u(20*1024*1024),Buffer.alloc(20*1024*1024)]));r.acknowledge();}assert.throws(()=>r.push(u(1)),/total/);
console.log('PASS batch fragmentation, ACK gate, count/length/total bounds, final completion');
