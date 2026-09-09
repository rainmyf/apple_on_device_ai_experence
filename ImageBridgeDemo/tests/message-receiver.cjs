const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
function load(name) {
 const file=path.join(__dirname,'../HarmonyOS/entry/src/main/ets',name+'.ets');
 const code=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020,experimentalDecorators:true}}).outputText;
 const mod={exports:{}};
 new Function('exports','require','module','ObservedV2','Trace',code)(mod.exports,(id)=>{
  if(id.includes('FrameReader'))return load('protocol/FrameReader');
  if(id==='@kit.ArkTS')return {util:{TextDecoder:{create:(enc,opts)=>({decodeToString:(bytes)=>new TextDecoder(enc,opts).decode(bytes)})},TextEncoder:class {encodeInto(text){return new TextEncoder().encode(text)}}}};
  return {};
 },mod,c=>c,()=>{});
 return mod.exports;
}
const {MessageReceiver,MessageModel}=load('services/MessageReceiver');
function fixture(show) {
 const model=new MessageModel(),acks=[];
 const client={send:async ({data})=>acks.push([...new Uint8Array(data)]),close:async()=>{}};
 const receiver=new MessageReceiver({},model,show); receiver.client=client;
 return {model,acks,client,receiver};
}
(async()=>{
 for(const original of ['  原文 📱🙂\n\n第二行  ','\uFEFF开头BOM','\t\r\n','a'.repeat(65536)]) {
  let body;const f=fixture(async text=>{body=text});
  await f.receiver.display(f.client,new TextEncoder().encode(original),0);
  assert.equal(body,original);assert.equal(f.model.lastText,original);assert.deepEqual(f.acks,[[0]]);
 }
 for(const bytes of [[0xc3,0x28],[0xed,0xa0,0x80],[0xf4,0x90,0x80,0x80],[0xff]]) {
  let called=false;const f=fixture(async()=>{called=true});
  await f.receiver.display(f.client,new Uint8Array(bytes),0);
  assert.equal(called,false);assert.equal(f.model.lastText,'');assert.deepEqual(f.acks,[[1]]);
 }
 const f=fixture(async()=>{throw Error('notification disabled')});
 for(const text of ['first','same','same']) {
  f.receiver.client=f.client;
  await f.receiver.display(f.client,new TextEncoder().encode(text),0);
 }
 assert.deepEqual(f.model.messages,['first','same','same']);
 assert.equal(f.model.receivedCount,3);assert.deepEqual(f.acks,[[0],[0],[0]]);
 console.log('PASS: original text, invalid UTF8 rejection, ordered append, duplicate text retained, notification failure does not reject receipt');
})().catch(error=>{console.error(error);process.exitCode=1});
