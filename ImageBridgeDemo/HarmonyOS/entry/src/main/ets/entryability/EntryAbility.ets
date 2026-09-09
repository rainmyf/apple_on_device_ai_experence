import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { ReceiverLifecycle } from '../services/ReceiverLifecycle';
import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  private suspendRequest: number = -1;

  private releaseDelay(): void {
    const request: number = this.suspendRequest;
    this.suspendRequest = -1;
    if (request >= 0) {
      try { backgroundTaskManager.cancelSuspendDelay(request); } catch (_) {}
    }
  }

  onForeground(): void {
    ReceiverLifecycle.foreground = true;
    this.releaseDelay();
    ReceiverLifecycle.onResume?.();
  }

  onBackground(): void {
    ReceiverLifecycle.foreground = false;
    if (this.suspendRequest >= 0) { return; }
    try {
      const info: backgroundTaskManager.DelaySuspendInfo = backgroundTaskManager.requestSuspendDelay(
        '继续接收iPhone图片和消息', () => { this.releaseDelay(); });
      this.suspendRequest = info.requestId;
      console.info('[ImageBridge] BACKGROUND_DELAY id=' + info.requestId + ' ms=' + info.actualDelayTime);
    } catch (error) { console.warn('[ImageBridge] BACKGROUND_DELAY_FAILED ' + String(error)); }
  }

  onDestroy(): void { this.releaseDelay(); }

  onWindowStageCreate(stage: window.WindowStage): void {
    try {
      stage.loadContent('pages/Index').catch(() => {
        console.error('[ImageBridge] Could not load receiver page');
      });
      stage.getMainWindow().then(async (main: window.Window) => {
        await main.setWindowKeepScreenOn(true);
      }).catch(() => { console.warn('[ImageBridge] Keep-screen-on unavailable'); });
    } catch (error) { console.error('[ImageBridge] Window error ' + String(error)); }
  }
}
