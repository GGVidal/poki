import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const rate = 24_000;
const out = process.argv[2] ?? 'docs/research/esp-1163';
const samples = [
  { id: 'short', parts: ['打开照片。'], expected: 'com.apple.mobileslideshow' },
  { id: 'address', parts: ['点一下页面上的和平路，', '十七号三楼。'], gapMs: 1150, expected: '和平路17号3楼', decoy: '和平路' },
  { id: 'correction', parts: ['点一下页面上的林小河。', '抱歉，改成林小雨。'], gapMs: 1150, expected: '林小雨', decoy: '林小河' },
  { id: 'noise', parts: ['打开设置。'], noise: true, expected: 'com.apple.Preferences' },
  { id: 'english', parts: ['Open the Photos app.'], voice: 'Samantha', expected: 'com.apple.mobileslideshow' },
];
const scratch = mkdtempSync(join(tmpdir(), 'poki-vad-fixtures-'));
const silence = ms => Buffer.alloc(ms * rate * 2 / 1000);
const duration = audio => audio.length / (rate * 2 / 1000);
const manifest = [];
let seed = 1163;

try {
  for (const sample of samples) {
    const clips = [silence(320)];
    const speech = [];
    let cursor = 320;
    for (const part of sample.parts) {
      if (speech.length) {
        clips.push(silence(sample.gapMs));
        cursor += sample.gapMs;
      }
      const aiff = join(scratch, 'speech.aiff');
      rmSync(aiff, { force: true });
      execFileSync('say', ['-v', sample.voice ?? 'Tingting', '-o', aiff, part]);
      const trim = 'silenceremove=start_periods=1:start_threshold=-46dB';
      const clip = execFileSync('ffmpeg', ['-v', 'error', '-i', aiff, '-af', `${trim},areverse,${trim},areverse`, '-ar', String(rate), '-ac', '1', '-f', 's16le', '-']);
      clips.push(clip);
      speech.push([cursor, cursor + duration(clip)]);
      cursor += duration(clip);
    }
    const pcm = Buffer.concat([...clips, silence(2600)]);
    if (sample.noise) {
      let pink = 0;
      for (let i = 0; i < pcm.length; i += 2) {
        seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
        pink = 0.88 * pink + 0.12 * (seed / 2 ** 31 - 1);
        const mixed = Math.round(0.82 * pcm.readInt16LE(i) + 5600 * pink);
        pcm.writeInt16LE(Math.max(-32768, Math.min(32767, mixed)), i);
      }
    }
    const file = `${sample.id}.flac`;
    execFileSync('ffmpeg', ['-v', 'error', '-y', '-f', 's16le', '-ar', String(rate), '-ac', '1', '-i', '-', join(out, file)], { input: pcm });
    manifest.push({ ...sample, file, speech, durationMs: duration(pcm), pcmSha256: createHash('sha256').update(pcm).digest('hex') });
  }
  writeFileSync(join(out, 'samples.json'), JSON.stringify(manifest, null, 2) + '\n');
} finally {
  rmSync(scratch, { recursive: true, force: true });
}
