const assert=require('node:assert/strict'),fs=require('node:fs');
const ts=require('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
let decline=false;
let events=[],failPreview=false,failDecode=false,files=new Map(),nextfd=1,handles=new Map();
function load(name){const m={exports:{}};let code=ts.transpileModule(fs.readFileSync(__dirname+'/../HarmonyOS/entry/src/main/ets/'+name+'.ets','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020,experimentalDecorators:true}}).outputText;new Function('exports','require','module','ObservedV2','Trace',code)(m.exports,id=>{
if(id.includes('ReceiverLifecycle'))return{ReceiverLifecycle:{foreground:true}};
if(id.includes('BatchFrameReader'))return load('protocol/BatchFrameReader');
if(id==='@kit.MediaLibraryKit')return{photoAccessHelper:{PhotoType:{IMAGE:1},getPhotoAccessHelper:()=>({showAssetsCreationDialog:async(src,configs)=>{events.push('consent');assert.equal(src.length,configs.length);return decline?[]:src.map((_,i)=>'media://'+i)},release:async()=>{}})}};
if(id==='@kit.ArkTS')return{util:{TextEncoder:class{encodeInto(s){return new TextEncoder().encode(s)}}}};
if(id==='@kit.ImageKit')return{image:{createImageSource:()=>({getImageInfo:async()=>({size:{width:100,height:100}}),createPixelMap:async()=>{if(failDecode)throw Error('decode');return{release:async()=>{}}},release:async()=>{}})}};
if(id==='@kit.CoreFileKit')return{fileUri:{getUriFromPath:p=>'file://'+p},fileIo:{OpenMode:{},copyFileSync:(src,fd)=>{files.set(handles.get(fd),files.get(src));events.push('copy')},listFileSync:p=>[...new Set([...files.keys()].filter(k=>k.startsWith(p+'/')).map(k=>k.slice(p.length+1).split('/')[0]))],readTextSync:p=>files.get(p)||'',openSync:p=>{handles.set(nextfd,p);return{fd:nextfd++}},writeSync:(fd,b)=>{files.set(handles.get(fd),b);events.push('write');return typeof b==='string'?Buffer.byteLength(b):b.byteLength},fsyncSync:()=>events.push('sync'),closeSync:()=>events.push('close'),renameSync:(a,b)=>files.set(b,files.get(a))}};
if(id==='@kit.PreviewKit')return{filePreview:{openPreview:async()=>{events.push('preview');if(failPreview)throw Error('no preview')}}};return{};
},m,c=>c,()=>{});return m.exports}
const{ImageReceiver,ReceiverModel}=load('services/ImageReceiver');const{BatchFrameReader}=load('protocol/BatchFrameReader');
const u=n=>{let b=Buffer.alloc(4);b.writeUInt32LE(n);return b};const jpeg=Buffer.from([255,216,255,1]);
function fixture(count){events=[];const model=new ReceiverModel(),r=new ImageReceiver({filesDir:'/app'},model),reader=new BatchFrameReader();reader.push(Buffer.concat([Buffer.from('IBAT'),u(count)]));const client={send:async({data})=>events.push('ack'+new Uint8Array(data)[0]),close:async()=>{}};r.client=client;return{r,model,reader,client}}
async function send(f){const b=f.reader.push(Buffer.concat([u(jpeg.length),jpeg]));await f.r.saveImage(f.client,f.reader,b,'/app/received-images/1700000000000-123',0)}
(async()=>{
let f=fixture(2); f.r.saveToGallery=async()=>events.push('gallery');
await send(f);assert.equal(events.includes('gallery'),false);assert.equal(events.at(-1),'ack0');
await send(f);assert(events.indexOf('gallery')>events.lastIndexOf('ack0'));assert.equal(f.model.photos.length,2);
f=fixture(2);f.r.saveToGallery=async()=>events.push('gallery');await send(f);failDecode=true;await send(f);assert.equal(events.at(-1),'ack1');assert.equal(f.model.receivedCount,1);failDecode=false;
const model=new ReceiverModel(),r=new ImageReceiver({filesDir:'/app',startAbility:async want=>{assert.equal(want.bundleName,'com.huawei.hmos.photos');events.push('gallery-open')}},model);
model.photos=['/app/received-images/1700000000000-123/1.jpg','/app/received-images/1700000000000-123/2.jpg'];r.exported=[];
events=[];decline=true;await r.saveToGallery();assert.equal(events.includes('copy'),false);assert.equal(model.pendingGallery,2);
decline=false;events=[];await r.saveToGallery();assert.equal(events.filter(e=>e==='copy').length,2);assert.equal(model.pendingGallery,0);assert.equal(events.filter(e=>e==='gallery-open').length,1);
const restored=new ReceiverModel();new ImageReceiver({filesDir:'/app'},restored);assert.equal(restored.pendingGallery,0);
events=[];await r.saveToGallery();assert.equal(events.length,0);
console.log('PASS: image receipt ACK precedes gallery confirmation; partial failure retains received images');
})().catch(e=>{console.error(e);process.exitCode=1});
