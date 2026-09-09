import { common } from '@kit.AbilityKit';
import { socket, mdns, connection } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { FrameReader } from '../protocol/FrameReader';

@ObservedV2
export class MessageModel {
  @Trace status: string = '正在启动…';
  @Trace ready: boolean = false;
  @Trace lastText: string = '';
  @Trace messages: string[] = [];
  @Trace receivedCount: number = 0;
  @Trace receivedBytes: number = 0;
  @Trace detail: string = '请让两台手机连接同一 Wi-Fi';
}

export class MessageReceiver {
  private server: socket.TCPSocketServer | undefined = undefined;
  private service: mdns.LocalServiceInfo | undefined = undefined;
  private client: socket.TCPSocketConnection | undefined = undefined;
  private generation: number = 0;
  private timer: number = -1;
  private context: common.UIAbilityContext;
  private model: MessageModel;

  private showMessage: (text: string) => Promise<void>;

  constructor(context: common.UIAbilityContext, model: MessageModel,
    showMessage: (text: string) => Promise<void>) {
    this.context = context;
    this.model = model;
    this.showMessage = showMessage;
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
      await server.listen({ address: '0.0.0.0', family: 1, port: 22857 });
      const service: mdns.LocalServiceInfo = {
        serviceType: '_msgbridge._tcp', serviceName: 'ImageBridge-Message', port: 22857
      };
      // Same address selection as the existing Storm/Breeze mDNS adapter.
      const networks = await connection.getAllNets();
      for (const network of networks) {
        const caps = await connection.getNetCapabilities(network);
        if (!caps.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) { continue; }
        const properties = await connection.getConnectionProperties(network);
        for (const link of properties.linkAddresses) {
          if (link.address.family === 1 && link.address.address !== '127.0.0.1') {
            service.host = { address: link.address.address, family: 1, port: 22857 };
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
      this.model.status = '等待消息';
      this.model.detail = '已开启自动发现 · 保持此应用在前台';
      console.info('[MessageBridge] READY service=' + registered.serviceName);
    } catch (error) {
      if (generation !== this.generation) { return; }
      await this.stop();
      this.model.status = '接收服务启动失败';
      this.model.detail = String(error);
      console.error('[MessageBridge] START_ERROR ' + String(error));
    }
  }

  private accept(client: socket.TCPSocketConnection, generation: number): void {
    if (generation !== this.generation || this.client !== undefined) {
      client.close().catch(() => {});
      return;
    }
    this.client = client;
    const reader: FrameReader = new FrameReader(65536);
    let finishing: boolean = false;
    this.model.status = '正在接收消息…';
    this.timer = setTimeout(() => {
      this.model.status = '接收超时，请重新发送';
      this.closeClient(client);
    }, 30000);
    client.on('message', (event: socket.SocketMessageInfo) => {
      if (this.client !== client || generation !== this.generation) { return; }
      try {
        const bytes: Uint8Array | undefined = reader.push(new Uint8Array(event.message));
        if (bytes !== undefined) {
          finishing = true;
          this.display(client, bytes, generation);
        }
      } catch (error) {
        finishing = true;
        this.reject(client, String(error));
      }
    });
    client.on('close', () => {
      if (this.client === client) {
        if (!finishing) { this.model.status = '发送端已断开，请重试'; }
        this.closeClient(client);
      }
    });
    client.on('error', () => {
      if (this.client === client) {
        this.model.status = '连接异常，请重新发送';
        this.closeClient(client);
      }
    });
  }

  private async display(client: socket.TCPSocketConnection, bytes: Uint8Array,
    generation: number): Promise<void> {
    try {
      // Fatal decoding rejects malformed UTF-8. ignoreBOM retains a literal leading U+FEFF.
      const text: string = util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true })
        .decodeToString(bytes);
      // Byte-for-byte round trip guards against lossy conversion on platform decoder variants.
      const encoded: Uint8Array = new util.TextEncoder().encodeInto(text);
      if (encoded.length !== bytes.length) { throw new Error('文本编码无效'); }
      for (let i: number = 0; i < bytes.length; i++) {
        if (encoded[i] !== bytes[i]) { throw new Error('文本编码无效'); }
      }
      if (generation !== this.generation || this.client !== client) { return; }
      this.model.messages = [...this.model.messages, text];
      this.model.lastText = text;
      this.model.receivedCount += 1;
      this.model.receivedBytes = bytes.length;
      this.model.status = '消息已收到';
      this.showMessage(text).catch((error: Error) => console.warn(String(error)));
      await client.send({ data: new Uint8Array([0]).buffer });
      console.info(`[MessageBridge] MESSAGE_APPENDED count=${this.model.receivedCount} bytes=${bytes.length}`);
    } catch (error) {
      if (generation === this.generation && this.client === client) {
        await this.reject(client, String(error));
      }
    } finally {
      this.closeClient(client);
    }
  }

  private async reject(client: socket.TCPSocketConnection, reason: string): Promise<void> {
    // Invalidate before awaiting ACK so an in-flight decode cannot publish this request.
    if (this.client === client) {
      clearTimeout(this.timer);
      this.timer = -1;
      this.client = undefined;
    }
    this.model.status = '消息接收失败';
    this.model.detail = reason;
    console.error('[MessageBridge] REJECT ' + reason);
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
