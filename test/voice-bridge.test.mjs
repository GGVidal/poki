import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { once } from 'node:events';
import { createInterface } from 'node:readline';
import { copyFile, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fixture } from './fixture.mjs';
import { root } from '../src/config.mjs';
import { buildVoicePrompt, compareVoicePrompts, VOICE_SECTION_IDS, VOICE_SPEC_VERSION } from '../src/voice-behavior-spec.mjs';

async function sessionBridge(t, { extraArgs = [], extraEnv = {}, failUpstream = false } = {}) {
  const dir = await mkdtemp(join(tmpdir(), 'poki-voice-token-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const preload = `
    import { writeFile } from 'node:fs/promises';
    import { join } from 'node:path';
    globalThis.fetch = async (url, options) => {
      await writeFile(join(process.env.POKI_MCP_STATE_DIR, 'request.json'), JSON.stringify({ url, body: JSON.parse(options.body) }));
      if (${JSON.stringify(failUpstream)}) return Response.json({ error: { message: 'upstream failed' } }, { status: 502 });
      if (url === 'https://api.openai.com/v1/realtime/client_secrets') return Response.json({ value: 'ek_test' });
      if (url === 'https://api.openai.com/v1/live/sessions') return Response.json({ transport: { sdp: 'sdp-answer' } }, { status: 201 });
      if (url === 'https://api.openai.com/v1/responses') return Response.json({ output: [{
        type: 'message', content: [{ type: 'output_text', text: 'Screen description' }],
      }] });
      throw new Error('Unexpected upstream URL');
    };
  `;
  const child = spawn(process.execPath, ['--import', `data:text/javascript,${encodeURIComponent(preload)}`, join(root, 'bin/voice-bridge.mjs'), '--port', '0', '--host', '127.0.0.1', ...extraArgs], {
    env: { ...process.env, POKI_MCP_STATE_DIR: dir, POKI_VOICE_MODEL: '', OPENAI_API_KEY: 'unused', ...extraEnv }, stdio: ['ignore', 'pipe', 'inherit'],
  });
  const exited = once(child, 'exit');
  t.after(async () => { child.kill(); await exited; });
  const lines = createInterface({ input: child.stdout });
  const events = [];
  const [line] = await Promise.race([once(lines, 'line'), exited.then(() => { throw new Error('Voice bridge exited before it was ready'); })]);
  lines.on('line', entry => { try { events.push(JSON.parse(entry)); } catch {} });
  const { port } = JSON.parse(line);
  const { secret } = JSON.parse(await readFile(join(dir, 'voice-bridge.json'), 'utf8'));
  return {
    base: `http://127.0.0.1:${port}/voice/${secret}`,
    events,
    request: async () => JSON.parse(await readFile(join(dir, 'request.json'), 'utf8')),
  };
}

test('legacy voice token requests hint Chinese transcription for each interface language', async t => {
  const { base, request } = await sessionBridge(t);
  for (const language of ['', 'zh-Hans', 'en']) {
    const response = await fetch(`${base}/token?language=${language}`);
    assert.equal(response.status, 200);
    assert.equal((await response.json()).value, 'ek_test');
    const { body: { session } } = await request();
    assert.equal(session.audio.input.transcription.language, 'zh');
    assert.ok(!session.tools.some(tool => tool.name === 'cancel_current_task'));
  }
});

test('a Realtime client opts in to requesting its own replies after audio is committed', async t => {
  const { base, request } = await sessionBridge(t);
  for (const [query, autoRespond] of [['', true], ['?turns=committed', false]]) {
    assert.equal((await fetch(`${base}/token${query}`)).status, 200);
    const { body: { session } } = await request();
    assert.equal(session.audio.input.turn_detection.create_response, autoRespond);
    assert.equal(session.audio.input.turn_detection.interrupt_response, true);
  }
});

test('the voice bridge exchanges a Live offer and returns only the SDP answer', async t => {
  const { base, request } = await sessionBridge(t);
  const token = await fetch(`${base}/token?transport=live`);
  assert.deepEqual(await token.json(), {
    model: 'gpt-live-1.1', live: true, local_tools: ['get_ios_version', 'look', 'open_app', 'do'],
  });
  const response = await fetch(`${base}/session?language=zh-Hans`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sdp: 'sdp-offer' }),
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { sdp: 'sdp-answer' });
  const upstream = await request();
  assert.equal(upstream.url, 'https://api.openai.com/v1/live/sessions');
  assert.deepEqual(upstream.body.transport, { type: 'webrtc', sdp: 'sdp-offer' });
  const { session } = upstream.body;
  assert.equal(session.model, 'gpt-live-1.1');
  assert.equal(session.delegation.type, 'responses');
  assert.ok(session.delegation.responses.tools.some(tool => tool.name === 'do'));
  assert.ok(session.delegation.responses.tools.some(tool => tool.name === 'cancel_current_task'));
  for (const prompt of [session.instructions, session.delegation.responses.instructions]) {
    assert.match(prompt, /cancel_current_task/);
    assert.match(prompt, /把停字发过去/);
  }
  assert.match(session.instructions, /Chinese/i);
  assert.match(session.instructions, /Before delegating a new task, say one short sentence about what you will do\./);
  assert.match(session.instructions, /give one short progress update when a meaningful step is confirmed and more work remains/);
  assert.match(session.instructions, /state the verified result and ask one brief, specific follow-up question/);
  assert.match(session.instructions, /For casual chat, reply in two or three short sentences/);
});

test('each Live screenshot uses its own unsaved vision request', async t => {
  const { base, request } = await sessionBridge(t);
  for (const [screen, previous] of [['first', 'second'], ['second', 'first']]) {
    const url = name => `data:image/jpeg;base64,${Buffer.from(`synthetic ${name} screenshot`).toString('base64')}`;
    const response = await fetch(`${base}/screen`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ image: url(screen) }),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { text: 'Screen description' });
    const upstream = await request();
    assert.equal(upstream.url, 'https://api.openai.com/v1/responses');
    assert.equal(upstream.body.store, false);
    assert.equal(upstream.body.previous_response_id, undefined);
    assert.equal(upstream.body.conversation, undefined);
    const images = upstream.body.input.flatMap(item => item.content).filter(part => part.type === 'input_image');
    assert.deepEqual(images.map(image => image.image_url), [url(screen)]);
    assert.ok(!JSON.stringify(upstream.body).includes(url(previous)));
  }
});

// The voice bridge in front of a fixture daemon and phone, as the Poki app reaches it.
async function bridge(t, f) {
  await copyFile(join(root, 'bin/voice-bridge.mjs'), join(f.dir, 'bin/voice-bridge.mjs'));
  const child = spawn(process.execPath, [join(f.dir, 'bin/voice-bridge.mjs'), '--port', '0', '--host', '127.0.0.1', '--mac-tools'], { env: { ...f.env, OPENAI_API_KEY: 'unused' }, stdio: ['ignore', 'pipe', 'inherit'] });
  const exited = once(child, 'exit');
  t.after(async () => { child.kill(); await exited; });
  const lines = createInterface({ input: child.stdout });
  const [line] = await once(lines, 'line');
  const { port } = JSON.parse(line);
  const { secret } = JSON.parse(await readFile(join(f.env.POKI_MCP_STATE_DIR, 'voice-bridge.json'), 'utf8'));
  return body => fetch(`http://127.0.0.1:${port}/voice/${secret}/tool`, { method: 'POST', body: JSON.stringify(body) }).then(r => r.json());
}

test('a voice tap_text the phone has not checked taps nothing; once checked it taps once', async t => {
  const f = await fixture(t);
  await f.set({ label: 'Send' });
  const tool = await bridge(t, f);
  const taps = async () => (await f.events()).filter(e => e.op === 'tap').length;

  // "tap Send", as the model asks for it: the bridge says what it would tap and where, and taps nothing.
  const check = await tool({ call_id: 'c1', name: 'tap_text', arguments: { text: 'Send' } });
  assert.equal(await taps(), 0, JSON.stringify(check));
  assert.equal(check.state, 'check', JSON.stringify(check));
  assert.equal(check.target.text, 'Send');

  // The phone cleared it (its rules, or the owner's OK): the same call taps that element once.
  const done = await tool({ call_id: 'c1', name: 'tap_text', arguments: { text: 'Send' }, checked: { app: check.app.bundle_id, text: check.target.text } });
  assert.equal(done.state, 'done', JSON.stringify(done));
  assert.equal(await taps(), 1);
});

test('a voice tap_text with Poki in front taps nothing, checked or not', async t => {
  const f = await fixture(t);
  await f.set({ label: 'Allow', bundleId: 'nz.zheha.poki', appName: 'Poki' });
  const tool = await bridge(t, f);
  const taps = async () => (await f.events()).filter(e => e.op === 'tap').length;

  // The approval card is in Poki: "tap Allow" is refused before the phone is asked.
  const check = await tool({ call_id: 'c1', name: 'tap_text', arguments: { text: 'Allow' } });
  assert.equal(check.state, 'failed', JSON.stringify(check));
  assert.match(check.output, /only the phone's owner/);

  // A call that says Poki was checked is refused too.
  const done = await tool({ call_id: 'c2', name: 'tap_text', arguments: { text: 'Allow' }, checked: { app: 'nz.zheha.poki', text: 'Allow' } });
  assert.equal(done.state, 'failed', JSON.stringify(done));
  assert.equal(await taps(), 0);
});

test('a voice tap_text on an element known only by its identifier shows the phone that name', async t => {
  const f = await fixture(t);
  await f.set({ elements: [{ role: 'Button', identifier: 'Send', frame: { x: 10, y: 10, width: 40, height: 20 } }] });
  const tool = await bridge(t, f);

  // The phone checks what it is told the element says: the identifier the tap matches, not nothing.
  const check = await tool({ call_id: 'c1', name: 'tap_text', arguments: { text: 'Send' } });
  assert.equal(check.state, 'check', JSON.stringify(check));
  assert.match(check.target.says, /\bSend\b/);
  assert.equal((await f.events()).filter(e => e.op === 'tap').length, 0);
});

test('voice bridge uses the shared behavior spec, keeps all stable sections, and stays within the prompt budget', async t => {
  const { base, request } = await sessionBridge(t);
  const phoneTools = ['get_ios_version', 'look', 'open_app', 'do'];
  const liveTools = [...phoneTools, 'cancel_current_task'];
  const budgets = {
    'zh-Hans': { realtime: 3381, liveVoice: 1870, liveExecutor: 3418 },
    en: { realtime: 3370, liveVoice: 1859, liveExecutor: 3407 },
  };

  for (const [language, budget] of Object.entries(budgets)) {
    assert.equal((await fetch(`${base}/token?language=${language}`)).status, 200);
    const realtime = (await request()).body.session;
    const expectedRealtime = buildVoicePrompt({ role: 'realtime', language, tools: phoneTools, host: 'phone' });
    assert.equal(realtime.instructions, expectedRealtime.text);
    assert.deepEqual(expectedRealtime.sectionIds, VOICE_SECTION_IDS);
    assert.ok(realtime.instructions.length <= budget.realtime, `${language} realtime ${realtime.instructions.length} > ${budget.realtime}`);

    assert.equal((await fetch(`${base}/session?language=${language}`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sdp: 'sdp-offer' }),
    })).status, 200);
    const live = (await request()).body.session;
    const expectedVoice = buildVoicePrompt({ role: 'live_voice', language, tools: liveTools, host: 'phone' });
    const expectedExecutor = buildVoicePrompt({ role: 'live_executor', language, tools: liveTools, host: 'phone' });
    assert.equal(live.instructions, expectedVoice.text);
    assert.equal(live.delegation.responses.instructions, expectedExecutor.text);
    assert.deepEqual(expectedExecutor.sectionIds, VOICE_SECTION_IDS);
    assert.ok(live.instructions.length <= budget.liveVoice, `${language} live voice ${live.instructions.length} > ${budget.liveVoice}`);
    assert.ok(live.delegation.responses.instructions.length <= budget.liveExecutor, `${language} live executor ${live.delegation.responses.instructions.length} > ${budget.liveExecutor}`);
    assert.equal(compareVoicePrompts(expectedRealtime, buildVoicePrompt({ role: 'realtime', language, tools: phoneTools, host: 'phone' })).equal, true);
  }
});

test('hiding a tool removes its promises from voice bridge prompts', async t => {
  const withoutOpenApp = await sessionBridge(t, { extraEnv: { POKI_VOICE_HIDDEN_TOOLS: 'open_app' } });
  assert.equal((await fetch(`${withoutOpenApp.base}/token?language=zh-Hans`)).status, 200);
  const rtNoOpen = (await withoutOpenApp.request()).body.session;
  assert.ok(!rtNoOpen.tools.some(tool => tool.name === 'open_app'));
  assert.ok(!rtNoOpen.instructions.includes('open_app'));
  assert.ok(!rtNoOpen.instructions.includes('Settings page'));

  const withoutDo = await sessionBridge(t, { extraEnv: { POKI_VOICE_HIDDEN_TOOLS: 'do' } });
  assert.equal((await fetch(`${withoutDo.base}/token?language=en`)).status, 200);
  const rtNoDo = (await withoutDo.request()).body.session;
  assert.ok(!rtNoDo.tools.some(tool => tool.name === 'do'));
  assert.ok(!rtNoDo.instructions.includes('one do'));
  assert.ok(!rtNoDo.instructions.includes('button: "home"'));
  assert.ok(!rtNoDo.instructions.includes('Tapping something'));

  const withoutCancel = await sessionBridge(t, { extraEnv: { POKI_VOICE_HIDDEN_TOOLS: 'cancel_current_task' } });
  assert.equal((await fetch(`${withoutCancel.base}/session?language=zh-Hans`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sdp: 'sdp-offer' }),
  })).status, 200);
  const liveNoCancel = (await withoutCancel.request()).body.session;
  assert.ok(!liveNoCancel.delegation.responses.tools.some(tool => tool.name === 'cancel_current_task'));
  assert.ok(!liveNoCancel.instructions.includes('cancel_current_task'));
  assert.ok(!liveNoCancel.delegation.responses.instructions.includes('cancel_current_task'));
});

test('voice bridge logs template version, voice mode, and commit state on startup', async t => {
  const okBridge = await sessionBridge(t);
  assert.equal((await fetch(`${okBridge.base}/token?language=zh-Hans`)).status, 200);
  assert.equal((await fetch(`${okBridge.base}/token?transport=live`)).status, 200);
  assert.equal((await fetch(`${okBridge.base}/session?language=zh-Hans`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sdp: 'sdp-offer' }),
  })).status, 200);
  await new Promise(resolve => setTimeout(resolve, 50));

  const startupEvents = okBridge.events.filter(event => event.event === 'voice_startup');
  assert.ok(startupEvents.some(e => e.template_version === VOICE_SPEC_VERSION && e.mode === 'realtime' && e.commit_state === 'confirmed'));
  assert.ok(startupEvents.some(e => e.template_version === VOICE_SPEC_VERSION && e.mode === 'live' && e.commit_state === 'queued'));
  assert.ok(startupEvents.some(e => e.template_version === VOICE_SPEC_VERSION && e.mode === 'live' && e.commit_state === 'confirmed'));

  const failingBridge = await sessionBridge(t, { failUpstream: true });
  assert.equal((await fetch(`${failingBridge.base}/token?language=en`)).status, 502);
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.ok(failingBridge.events.some(e => e.event === 'voice_startup' && e.template_version === VOICE_SPEC_VERSION && e.mode === 'realtime' && e.commit_state === 'failed'));
});

test('phone direct Swift renderer and Node voice bridge produce identical sections and semantics', async t => {
  if (process.platform !== 'darwin') {
    t.skip('Swift parity check runs on macOS');
    return;
  }
  const execFileAsync = promisify(execFile);
  const dir = await mkdtemp(join(tmpdir(), 'poki-voice-parity-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const cases = [
    { role: 'realtime', language: 'zh-Hans', tools: ['get_ios_version', 'look', 'open_app', 'do'], host: 'phone' },
    { role: 'realtime', language: 'en', tools: ['get_ios_version', 'look', 'open_app', 'do'], host: 'phone' },
    { role: 'live_voice', language: 'zh-Hans', tools: ['get_ios_version', 'look', 'open_app', 'do', 'cancel_current_task'], host: 'phone' },
    { role: 'live_executor', language: 'zh-Hans', tools: ['get_ios_version', 'look', 'open_app', 'do', 'cancel_current_task'], host: 'phone' },
    { role: 'realtime', language: 'zh-Hans', tools: ['get_ios_version', 'look', 'do'], host: 'phone' },
    { role: 'realtime', language: 'en', tools: ['get_ios_version', 'look', 'open_app'], host: 'phone' },
    { role: 'live_executor', language: 'zh-Hans', tools: ['get_ios_version', 'look', 'open_app', 'do'], host: 'phone' },
    { role: 'realtime', language: 'en', tools: ['get_ios_version', 'open_settings', 'read_screen', 'open_app', 'tap_text', 'go_home'], host: 'mac' },
  ];
  const inputPath = join(dir, 'cases.json');
  const mainPath = join(dir, 'main.swift');
  const binPath = join(dir, 'parity');
  await writeFile(inputPath, JSON.stringify(cases));
  await writeFile(mainPath, `
import Foundation
struct CaseInput: Decodable { let role: String; let language: String; let tools: [String]; let host: String }
struct CaseOutput: Encodable { let templateVersion: String; let sectionIds: [String]; let clauseIds: [String]; let text: String }
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let inputs = try JSONDecoder().decode([CaseInput].self, from: data)
let outputs = inputs.map { item -> CaseOutput in
    let built = VoiceBehaviorSpec.shared.build(
        role: VoicePromptRole(rawValue: item.role)!,
        language: item.language,
        tools: item.tools,
        host: VoicePromptHost(rawValue: item.host)!
    )
    return CaseOutput(templateVersion: built.templateVersion, sectionIds: built.sectionIds, clauseIds: built.clauseIds, text: built.text)
}
let encoded = try JSONEncoder().encode(outputs)
FileHandle.standardOutput.write(encoded)
`);
  await execFileAsync('swiftc', ['-DDEBUG', join(root, 'native/ios-app/Poki/Voice/VoiceBehaviorSpec.swift'), mainPath, '-o', binPath]);
  const { stdout } = await execFileAsync(binPath, [inputPath]);
  const swiftResults = JSON.parse(stdout);
  assert.equal(swiftResults.length, cases.length);
  for (let i = 0; i < cases.length; i += 1) {
    const nodeResult = buildVoicePrompt(cases[i]);
    const comparison = compareVoicePrompts(swiftResults[i], nodeResult);
    assert.equal(comparison.equal, true, `case ${i} (${cases[i].role}/${cases[i].language}): ${comparison.differences.join('; ')}`);
  }
});
