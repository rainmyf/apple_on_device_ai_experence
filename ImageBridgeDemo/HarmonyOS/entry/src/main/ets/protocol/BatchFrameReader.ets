// One bounded image at a time. The next frame is legal only after its predecessor ACK.
export class BatchFrameReader {
  private header: Uint8Array = new Uint8Array(8);
  private used: number = 0;
  private count: number = 0;
  private index: number = 0;
  private total: number = 0;
  private body: Uint8Array | undefined = undefined;
  private bodyUsed: number = 0;
  private awaitingACK: boolean = false;
  get complete(): boolean { return this.count > 0 && this.index === this.count; }
  get isLast(): boolean { return this.index + 1 === this.count; }
  get imageCount(): number { return this.count; }
  acknowledge(): void {
    if (!this.awaitingACK) { throw new Error('No image awaiting ACK'); }
    this.index++; this.awaitingACK = false; this.body = undefined; this.bodyUsed = 0; this.used = 0;
  }
  push(chunk: Uint8Array): Uint8Array | undefined {
    if (chunk.length === 0) { return undefined; }
    if (this.awaitingACK || this.complete) { throw new Error('Unexpected data before ACK or after batch'); }
    let offset: number = 0;
    if (this.count === 0) {
      while (this.used < 8 && offset < chunk.length) { this.header[this.used++] = chunk[offset++]; }
      if (this.used < 8) { return undefined; }
      if (this.header[0] !== 73 || this.header[1] !== 66 || this.header[2] !== 65 || this.header[3] !== 84) {
        throw new Error('Invalid batch magic');
      }
      this.count = new DataView(this.header.buffer).getUint32(4, true);
      if (this.count < 1 || this.count > 20) { throw new Error('Invalid image count'); }
      this.used = 0;
    }
    while (this.used < 4 && offset < chunk.length) { this.header[this.used++] = chunk[offset++]; }
    if (this.used < 4) { return undefined; }
    if (this.body === undefined) {
      const length: number = new DataView(this.header.buffer).getUint32(0, true);
      if (length < 1 || length > 20 * 1024 * 1024) { throw new Error('Invalid image size'); }
      if (this.total + length > 100 * 1024 * 1024) { throw new Error('Invalid batch total'); }
      this.total += length; this.body = new Uint8Array(length);
    }
    const remaining: number = chunk.length - offset;
    if (remaining > this.body.length - this.bodyUsed) { throw new Error('Unexpected data before ACK'); }
    this.body.set(chunk.subarray(offset), this.bodyUsed); this.bodyUsed += remaining;
    if (this.bodyUsed === this.body.length) { this.awaitingACK = true; return this.body; }
    return undefined;
  }
}
