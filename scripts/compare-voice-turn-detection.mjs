import { execFile, spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { appendFile, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { simulatorRequest } from '../src/simulator.mjs';

const run = promisify(execFile);
const root = fileURLToPath(new URL('..', import.meta.url));
const fixtures = join(root, 'docs/research/esp-1163');
const [device, output, count = '5', only = 'all', previous] = process.argv.slice(2);
const rounds = Number(count);
const modes = ['server_vad', 'semantic_vad'];
const model = 'gpt-realtime-2.1';
const safari = 'com.apple.mobilesafari';
const apps = new Map([
  ['photos', 'com.apple.mobileslideshow'], ['照片', 'com.apple.mobileslideshow'],
  ['settings', 'com.apple.Preferences'], ['设置', 'com.apple.Preferences'],
]);
const now = () => performance.now();

if (!device || !output || !Number.isInteger(rounds) || rounds < 1 || !process.env.OPENAI_API_KEY) {
  console.error('Usage: OPENAI_API_KEY=<inherited> node scripts/compare-voice-turn-detection.mjs <disposable-simulator-uuid> <new-output-dir> [rounds] [sample|all] [previous-trials.jsonl]');
  process.exit(2);
}

const simctl = (...args) => run('xcrun', ['simctl', ...args]);
const sims = Object.values(JSON.parse((await simctl('list', 'devices', 'booted', '--json')).stdout).devices).flat();
if (!sims.some(sim => sim.udid === device && sim.name === 'Poki ESP-1163 VAD')) {
  throw new Error('Expected a booted disposable simulator named Poki ESP-1163 VAD');
}

const samples = JSON.parse(await readFile(join(fixtures, 'samples.json'), 'utf8')).filter(sample => only === 'all' || sample.id === only);
if (!samples.length) throw new Error('Unknown sample');
const completed = new Set();
if (previous) {
  const rows = (await readFile(previous, 'utf8')).trim().split('\n').filter(Boolean).map(JSON.parse);
  for (const row of rows) {
    if (row.result) completed.add(`${row.sample}/${row.round}/${row.mode}`);
  }
}
await mkdir(output, { mode: 0o700 });
const scratch = await mkdtemp(join(tmpdir(), 'poki-vad-'));
const children = [];
const pages = new Map();
const fixture = createServer(async (request, response) => {
  const page = pages.get(request.url);
  if (!page) { response.writeHead(404).end(); return; }
  const { sample } = page;
  if (request.method === 'GET') page.loaded = true;
  const options = [sample.decoy, sample.expected].filter(() => sample.decoy);
  if (request.method === 'POST') {
    let body = '';
    for await (const chunk of request) body += chunk;
    const selected = new URLSearchParams(body).get('selected');
    if (!options.includes(selected)) { response.writeHead(400).end(); return; }
    page.clicks.push({ selected, at: now() });
  }
  const selected = page.clicks.at(-1)?.selected ?? '未选择';
  response.writeHead(200, { 'content-type': 'text/html;charset=utf-8', 'cache-control': 'no-store' });
  response.end(`<!doctype html><html lang="zh"><meta name="viewport" content="width=device-width"><title>语音实验</title>
  <body><h1>语音实验</h1><p>已选：${selected}</p>
  <form method="post">${options.map(label => `<button style="display:block;font-size:26px;margin:12px;padding:12px" name="selected" value="${label}">${label}</button>`).join('')}</form></body></html>`);
});

async function start(script, args, directory) {
  const env = { ...process.env, POKI_MCP_STATE_DIR: directory, POKI_VOICE_MODEL: '' };
  // The daemon and its simulator helpers need no OpenAI credential.
  if (script === 'src/daemon.mjs') delete env.OPENAI_API_KEY;
  const child = spawn(process.execPath, [join(root, script), ...args], { env, stdio: ['ignore', 'pipe', 'ignore'] });
  children.push(child);
  const lines = createInterface({ input: child.stdout });
  let ready;
  for await (const line of lines) {
    let event;
    try { event = JSON.parse(line); } catch { continue; }
    if (event.event === 'ready') { ready = event; break; }
  }
  child.stdout.resume();
  if (!ready) throw new Error(`${script} exited before ready`);
  return ready;
}

async function closeResources() {
  fixture.close();
  for (const child of children.toReversed()) {
    if (child.exitCode !== null || child.signalCode !== null) continue;
    const exited = once(child, 'exit');
    child.kill();
    await Promise.race([exited, delay(2500, undefined, { ref: false })]);
    if (child.exitCode === null && child.signalCode === null) {
      child.kill('SIGKILL');
      await exited;
    }
  }
  await rm(scratch, { recursive: true, force: true });
}

async function screen() {
  return simulatorRequest(device, { op: 'ax' });
}

async function prepare(page, url) {
  await simctl('openurl', device, url);
  for (let attempt = 0; attempt < 24; attempt++) {
    const tree = await screen();
    if (tree.foreground.bundle_id === safari && page.loaded) { await delay(300); return; }
    await delay(250);
  }
  throw new Error('The disposable simulator did not show the experiment page');
}

const errorCode = value => /^[a-z][a-z0-9_]{0,63}$/.test(value ?? '') ? value : 'unknown';

async function trial(base, sample, mode, round, page) {
  const query = new URLSearchParams({ transport: 'realtime', turns: 'committed', language: 'zh-Hans' });
  if (mode === 'semantic_vad') query.set('vad', mode);
  const tokenRes = await fetch(`${base}/token?${query}`, { signal: AbortSignal.timeout(12000) });
  if (!tokenRes.ok) throw new Error(`Bridge could not mint a Realtime session (HTTP ${tokenRes.status})`);
  const token = await tokenRes.json();
  const socket = new WebSocket(`wss://api.openai.com/v1/realtime?model=${model}`, { headers: { Authorization: `Bearer ${token.value}` } });
  const ready = Promise.withResolvers();
  const row = { sample: sample.id, round, mode, speech: sample.speech, events: [], actions: [], errors: [] };
  const committed = new Set();
  let epoch, lastEvent, session, requested = false, active = false, pending = 0, wantsResponse = false, inFlight = 0, disconnected = false;
  const stamp = () => Math.round(now() - epoch);
  const send = event => socket.send(JSON.stringify(event));
  function flush() {
    if (!requested && !active && (pending || wantsResponse) && socket.readyState === WebSocket.OPEN) {
      if (pending) pending--;
      wantsResponse = false;
      requested = true;
      send({ type: 'response.create' });
    }
  }

  async function bridgeTool(item, args, checked) {
    const response = await fetch(`${base}/tool`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, signal: AbortSignal.timeout(10000),
      body: JSON.stringify({ name: item.name, call_id: item.call_id, arguments: args, checked }),
    });
    if (!response.ok) throw new Error(`Tool HTTP ${response.status}`);
    return response.json();
  }

  async function tool(item) {
    inFlight++;
    const call = { name: item.name, atMs: stamp(), itemStatus: item.status };
    row.actions.push(call);
    let output;
    try {
      const args = call.arguments = JSON.parse(item.arguments || '{}');
      if (item.name === 'open_settings' && !args.page || item.name === 'open_app' && apps.has(args.name?.toLowerCase())) {
        call.target = item.name === 'open_settings' ? apps.get('settings') : apps.get(args.name.toLowerCase());
        call.dispatchMs = stamp();
        const launchArgs = item.name === 'open_app' ? { name: call.target } : args;
        const result = await bridgeTool(item, launchArgs);
        call.toolState = result.state;
        if (result.state !== 'done') call.toolError = result.output;
        const observed = (await screen()).foreground.bundle_id;
        call.observed = observed;
        call.effectMs = stamp();
        output = JSON.stringify({ state: result.state, foreground: observed });
        call.confirmed = result.state === 'done' && observed === call.target;
      } else if (item.name === 'tap_text' && sample.decoy) {
        const before = page.clicks.length;
        const preview = await bridgeTool(item, args);
        call.target = preview.target?.text ?? args.text;
        call.previewState = preview.state;
        if (preview.state === 'failed') call.previewError = preview.output;
        if (preview.state === 'check' && preview.app?.bundle_id === safari &&
            [sample.expected, sample.decoy].includes(call.target) && await pageIsCurrent()) {
          call.dispatchMs = stamp();
          const result = await bridgeTool(item, args, { app: safari, text: call.target });
          call.toolState = result.state;
          if (result.state !== 'done') call.toolError = result.output;
          for (let attempt = 0; attempt < 8 && page.clicks.length === before; attempt++) await delay(100);
          const click = page.clicks[before];
          call.observed = click?.selected ?? null;
          call.effectMs = click ? Math.round(click.at - epoch) : null;
          call.confirmed = result.state === 'done' && call.observed === call.target;
          output = JSON.stringify({ state: result.state, selected: call.observed });
        } else output = 'Nothing tapped. Select one exact button on the experiment page.';
      } else if (item.name === 'read_screen') {
        output = (await bridgeTool(item, args)).output;
        if (sample.decoy && await pageIsCurrent()) {
          const picture = join(scratch, 'screen.png');
          await simctl('io', device, 'screenshot', picture);
          const { stdout } = await run(join(root, 'build/ocr'), [picture]);
          output += '\nVisible text: ' + JSON.parse(stdout).map(line => line.text).join(' | ');
        }
      } else if (item.name === 'get_ios_version') {
        output = 'Disposable iPhone 17 Pro simulator running iOS 27.2.';
      } else {
        output = 'No action. This simulator only allows Photos, Settings and the experiment buttons.';
      }
    } catch (error) {
      call.error = error.name;
      output = 'Simulator tool did not complete.';
    } finally {
      inFlight--;
    }
    call.finishedMs = stamp();
    if (socket.readyState === WebSocket.OPEN) {
      send({ type: 'conversation.item.create', item: { type: 'function_call_output', call_id: item.call_id, output } });
      wantsResponse = true;
      flush();
    }
  }

  async function pageIsCurrent() {
    const tree = await screen();
    return page.loaded && tree.foreground.bundle_id === safari && tree.elements.some(el => el.value?.includes('127.0.0.1'));
  }

  socket.addEventListener('error', () => { disconnected = true; ready.resolve(); });
  socket.addEventListener('close', () => { disconnected = true; ready.resolve(); });
  socket.addEventListener('message', ({ data }) => {
    const event = JSON.parse(data);
    if (event.type === 'session.created') {
      const { audio, model: acceptedModel, tools, reasoning } = event.session;
      session = { model: acceptedModel, audio, tools: tools.map(t => t.name), reasoning };
      ready.resolve();
      return;
    }
    if (!epoch) return;
    lastEvent = now();
    const atMs = stamp();
    switch (event.type) {
      case 'input_audio_buffer.speech_started':
      case 'input_audio_buffer.speech_stopped':
        row.events.push({ type: event.type, atMs, item: event.item_id, audioStartMs: event.audio_start_ms, audioEndMs: event.audio_end_ms });
        break;
      case 'input_audio_buffer.committed':
        row.events.push({ type: event.type, atMs, item: event.item_id });
        if (!committed.has(event.item_id)) { committed.add(event.item_id); pending++; flush(); }
        break;
      case 'conversation.item.input_audio_transcription.completed':
      case 'conversation.item.input_audio_transcription.failed':
        row.events.push({ type: event.type, atMs, item: event.item_id, text: event.transcript, usage: event.usage, code: event.error ? errorCode(event.error.code) : undefined });
        break;
      case 'response.created':
        requested = false; active = true;
        row.events.push({ type: event.type, atMs });
        break;
      case 'response.done':
        active = false;
        row.events.push({ type: event.type, atMs, status: event.response.status, usage: event.response.usage });
        flush();
        break;
      case 'response.output_audio_transcript.done':
        row.events.push({ type: event.type, atMs, text: event.transcript });
        break;
      case 'response.output_item.done':
        if (event.item.type === 'function_call') void tool(event.item);
        break;
      case 'error':
        row.errors.push({ atMs, code: errorCode(event.error?.code) });
        requested = false;
        break;
    }
  });

  try {
    await Promise.race([ready.promise, delay(9000, undefined, { ref: false })]);
    const vad = session?.audio?.input?.turn_detection;
    if (!session || session.model !== model || vad?.type !== mode || vad.create_response !== false ||
        session.audio.input.transcription.language !== 'zh' || session.audio.input.format.rate !== 24_000) {
      throw new Error('Realtime session did not accept the requested model or audio configuration');
    }
    row.session = session;
    epoch = lastEvent = now();
    const pcmRes = await fetch(`${base}/utterance?n=${sample.number}`, { signal: AbortSignal.timeout(6000) });
    if (!pcmRes.ok) throw new Error(`Bridge recording request failed (HTTP ${pcmRes.status})`);
    const pcm = Buffer.from(await pcmRes.arrayBuffer());
    if (createHash('sha256').update(pcm).digest('hex') !== sample.pcmSha256) throw new Error('PCM differs from the recorded fixture');
    epoch = lastEvent = now();
    let maxLateness = 0;
    const bytesPerMs = 48;
    const frameMs = 40;
    for (let offset = 0; offset < pcm.length && !disconnected; offset += frameMs * bytesPerMs) {
      const deadline = epoch + offset / bytesPerMs;
      if (deadline > now()) await delay(deadline - now());
      maxLateness = Math.max(maxLateness, now() - deadline);
      if (socket.readyState !== WebSocket.OPEN) break;
      send({ type: 'input_audio_buffer.append', audio: pcm.subarray(offset, offset + frameMs * bytesPerMs).toString('base64') });
    }
    row.maxReplayLatenessMs = Math.round(maxLateness);
    const deadline = epoch + pcm.length / bytesPerMs + 14000;
    while (!disconnected && now() < deadline && (requested || active || pending || wantsResponse || inFlight || now() - lastEvent < 1150)) await delay(50);
    if (disconnected || now() >= deadline) row.errors.push({ atMs: stamp(), code: disconnected ? 'disconnected' : 'timeout' });
  } finally {
    socket.close();
    while (inFlight) await delay(50);
  }

  const end = sample.speech.at(-1)[1];
  const stops = row.events.filter(event => event.type === 'input_audio_buffer.speech_stopped');
  const actions = row.actions.filter(call => call.dispatchMs !== undefined);
  const effective = actions.find(call => call.confirmed && call.observed === sample.expected);
  const final = sample.decoy ? page.clicks.at(-1)?.selected ?? null : (await screen()).foreground.bundle_id;
  row.result = {
    expected: sample.expected, final, success: final === sample.expected && Boolean(effective),
    earlyCutCount: stops.filter(event => event.audioEndMs < end - 100).length,
    earlyDispatchCount: actions.filter(call => call.dispatchMs < end).length,
    wrongEffectCount: actions.filter(call => call.confirmed && call.observed !== sample.expected).length,
    duplicateEffectCount: Math.max(0, actions.filter(call => call.confirmed && call.observed === sample.expected).length - 1),
    finalVadWaitMs: Math.round(stops.find(event => event.audioEndMs >= end - 100)?.atMs - end),
    firstEffectiveMs: effective ? Math.round(effective.dispatchMs - end) : null,
    confirmedMs: effective ? Math.round(effective.effectMs - end) : null,
  };
  return row;
}

try {
  for (const [index, sample] of samples.entries()) {
    sample.number = String(index + 1).padStart(2, '0');
    const { stdout } = await run('ffmpeg', ['-v', 'error', '-i', join(fixtures, sample.file), '-f', 's16le', '-'], { encoding: 'buffer', maxBuffer: 1024 * 1024 });
    await writeFile(join(scratch, `u${sample.number}.24k.pcm`), stdout, { mode: 0o600 });
  }
  const state = join(scratch, 'state');
  await start('src/daemon.mjs', ['--port', '0'], state);
  const bridge = await start('bin/voice-bridge.mjs', ['--port', '0', '--host', '127.0.0.1', '--mac-tools', '--device', device, '--test-dir', scratch], state);
  const { secret } = JSON.parse(await readFile(join(state, 'voice-bridge.json')));
  const base = `http://127.0.0.1:${bridge.port}/voice/${secret}`;
  await new Promise(resolve => fixture.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${fixture.address().port}`;
  const schedule = Array.from({ length: rounds }, (_, index) => index + 1).flatMap(round =>
    samples.flatMap((sample, index) => modes.every(mode => completed.has(`${sample.id}/${round}/${mode}`)) ? [] :
      (index % 2 ? modes.toReversed() : modes).map(mode => ({ round, sample, mode }))));
  console.log(`Realtime voice bridge and disposable simulator ready. ${schedule.length} scheduled trials.`);
  for (const bundle of new Set(samples.filter(sample => !sample.decoy).map(sample => sample.expected))) {
    await simctl('launch', device, bundle);
  }
  let consecutiveFailures = 0;
  for (const { round, sample, mode } of schedule) {
    const path = `/${sample.id}/${round}/${mode}`;
    const page = { sample, clicks: [] };
    pages.set(path, page);
    let row;
    try {
      await prepare(page, origin + path);
      row = await trial(base, sample, mode, round, page);
    } catch (error) {
      row = { sample: sample.id, round, mode, failed: error.message };
    }
    await appendFile(join(output, 'trials.jsonl'), JSON.stringify(row) + '\n', { mode: 0o600 });
    if (round === 1 && ['address', 'correction', 'english'].includes(sample.id)) {
      await simctl('io', device, 'screenshot', join(output, `${sample.id}-${mode}.png`)).catch(() => {});
    }
    const { success, earlyCutCount, firstEffectiveMs } = row.result ?? {};
    console.log(`${round} ${sample.id} ${mode} ${row.failed ?? `success=${success} cuts=${earlyCutCount} firstEffectiveMs=${firstEffectiveMs} errors=${row.errors.length}`}`);
    consecutiveFailures = row.failed ? consecutiveFailures + 1 : 0;
    if (consecutiveFailures >= 4) throw new Error('Four consecutive trials stopped before measurement. Keep this log and resume after the dependency recovers.');
  }
} finally {
  await closeResources();
}
