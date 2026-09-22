/* Preserve the connected source's channel count. Never upmix to the requested count. */
class DiagnosticCapture extends AudioWorkletProcessor {
  constructor() {
    super();
    this.buffers = [];
    this.offset = 0;
  }
  process(inputs, outputs) {
    for (const output of outputs) for (const channel of output) channel.fill(0);
    const channels = inputs[0];
    if (!channels?.length || !channels[0].length) return true;
    if (this.buffers.length !== channels.length) {
      this.buffers = channels.map(() => new Float32Array(4096));
      this.offset = 0;
    }
    let cursor = 0;
    while (cursor < channels[0].length) {
      const count = Math.min(4096 - this.offset, channels[0].length - cursor);
      for (let c = 0; c < channels.length; c++) this.buffers[c].set(channels[c].subarray(cursor, cursor + count), this.offset);
      cursor += count;
      this.offset += count;
      if (this.offset === 4096) {
        this.port.postMessage({ channels: this.buffers, sampleRate }, this.buffers.map(channel => channel.buffer));
        this.buffers = channels.map(() => new Float32Array(4096));
        this.offset = 0;
      }
    }
    return true;
  }
}
registerProcessor('diagnostic-capture', DiagnosticCapture);
