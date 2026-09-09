import { ReceiverLifecycle } from '../services/ReceiverLifecycle';
import { notificationManager } from '@kit.NotificationKit';
import { fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { ReceiverModel, ImageReceiver } from '../services/ImageReceiver';
import { MessageModel, MessageReceiver } from '../services/MessageReceiver';

@Entry
@ComponentV2
struct Index {
  @Local model: ReceiverModel = new ReceiverModel();
  @Local messageModel: MessageModel = new MessageModel();
  @Local selectedDemo: number = 0;
  @Local starting: boolean = false;
  @Local messageStarting: boolean = false;
  private receiver: ImageReceiver | undefined = undefined;
  private messageReceiver: MessageReceiver | undefined = undefined;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.receiver = new ImageReceiver(context, this.model);
    ReceiverLifecycle.onResume = () => { this.receiver?.resumeGallery(); };
    this.receiver.resumeGallery();
    this.messageReceiver = new MessageReceiver(context, this.messageModel,
      (text: string): Promise<void> => this.showMessage(text));
    this.restart();
    this.restartMessages();
    notificationManager.requestEnableNotification(context).catch(() => {
      console.warn('[MessageBridge] Notification permission unavailable');
    });
  }

  aboutToDisappear(): void {
    ReceiverLifecycle.onResume = undefined;
    this.receiver?.stop();
    this.messageReceiver?.stop();
  }

  onBackPress(): boolean {
    if (this.selectedDemo !== 0) { this.selectedDemo = 0; return true; }
    return false;
  }

  private async restart(): Promise<void> {
    if (this.starting) { return; }
    this.starting = true;
    await this.receiver?.start();
    this.starting = false;
  }

  private async restartMessages(): Promise<void> {
    if (this.messageStarting) { return; }
    this.messageStarting = true;
    await this.messageReceiver?.start();
    this.messageStarting = false;
  }

  private async showMessage(text: string): Promise<void> {
    // A notification failure must not remove the received list entry.
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION);
      await notificationManager.publish({
        id: Math.floor(Date.now() % 2147483647),
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        isAlertOnce: false,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_LONG_TEXT,
          longText: { title: '收到来自iPhone的通知', text: text,
            longText: text, briefText: text, expandedTitle: '收到来自iPhone的通知' }
        }
      });
    } catch (error) {
      console.warn('[MessageBridge] Notification failed ' + String(error));
    }
  }

  @Builder
  demoEntry(title: string, index: number) {
    Row() {
      Text(title).fontSize(21).fontWeight(FontWeight.Medium).fontColor('#12343B')
      Blank()
      Text('›').fontSize(28).fontColor('#526A71')
    }.width('100%').padding(24).backgroundColor(Color.White).borderRadius(18)
      .onClick(() => { this.selectedDemo = index; }).id(`demo-entry-${index}`)
  }

  @Builder
  imagePage() {
    Text(this.model.status).fontSize(19).fontColor('#007C83').id('receiver-status')
    Blank()
    Text(this.model.galleryStatus).fontSize(18).fontColor('#12343B')

    Blank()
    Button('打开图库').width('100%').backgroundColor('#007C83')
      .onClick(() => {
        this.receiver?.openGallery().catch(() => { this.model.galleryStatus = '无法打开图库，请手动打开'; });
      }).id('open-gallery')
    if (!this.model.ready) {
      Button(this.starting ? '正在启动…' : '重试').enabled(!this.starting)
        .onClick(() => { this.restart(); }).backgroundColor('#007C83').width('100%')
    }
  }

  @Builder
  messagePage() {
    Text(this.messageModel.status).fontSize(19).fontColor('#007C83').id('message-status')
    List({ space: 12 }) {
      if (this.messageModel.messages.length === 0) {
        ListItem() { Text('暂无消息').fontSize(18).fontColor('#526A71').padding(20) }
      }
      ForEach(this.messageModel.messages, (text: string, index: number) => {
        ListItem() {
          Column({ space: 8 }) {
            Text(`消息 ${index + 1}`).fontSize(14).fontColor('#526A71').width('100%')
            Text(text).fontSize(18).fontColor('#263B40').width('100%')
              .copyOption(CopyOptions.InApp)
          }.padding(20).width('100%').backgroundColor(Color.White).borderRadius(16)
        }
      }, (_text: string, index: number) => index.toString())
    }.width('100%').layoutWeight(1).id('received-messages')
    if (!this.messageModel.ready) {
      Button(this.messageStarting ? '正在启动…' : '重试').enabled(!this.messageStarting)
        .onClick(() => { this.restartMessages(); }).backgroundColor('#007C83').width('100%')
    }
  }

  build() {
    Column({ space: 20 }) {
      if (this.selectedDemo !== 0) {
        Text('〈 演示').fontSize(18).fontColor('#007C83').width('100%')
          .onClick(() => { this.selectedDemo = 0; }).id('back-to-demos')
      }
      Text(this.selectedDemo === 0 ? '演示' : (this.selectedDemo === 1 ? '图片分享' : '消息分享'))
        .fontSize(30).fontWeight(FontWeight.Bold).fontColor('#12343B').width('100%')
      if (this.selectedDemo === 0) {
        this.demoEntry('图片分享', 1)
        this.demoEntry('消息分享', 2)
        Blank()
      } else if (this.selectedDemo === 1) {
        this.imagePage()
      } else {
        this.messagePage()
      }
    }.padding({ top: 56, bottom: 32, left: 24, right: 24 })
      .width('100%').height('100%').backgroundColor('#F4F7F8')
  }
}
