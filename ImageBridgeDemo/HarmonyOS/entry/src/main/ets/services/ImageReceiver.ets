import { ReceiverLifecycle } from './ReceiverLifecycle';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { socket, mdns, connection } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { BatchFrameReader } from '../protocol/BatchFrameReader';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { filePreview } from '@kit.PreviewKit';

@ObservedV2
export class ReceiverModel {
  @Trace status: string = '正在启动…';
  @Trace ready: boolean = false;
  @Trace image: image.PixelMap | undefined = undefined;
  @Trace lastPath: string = '';
  @Trace photos: string[] = [];
  @Trace galleryBusy: boolean = false;
  @Trace galleryStatus: string = '';
  @Trace pendingGallery: number = 0;
  @Trace receivedCount: number = 0;
  @Trace receivedBytes: number = 0;
  @Trace detail: string = '请让两台手机连接同一 Wi-Fi';
}

export class ImageReceiver {
  private server: socket.TCPSocketServer | undefined = undefined;
  private service: mdns.LocalServiceInfo | undefined = undefined;
  private client: socket.TCPSocketConnection | undefined = undefined;
  private generation: number = 0;
  private timer: number = -1;
  private context: common.UIAbilityContext;
  private model: ReceiverModel;
  private exported: string[] = [];
  private galleryDeferred: boolean = false;

  constructor(context: common.UIAbilityContext, model: ReceiverModel) {
    this.context = context;
    this.model = model;
    try { this.model.lastPath = fs.readTextSync(this.context.filesDir + '/received-images/last-path.txt'); } catch (_) {}
    const root: string = this.context.filesDir + '/received-images';
    const paths: string[] = [];
    try {
      const batches: string[] = fs.listFileSync(root).sort().reverse();
      for (const batch of batches) {
        if (!/^[0-9]+-[0-9]+$/.test(batch)) { continue; }
        try {
          const names: string[] = fs.listFileSync(root + '/' + batch)
            .filter((name: string) => /^[0-9]+\.jpg$/.test(name))
            .sort((a: string, b: string) => parseInt(a) - parseInt(b));
          for (const name of names) { paths.push(root + '/' + batch + '/' + name); }
        } catch (_) {}
      }
    } catch (_) {}
    this.model.photos = paths;
    try { this.exported = JSON.parse(fs.readTextSync(root + '/gallery-exported.json')) as string[]; } catch (_) {}
    this.updatePending();
    this.galleryDeferred = this.model.pendingGallery > 0;

  }

  private updatePending(): void {
    this.model.pendingGallery = this.model.photos.filter((path: string) => !this.exported.includes(path)).length;
  }

  resumeGallery(): void {
    if (this.galleryDeferred && !this.model.galleryBusy) {
      this.saveToGallery().catch((error: Error) => console.error(String(error)));
    }
  }

  async saveToGallery(): Promise<void> {
    if (!ReceiverLifecycle.foreground) { this.galleryDeferred = true; this.model.galleryStatus = '图片已收到，返回前台后自动保存到图库'; return; }
    if (this.model.galleryBusy) { this.galleryDeferred = true; return; }
    this.galleryDeferred = false;
    const paths: string[] = this.model.photos.filter((path: string) => !this.exported.includes(path)).slice(0, 100);
    if (paths.length === 0) { return; }
    this.model.galleryBusy = true;
    let helper: photoAccessHelper.PhotoAccessHelper | undefined = undefined;
    let saved: number = 0;
    try {
      helper = photoAccessHelper.getPhotoAccessHelper(this.context);
      this.model.galleryStatus = '请确认保存到图库';
      const configs: photoAccessHelper.PhotoCreationConfig[] = paths.map((path: string, index: number): photoAccessHelper.PhotoCreationConfig => ({
        title: 'iPhone_' + Date.now().toString() + '_' + index.toString(),
        fileNameExtension: 'jpg', photoType: photoAccessHelper.PhotoType.IMAGE
      }));
      const uris: string[] = await helper.showAssetsCreationDialog(
        paths.map((path: string) => fileUri.getUriFromPath(path)), configs);
      if (uris.length === 0) { this.model.galleryStatus = '未保存到图库'; return; }
      if (uris.length !== paths.length) { throw new Error('图库返回的照片数量不匹配'); }
      for (let i: number = 0; i < paths.length; i++) {
        const destination: fs.File = fs.openSync(uris[i], fs.OpenMode.READ_WRITE);
        try { fs.copyFileSync(paths[i], destination.fd); fs.fsyncSync(destination.fd); }
        finally { fs.closeSync(destination); }
        this.exported.push(paths[i]); saved++;
        const record: string = this.context.filesDir + '/received-images/gallery-exported.json';
        this.writeDurably(record + '.tmp', JSON.stringify(this.exported));
        fs.renameSync(record + '.tmp', record);
        this.updatePending();
      }
      this.model.galleryStatus = `已保存 ${saved} 张到图库`;
      try { await this.openGallery(); }
      catch (_) { this.model.galleryStatus = `已保存 ${saved} 张到图库，请手动打开图库`; }
    } catch (error) {
      this.model.galleryStatus = `已保存 ${saved} 张到图库，其余可重试`;
      console.error('[ImageBridge] GALLERY_ERROR ' + String(error));
    } finally {
      this.model.galleryBusy = false;
      this.updatePending();
      try { await helper?.release(); } catch (_) {}
      if (ReceiverLifecycle.foreground) { this.resumeGallery(); }
    }
  }

  async openGallery(): Promise<void> {
    // Launcher entry verified on the connected Huawei device; no private album route.
    await this.context.startAbility({
      bundleName: 'com.huawei.hmos.photos',
      abilityName: 'com.huawei.hmos.photos.MainAbility'
    });
  }

  async start(): Promise<void> {
    await this.stop();
    const generation: number = ++this.generation;
    try {
      const server: socket.TCPSocketServer = socket.constructTCPSocketServerInstance();
      this.server = server;
      server.on('connect', (client: socket.TCPSocketConnection) => {
        this.accept(client, generation);
      });
      server.on('error', () => {
        if (generation === this.generation) {
          this.model.status = '监听连接失败，请重新启动接收';
          this.model.ready = false;
        }
      });
      await server.listen({ address: '0.0.0.0', family: 1, port: 22856 });
      const service: mdns.LocalServiceInfo = {
        serviceType: '_imgbridge._tcp', serviceName: 'ImageBridge-Harmony', port: 22856
      };
      // Same address selection as the existing Storm/Breeze mDNS adapter.
      const networks = await connection.getAllNets();
      for (const network of networks) {
        const caps = await connection.getNetCapabilities(network);
        if (!caps.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) { continue; }
        const properties = await connection.getConnectionProperties(network);
        for (const link of properties.linkAddresses) {
          if (link.address.family === 1 && link.address.address !== '127.0.0.1') {
            service.host = { address: link.address.address, family: 1, port: 22856 };
            break;
          }
        }
      }
      const registered: mdns.LocalServiceInfo = await mdns.addLocalService(this.context, service);
      if (generation !== this.generation) {
        await mdns.removeLocalService(this.context, registered);
        return;
      }
      this.service = registered;
      this.model.ready = true;
      this.model.status = '等待图片';
      this.model.detail = '已开启自动发现 · 保持此应用在前台';
      console.info('[ImageBridge] READY service=' + registered.serviceName);
    } catch (error) {
      if (generation !== this.generation) { return; }
      await this.stop();
      this.model.status = '接收服务启动失败';
      this.model.detail = String(error);
      console.error('[ImageBridge] START_ERROR ' + String(error));
    }
  }

  private armTimeout(client: socket.TCPSocketConnection): void {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      if (this.client === client) {
        this.model.status = '接收超时';
        this.model.detail = `已保存 ${this.model.receivedCount} 张，可重新预览最后一张`;
        this.closeClient(client);
      }
    }, 30000);
  }

  async previewLast(): Promise<void> {
    if (this.model.lastPath.length === 0) { throw new Error('尚无已保存图片'); }
    await this.previewPhoto(this.model.lastPath);
  }

  async previewPhoto(path: string): Promise<void> {
    await filePreview.openPreview(this.context, {
      uri: fileUri.getUriFromPath(path), title: '收到的图片', mimeType: 'image/jpeg'
    });
  }

  private accept(client: socket.TCPSocketConnection, generation: number): void {
    if (generation !== this.generation || this.client !== undefined) {
      client.close().catch(() => {}); return;
    }
    this.client = client;
    const reader: BatchFrameReader = new BatchFrameReader();
    const root: string = this.context.filesDir + '/received-images';
    const directory: string = root + '/' + Date.now().toString() + '-' + Math.floor(Math.random() * 1000000000).toString();
    this.model.receivedCount = 0; this.model.receivedBytes = 0;
    try { fs.mkdirSync(directory, true); } catch (error) { this.reject(client, String(error)); return; }
    this.model.status = '正在接收图片…'; this.armTimeout(client);
    client.on('message', (event: socket.SocketMessageInfo) => {
      if (this.client !== client || generation !== this.generation) { return; }
      try {
        const bytes: Uint8Array | undefined = reader.push(new Uint8Array(event.message));
        this.armTimeout(client);
        if (bytes !== undefined) { this.saveImage(client, reader, bytes, directory, generation); }
      } catch (error) { this.reject(client, String(error)); }
    });
    client.on('close', () => {
      if (this.client === client) {
        this.model.status = `连接已断开，已保存 ${this.model.receivedCount} 张`;
        this.closeClient(client);
      }
    });
    client.on('error', () => {
      if (this.client === client) { this.reject(client, '连接异常'); }
    });
  }

  private writeDurably(path: string, contents: ArrayBuffer | string): void {
    const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      if (typeof contents === 'string') {
        // Manifest is UTF-8 text; a short write is a failure, never an ACK.
        const expected: number = new util.TextEncoder().encodeInto(contents).length;
        if (fs.writeSync(file.fd, contents) !== expected) { throw new Error('保存路径记录不完整'); }
      } else {
        let offset: number = 0;
        while (offset < contents.byteLength) {
          const written: number = fs.writeSync(file.fd, contents.slice(offset));
          if (written < 1) { throw new Error('图片写入不完整'); }
          offset += written;
        }
      }
      fs.fsyncSync(file.fd);
    } finally { fs.closeSync(file); }
  }

  private async saveImage(client: socket.TCPSocketConnection, reader: BatchFrameReader,
    bytes: Uint8Array, directory: string, generation: number): Promise<void> {
    let source: image.ImageSource | undefined = undefined;
    let pixels: image.PixelMap | undefined = undefined;
    try {
      if (bytes.length < 3 || bytes[0] !== 255 || bytes[1] !== 216 || bytes[2] !== 255) {
        throw new Error('不是 JPEG 图片');
      }
      source = image.createImageSource(bytes.buffer);
      const info: image.ImageInfo = await source.getImageInfo();
      if (info.size.width < 1 || info.size.height < 1 || info.size.width > 4096 || info.size.height > 4096) {
        throw new Error('图片尺寸超过 4096 × 4096');
      }
      pixels = await source.createPixelMap();
      if (generation !== this.generation || this.client !== client) { return; }
      const path: string = directory + '/' + (this.model.receivedCount + 1).toString() + '.jpg';
      this.writeDurably(path, bytes.buffer);
      this.model.receivedCount++; this.model.receivedBytes += bytes.length;
      this.model.photos = [...this.model.photos, path];
      this.updatePending();
      const manifest: string = this.context.filesDir + '/received-images/last-path.txt';
      this.writeDurably(manifest + '.tmp', path); fs.renameSync(manifest + '.tmp', manifest);
      this.model.lastPath = path;
      this.model.status = `已保存 ${this.model.receivedCount} / ${reader.imageCount} 张`;
      this.model.detail = '图片保存在本应用中';
      if (this.client !== client || generation !== this.generation) { return; }
      reader.acknowledge();
      await client.send({ data: new Uint8Array([0]).buffer });
      if (this.client !== client || generation !== this.generation) { return; }
      if (reader.complete) {
        this.closeClient(client);
        this.saveToGallery().catch((error: Error) => console.error(String(error)));
      } else { this.armTimeout(client); }
    } catch (error) {
      if (generation === this.generation && this.client === client) { await this.reject(client, String(error)); }
    } finally {
      if (pixels !== undefined) { await pixels.release(); }
      if (source !== undefined) { await source.release(); }
    }
  }

  private async reject(client: socket.TCPSocketConnection, reason: string): Promise<void> {
    // Invalidate before awaiting ACK so an in-flight decode cannot publish this request.
    if (this.client === client) {
      clearTimeout(this.timer);
      this.timer = -1;
      this.client = undefined;
    }
    this.model.status = `图片接收失败，已保存 ${this.model.receivedCount} 张`;
    this.model.detail = reason;
    console.error('[ImageBridge] REJECT ' + reason);
    try { await client.send({ data: new Uint8Array([1]).buffer }); } catch (_) {}
    this.closeClient(client);
  }

  private closeClient(client: socket.TCPSocketConnection): void {
    if (this.client === client) {
      clearTimeout(this.timer);
      this.timer = -1;
      this.client = undefined;
    }
    client.close().catch(() => {});
  }

  async stop(): Promise<void> {
    this.generation += 1;
    this.model.ready = false;
    if (this.client !== undefined) { this.closeClient(this.client); }
    const service: mdns.LocalServiceInfo | undefined = this.service;
    this.service = undefined;
    if (service !== undefined) {
      try { await mdns.removeLocalService(this.context, service); } catch (_) {}
    }
    const server: socket.TCPSocketServer | undefined = this.server;
    this.server = undefined;
    if (server !== undefined) { try { await server.close(); } catch (_) {} }
  }
}
