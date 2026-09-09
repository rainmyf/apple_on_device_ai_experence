// STORM-inspired uint32 little-endian framing; independent demo protocol.
export class FrameReader {
  private header: Uint8Array = new Uint8Array(4);
  private headerUsed: number = 0;
  private body: Uint8Array | undefined = undefined;
  private bodyUsed: number = 0;
  complete: boolean = false;

  private maximumBytes: number;

  constructor(maximumBytes: number = 20 * 1024 * 1024) {
    this.maximumBytes = maximumBytes;
  }

  push(chunk: Uint8Array): Uint8Array | undefined {
    if (this.complete && chunk.length > 0) { throw new Error('Unexpected trailing data'); }
    let offset: number = 0;
    while (this.headerUsed < 4 && offset < chunk.length) {
      this.header[this.headerUsed++] = chunk[offset++];
    }
    if (this.headerUsed < 4) { return undefined; }
    if (this.body === undefined) {
      const length: number = new DataView(this.header.buffer).getUint32(0, true);
      if (length < 1 || length > this.maximumBytes) { throw new Error('Invalid payload size'); }
      this.body = new Uint8Array(length);
    }
    const remaining: number = chunk.length - offset;
    if (remaining > this.body.length - this.bodyUsed) { throw new Error('Unexpected trailing data'); }
    this.body.set(chunk.subarray(offset), this.bodyUsed);
    this.bodyUsed += remaining;
    if (this.bodyUsed === this.body.length && !this.complete) {
      this.complete = true;
      return this.body;
    }
    return undefined;
  }
}
