// .github/scripts/promotion.py picks the build a Beta is made from. It runs here against a stand-in
// for gh that answers from a fixed copy of the repository's tags, Pre-alpha runs and artifacts, so
// no request leaves this machine.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const script = join(root, '.github/scripts/promotion.py');
const BUILT = '69585293051fee03c7ad110f037d8f4dd2a4e96f';
const FAILED = '55b04d6b3c9190f223271ffc748538291c396e6a';
const UNTESTED = 'c3f1e2a0b9d84c7e6f5a4b3c2d1e0f9a8b7c6d5e';
const HOTFIX_OK = '5e550f8ff6d2a6c7acee99adbd859514be9825bd';
const HOTFIX_FAILED = '5be3531d4f8c6312aa3143e9c7f50a0a614cdb10';
const HOTFIX_UNTESTED = '7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b';
const HOTFIX_MISMATCH = '8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c';
const HOTFIX_DRAFT = '9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d';
const IPA_SHA_OK = 'a'.repeat(64);
const IPA_SHA_OLD = 'b'.repeat(64);
const IPA_SHA_FAILED = 'c'.repeat(64);
const IPA_SHA_UNTESTED = 'd'.repeat(64);
const IPA_SHA_MISMATCH = 'e'.repeat(64);
const SIGNING_SHA = '1'.repeat(64);
const TESTS = ['prealpha', 'app-tests / inprocess', 'app-tests / agent-chat', 'app-tests / app', 'setup-tests'];
const HOTFIX_TESTS = ['resolve-hotfix', 'build-hotfix', 'publish-hotfix', 'app-tests / inprocess', 'app-tests / agent-chat', 'app-tests / app', 'setup-tests'];
const RUN = id => `https://github.com/example/poki/actions/runs/${id}`;

const hotfixRelease = (tag, ipaName, ipaSha, draft = false) => ({
  tag_name: tag,
  draft,
  assets: [
    { name: ipaName, digest: `sha256:${ipaSha}` },
    { name: 'Poki-signing.zip', digest: `sha256:${SIGNING_SHA}` },
    { name: 'SHA256SUMS', digest: `sha256:${'2'.repeat(64)}` },
  ],
});

const repo = {
  tags: {
    'app-0.4.5-prealpha.1724': BUILT,
    'app-0.4.5-prealpha.1700': UNTESTED,
    'app-0.4.4-beta.1': 'b5d72f3dd156b5f7f9cbe4d6605ef10a41d5b6d3',
    'app-0.4.7-prealpha.9969': HOTFIX_OK,
    'app-0.4.7-prealpha.9970': HOTFIX_FAILED,
    'app-0.4.7-prealpha.9971': HOTFIX_UNTESTED,
    'app-0.4.7-prealpha.9972': HOTFIX_MISMATCH,
    'app-0.4.7-prealpha.9973': HOTFIX_DRAFT,
  },
  commits: { [FAILED]: FAILED, [BUILT]: BUILT, [HOTFIX_OK]: HOTFIX_OK },
  runs: {
    [BUILT]: [{ databaseId: 44047275802, status: 'completed', conclusion: 'success', url: RUN(44047275802) }],
    [FAILED]: [{ databaseId: 43694260348, status: 'completed', conclusion: 'failure', url: RUN(43694260348) }],
    [UNTESTED]: [{ databaseId: 43000000001, status: 'completed', conclusion: 'success', url: RUN(43000000001) }],
    // Even if main also built the hotfix commit, proposing the versioned hotfix tag must use the hotfix run.
    [HOTFIX_OK]: [{ databaseId: 44000000001, status: 'completed', conclusion: 'success', url: RUN(44000000001) }],
  },
  hotfixRuns: [
    { id: 860, run_number: 860, status: 'completed', conclusion: 'success', display_title: 'Hotfix Pre-alpha 0.4.7 (9969)', html_url: RUN(860), head_branch: 'main', event: 'workflow_dispatch' },
    { id: 861, run_number: 861, status: 'completed', conclusion: 'failure', display_title: 'Hotfix Pre-alpha 0.4.7', html_url: RUN(861), head_branch: 'main', event: 'workflow_dispatch' },
    { id: 862, run_number: 862, status: 'completed', conclusion: 'success', display_title: 'Hotfix Pre-alpha 0.4.7', html_url: RUN(862), head_branch: 'main', event: 'workflow_dispatch' },
    { id: 863, run_number: 863, status: 'completed', conclusion: 'success', display_title: 'Hotfix Pre-alpha 0.4.7', html_url: RUN(863), head_branch: 'main', event: 'workflow_dispatch' },
    { id: 864, run_number: 864, status: 'completed', conclusion: 'failure', display_title: 'Hotfix Pre-alpha 0.4.7', html_url: RUN(864), head_branch: 'main', event: 'workflow_dispatch' },
    { id: 865, run_number: 865, status: 'completed', conclusion: 'success', display_title: 'Hotfix Pre-alpha 0.4.7 (9971)', html_url: RUN(865), head_branch: 'main', event: 'workflow_dispatch' },
    { id: 866, run_number: 866, status: 'completed', conclusion: 'success', display_title: 'Hotfix Pre-alpha 0.4.7', html_url: RUN(866), head_branch: 'main', event: 'workflow_dispatch' },
  ],
  provenance: {
    860: { sha: HOTFIX_OK, version: '0.4.7', build: '9969', ipa_sha256: IPA_SHA_OLD },
    862: { sha: HOTFIX_OK, version: '0.4.7', build: '9969', ipa_sha256: IPA_SHA_OK },
    863: { sha: 'f'.repeat(40), version: '0.4.7', build: '9969', ipa_sha256: IPA_SHA_OK },
    864: { sha: HOTFIX_FAILED, version: '0.4.7', build: '9970', ipa_sha256: IPA_SHA_FAILED },
    865: { sha: HOTFIX_UNTESTED, version: '0.4.7', build: '9971', ipa_sha256: IPA_SHA_UNTESTED },
    866: { sha: HOTFIX_MISMATCH, version: '0.4.7', build: '9972', ipa_sha256: IPA_SHA_OLD },
  },
  releases: {
    'app-0.4.7-prealpha.9969': hotfixRelease('app-0.4.7-prealpha.9969', 'Poki-external-0.4.7-9969.ipa', IPA_SHA_OK),
    'app-0.4.7-prealpha.9970': hotfixRelease('app-0.4.7-prealpha.9970', 'Poki-external-0.4.7-9970.ipa', IPA_SHA_FAILED),
    'app-0.4.7-prealpha.9971': hotfixRelease('app-0.4.7-prealpha.9971', 'Poki-external-0.4.7-9971.ipa', IPA_SHA_UNTESTED),
    'app-0.4.7-prealpha.9972': hotfixRelease('app-0.4.7-prealpha.9972', 'Poki-external-0.4.7-9972.ipa', IPA_SHA_MISMATCH),
    'app-0.4.7-prealpha.9973': hotfixRelease('app-0.4.7-prealpha.9973', 'Poki-external-0.4.7-9973.ipa', IPA_SHA_OK, true),
  },
  // A run from before the tests joined prealpha.yml has the build job alone.
  jobs: {
    44047275802: TESTS.map(name => ({ name, conclusion: 'success' })),
    43000000001: [{ name: 'prealpha', conclusion: 'success' }],
    862: HOTFIX_TESTS.map(name => ({ name, conclusion: 'success' })),
    865: ['resolve-hotfix', 'build-hotfix', 'publish-hotfix'].map(name => ({ name, conclusion: 'success' })),
  },
  artifacts: { 44047275802: [{ name: 'Poki-unsigned', expired: false }], 43000000001: [{ name: 'Poki-unsigned', expired: false }] },
  rolling: { 'app-prealpha-latest': ['Poki-external-0.4.5-1724.ipa', 'Poki-signing.zip', 'SHA256SUMS'] },
};

const GH = `#!/usr/bin/env node
const fs = require('node:fs');
const repo = JSON.parse(fs.readFileSync(process.env.GH_STUB, 'utf8'));
const args = process.argv.slice(2), path = args.find(a => a.startsWith('repos/')) ?? '';
const out = value => process.stdout.write((typeof value === 'string' ? value : JSON.stringify(value)) + '\\n');
const last = path.split('/').pop();
if (args[0] === 'release' && args[1] === 'view') {
  if (!repo.rolling[args[2]]) process.exit(1);
  out(repo.rolling[args[2]].join('\\n'));
} else if (args[0] === 'run' && args[1] === 'list') out(repo.runs[args[args.indexOf('--commit') + 1]] ?? []);
else if (args[0] === 'run' && args[1] === 'download') {
  const dir = args[args.indexOf('--dir') + 1];
  const prov = repo.provenance[args[2]];
  if (!prov) process.exit(1);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(dir + '/poki-hotfix-source.json', JSON.stringify(prov));
} else if (path.includes('/releases/tags/')) {
  const rel = repo.releases[last];
  if (!rel) process.exit(1);
  out(rel);
} else if (path.includes('/actions/workflows/prealpha.yml/runs?')) {
  for (const r of repo.hotfixRuns) out(r);
} else if (path.includes('/git/ref/tags/')) process.exit(repo.tags[last] ? 0 : 1);
else if (path.includes('/commits/')) {
  const sha = repo.tags[last] ?? repo.commits[last];
  if (!sha) process.exit(1);
  out(sha);
} else if (path.includes('/jobs?')) out(repo.jobs[path.split('/').at(-2)] ?? []);
else if (path.includes('/artifacts')) out(repo.artifacts[path.split('/').at(-2)] ?? []);
else if (path.includes('/tags?')) out(Object.keys(repo.tags).join('\\n'));
else process.exit(2);
`;

function propose(t, from, currentVersion = '0.4.5') {
  const dir = mkdtempSync(join(tmpdir(), 'promotion-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'bin'));
  mkdirSync(join(dir, '.github'));
  mkdirSync(join(dir, 'native/ios-app'), { recursive: true });
  writeFileSync(join(dir, 'bin/gh'), GH);
  chmodSync(join(dir, 'bin/gh'), 0o755);
  writeFileSync(join(dir, 'repo.json'), JSON.stringify(repo));
  const channels = JSON.stringify({ soak_days: 3, promotions: [] }, null, 2) + '\n';
  writeFileSync(join(dir, '.github/channels.json'), channels);
  writeFileSync(join(dir, 'native/ios-app/VERSION'), currentVersion + '\n');
  const done = spawnSync('python3', [script, 'propose', 'beta', from, ''], {
    cwd: dir, encoding: 'utf8',
    env: { ...process.env, GH_STUB: join(dir, 'repo.json'), GH_REPO: 'example/poki', PATH: `${join(dir, 'bin')}:${process.env.PATH}` },
  });
  const after = readFileSync(join(dir, '.github/channels.json'), 'utf8');
  return {
    status: done.status, output: done.stdout + done.stderr, channelsChanged: after !== channels,
    promotions: JSON.parse(after).promotions, version: readFileSync(join(dir, 'native/ios-app/VERSION'), 'utf8').trim(),
  };
}

test('a beta is proposed from the build on app-prealpha-latest, with no alpha', t => {
  const r = propose(t, '');
  assert.equal(r.status, 0, r.output);
  assert.equal(r.promotions.length, 1);
  assert.deepEqual(
    { ...r.promotions[0], proposed: undefined },
    { channel: 'beta', proposed: undefined, version: '0.4.5-beta.1', tag: 'app-0.4.5-beta.1', base_version: '0.4.5', build: '1724',
      source: 'app-0.4.5-prealpha.1724', sha: BUILT, built_by: RUN(44047275802), version_bump: '0.4.5 -> 0.4.6' },
  );
  assert.equal(r.version, '0.4.6');
});

test('a build whose Pre-alpha run failed, in its build or its tests, is refused, naming the run, and nothing is proposed', t => {
  const r = propose(t, FAILED);
  assert.notEqual(r.status, 0);
  assert.match(r.output, /did not succeed \(failure\)/);
  assert.ok(r.output.includes(RUN(43694260348)), r.output);
  assert.equal(r.channelsChanged, false);
  assert.equal(r.version, '0.4.5');
});

test('a build whose run never ran the app tests is refused, naming the missing tests', t => {
  const r = propose(t, 'app-0.4.5-prealpha.1700');
  assert.notEqual(r.status, 0);
  assert.ok(r.output.includes(RUN(43000000001)), r.output);
  assert.match(r.output, /did not pass app-tests \/ inprocess, app-tests \/ agent-chat, app-tests \/ app, setup-tests/);
  assert.equal(r.channelsChanged, false);
  assert.equal(r.version, '0.4.5');
});

test('a tested versioned hotfix Pre-alpha can be proposed to beta using its provenance-verified run', t => {
  const r = propose(t, 'app-0.4.7-prealpha.9969', '0.5.1');
  assert.equal(r.status, 0, r.output);
  assert.equal(r.promotions.length, 1);
  assert.deepEqual(
    { ...r.promotions[0], proposed: undefined },
    {
      channel: 'beta', proposed: undefined, version: '0.4.7-beta.1', tag: 'app-0.4.7-beta.1',
      base_version: '0.4.7', build: '9969', source: 'app-0.4.7-prealpha.9969', sha: HOTFIX_OK,
      built_by: RUN(862),
    },
  );
  // Main is already on a newer version, so proposing an older hotfix must not move VERSION back.
  assert.equal(r.version, '0.5.1');
});

test('a hotfix Pre-alpha that failed tests, skipped tests, mismatched its release, or is still a draft is refused', t => {
  for (const [tag, expected] of [
    ['app-0.4.7-prealpha.9970', /did not succeed \(failure\).*actions\/runs\/864/],
    ['app-0.4.7-prealpha.9971', /actions\/runs\/865.*did not pass app-tests \/ inprocess, app-tests \/ agent-chat, app-tests \/ app, setup-tests/],
    ['app-0.4.7-prealpha.9972', /No hotfix Pre-alpha run matches app-0.4\.7-prealpha\.9972/],
    ['app-0.4.7-prealpha.9973', /still a draft release/],
  ]) {
    const r = propose(t, tag, '0.5.1');
    assert.notEqual(r.status, 0, `${tag} must be refused`);
    assert.match(r.output, expected, `${tag}: ${r.output}`);
    assert.equal(r.channelsChanged, false, `${tag} must not edit channels.json`);
    assert.equal(r.version, '0.5.1', `${tag} must not edit VERSION`);
  }
});

// Parse GitHub Actions expressions used in job/step `if` and `environment` fields with real
// short-circuit semantics (e.g. `cond && 'a' || 'b'`), instead of matching substrings.
function evalActionsExpr(expr, ctx) {
  const tokens = [];
  let i = 0;
  while (i < expr.length) {
    if (/\s/.test(expr[i])) { i++; continue; }
    const two = expr.slice(i, i + 2);
    if (['==', '!=', '&&', '||'].includes(two)) { tokens.push({ t: two }); i += 2; continue; }
    if (['(', ')', '!'].includes(expr[i])) { tokens.push({ t: expr[i] }); i++; continue; }
    if (expr[i] === "'") {
      let s = '';
      i++;
      while (i < expr.length) {
        if (expr[i] === "'" && expr[i + 1] === "'") { s += "'"; i += 2; continue; }
        if (expr[i] === "'") { i++; break; }
        s += expr[i++];
      }
      tokens.push({ t: 'str', v: s });
      continue;
    }
    const m = expr.slice(i).match(/^[A-Za-z_][A-Za-z0-9_.-]*/);
    if (!m) throw new Error(`Unsupported Actions expression near: ${expr.slice(i)}`);
    tokens.push({ t: 'id', v: m[0] });
    i += m[0].length;
  }
  let pos = 0;
  const peek = () => tokens[pos];
  const take = () => tokens[pos++];
  const truthy = v => Boolean(v);
  function parseOr() {
    let left = parseAnd();
    while (peek()?.t === '||') { take(); const right = parseAnd(); left = truthy(left) ? left : right; }
    return left;
  }
  function parseAnd() {
    let left = parseEq();
    while (peek()?.t === '&&') { take(); const right = parseEq(); left = truthy(left) ? right : left; }
    return left;
  }
  function parseEq() {
    let left = parseUnary();
    while (peek()?.t === '==' || peek()?.t === '!=') {
      const op = take().t;
      const right = parseUnary();
      left = op === '==' ? left === right : left !== right;
    }
    return left;
  }
  function parseUnary() {
    if (peek()?.t === '!') { take(); return !truthy(parseUnary()); }
    return parsePrimary();
  }
  function parsePrimary() {
    const tok = take();
    if (!tok) throw new Error(`Unexpected end of expression: ${expr}`);
    if (tok.t === '(') {
      const v = parseOr();
      assert.equal(take()?.t, ')', `Unclosed '(' in: ${expr}`);
      return v;
    }
    if (tok.t === 'str') return tok.v;
    if (tok.t === 'id') {
      if (tok.v === 'true') return true;
      if (tok.v === 'false') return false;
      if (Object.hasOwn(ctx, tok.v)) return ctx[tok.v];
      throw new Error(`Unknown Actions context reference: ${tok.v}`);
    }
    throw new Error(`Unexpected token ${tok.t} in: ${expr}`);
  }
  const value = parseOr();
  assert.equal(pos, tokens.length, `Unparsed trailing tokens in: ${expr}`);
  return value;
}

function evalActionsField(raw, ctx) {
  if (raw == null) return '';
  const trimmed = raw.trim().replace(/^(['"])(.*)\1$/, '$2');
  const m = trimmed.match(/^\$\{\{\s*(.*?)\s*\}\}$/);
  return m ? evalActionsExpr(m[1], ctx) : trimmed;
}

function parseWorkflowJobs(workflow) {
  const jobsSection = workflow.slice(workflow.indexOf('\njobs:\n') + '\njobs:\n'.length);
  const blocks = jobsSection.split(/\n(?=  [a-z0-9-]+:\n)/);
  return blocks.map(block => {
    const [header, ...rest] = block.split('\n');
    const id = header.trim().replace(/:$/, '');
    const body = rest.join('\n');
    const ifMatch = body.match(/^    if:\s*(.+)$/m);
    let envField = body.match(/^    environment:\s*(.+)$/m)?.[1]?.trim() ?? null;
    if (!envField) {
      const envBlock = body.match(/^    environment:\n((?:      .+\n?)+)/m)?.[1] ?? '';
      envField = envBlock.match(/^      name:\s*(.+)$/m)?.[1]?.trim() ?? null;
    }
    const stepsPart = body.split(/^    steps:\n/m)[1] ?? '';
    const steps = stepsPart.split(/\n(?=      - )|^      - /m).filter(s => s.trim()).map(step => ({
      ifExpr: step.match(/^        if:\s*(.+)$/m)?.[1]?.trim() ?? null,
      text: step,
    }));
    return { id, ifExpr: ifMatch?.[1]?.trim() ?? null, envField, steps };
  });
}

// Older Poki and Poki Setup install whatever the Alpha releases carry, on every channel, so Beta
// and Stable must wait for their own GitHub approval environments, and Alpha compatibility records
// may only run on the Beta path after the Beta approval.
test('publish-promotion.yml gates Beta, Stable, and Alpha compatibility records on their matching approval environments', () => {
  const workflow = readFileSync(join(root, '.github/workflows/publish-promotion.yml'), 'utf8');
  const jobs = parseWorkflowJobs(workflow);

  const activeFor = channel => {
    const ctx = {
      'github.event_name': 'push',
      'needs.read.outputs.channel': channel,
      'env.CHANNEL': channel,
      'inputs.verify_r2': false,
    };
    const alphaWriters = [];
    const publishers = [];
    for (const job of jobs) {
      const jobRuns = job.ifExpr ? Boolean(evalActionsExpr(job.ifExpr.replace(/^\$\{\{\s*|\s*\}\}$/g, ''), ctx)) : true;
      if (!jobRuns) continue;
      const environment = job.envField ? String(evalActionsField(job.envField, ctx)) : '';
      for (const step of job.steps) {
        const stepRuns = step.ifExpr ? Boolean(evalActionsExpr(step.ifExpr.replace(/^\$\{\{\s*|\s*\}\}$/g, ''), ctx)) : true;
        if (!stepRuns) continue;
        if (/publish-rolling\.sh alpha/.test(step.text)) alphaWriters.push({ job: job.id, environment });
        if (/gh release create\b/.test(step.text)) publishers.push({ job: job.id, environment });
      }
    }
    return { alphaWriters, publishers };
  };

  const beta = activeFor('beta');
  assert.ok(beta.publishers.length > 0, 'beta promotion has no active release publisher');
  assert.ok(beta.alphaWriters.length > 0, 'beta promotion does not publish Alpha compatibility records');
  for (const entry of [...beta.publishers, ...beta.alphaWriters]) {
    assert.equal(entry.environment, 'beta', `job ${entry.job} ran for beta under environment ${entry.environment || '(none)'}`);
  }

  const stable = activeFor('stable');
  assert.ok(stable.publishers.length > 0, 'stable promotion has no active release publisher');
  assert.equal(stable.alphaWriters.length, 0, 'stable promotion must not write Alpha compatibility records');
  for (const entry of stable.publishers) {
    assert.equal(entry.environment, 'stable', `job ${entry.job} ran for stable under environment ${entry.environment || '(none)'}`);
  }

  for (const ignored of ['', 'alpha']) {
    const none = activeFor(ignored);
    assert.equal(none.publishers.length, 0, `channel ${ignored || '(empty)'} must not publish`);
    assert.equal(none.alphaWriters.length, 0, `channel ${ignored || '(empty)'} must not write Alpha records`);
  }
});
