export class ReceiverLifecycle {
  static onResume: (() => void) | undefined = undefined;
  static foreground: boolean = true;
}
