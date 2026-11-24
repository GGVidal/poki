// .github/scripts/promotion.py picks the build a Beta is made from. It runs here against a stand-in
// for gh that answers from a fixed copy of the repository's tags, Pre-alpha runs and artifacts, so
// no request leaves this machine.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { chmodSync, mkdtempSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  actionsTruthy,
  evalActionsExpr,
  evalActionsField,
  evalJobIf,
  jobEnvironment,
  jobNeeds,
  parseWorkflowYaml,
} from './workflow-eval.mjs';

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
      source: 'app-0.4.5-prealpha.1724', source_kind: 'run', sha: BUILT, built_by: RUN(44047275802), version_bump: '0.4.5 -> 0.4.6' },
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
      base_version: '0.4.7', build: '9969', source: 'app-0.4.7-prealpha.9969', source_kind: 'release',
      ipa_sha256: IPA_SHA_OK, sha: HOTFIX_OK, built_by: RUN(862),
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

function makeIpa(path, version, build, marker) {
  execFileSync('python3', ['-B', '-c', [
    'import plistlib, sys, zipfile',
    'with zipfile.ZipFile(sys.argv[1], "w") as archive:',
    '    info = {"CFBundleShortVersionString": sys.argv[2], "CFBundleVersion": sys.argv[3]}',
    '    archive.writestr("Payload/Poki.app/Info.plist", plistlib.dumps(info))',
    '    archive.writestr("Payload/Poki.app/origin.txt", sys.argv[4])',
  ].join('\n'), path, version, build, marker]);
}

function fileSha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

const PUBLISH_GH = `#!/usr/bin/env node
const { appendFileSync, copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } = require('node:fs');
const { join } = require('node:path');
const state = JSON.parse(readFileSync(process.env.PUBLISH_STATE, 'utf8'));
const args = process.argv.slice(2);
const path = args.find(a => a.startsWith('repos/')) ?? '';
const log = entry => appendFileSync(process.env.PUBLISH_LEDGER, JSON.stringify({
  job: process.env.TEST_JOB,
  environment: process.env.TEST_ENV,
  ...entry,
}) + '\\n');
const saveState = () => writeFileSync(process.env.PUBLISH_STATE, JSON.stringify(state));

if (args[0] === 'release' && args[1] === 'view') {
  const tag = args[2];
  if (args.includes('.isDraft')) {
    const rel = state.releases[tag];
    if (!rel) process.exit(1);
    console.log(rel.draft ? 'true' : 'false');
  } else if (args.includes('.assets | length')) {
    const created = state.created[tag];
    if (!created) process.exit(1);
    console.log(created.assetCount);
  } else if (args.includes('.assets[].name')) {
    const assets = state.rolling[tag] ?? state.created[tag]?.assets;
    if (!assets) process.exit(1);
    console.log(assets.join('\\n'));
  } else {
    if (!state.created[tag] && !state.releases[tag]) process.exit(1);
    console.log(tag);
  }
} else if (args[0] === 'release' && args[1] === 'create') {
  const tag = args[2];
  const files = [];
  for (let i = 3; i < args.length; i++) {
    if (args[i].startsWith('--')) {
      if (['--target', '--title', '--notes-file'].includes(args[i])) i++;
      continue;
    }
    files.push(args[i]);
  }
  state.created[tag] = { assetCount: files.length, assets: files.map(f => f.split('/').pop()), draft: args.includes('--draft') };
  saveState();
  log({ kind: 'release-create', target: tag, draft: args.includes('--draft') });
} else if (args[0] === 'release' && args[1] === 'upload') {
  const tag = args[2];
  log({ kind: 'release-upload', target: tag });
} else if (args[0] === 'release' && args[1] === 'edit') {
  const tag = args[2];
  if (args.includes('--draft=false')) {
    if (state.created[tag]) {
      state.created[tag].draft = false;
      saveState();
    }
    log({ kind: 'release-publish', target: tag });
  } else {
    log({ kind: 'release-edit', target: tag });
  }
} else if (args[0] === 'release' && args[1] === 'download') {
  const tag = args[2];
  const dir = args[args.indexOf('--dir') + 1];
  const relDir = state.releaseDirs[tag];
  if (!relDir) process.exit(1);
  mkdirSync(dir, { recursive: true });
  for (const name of state.releaseFiles[tag] ?? []) {
    copyFileSync(join(relDir, name), join(dir, name));
  }
} else if (args[0] === 'run' && args[1] === 'list') {
  const commit = args[args.indexOf('--commit') + 1];
  const id = state.latestMainRun[commit];
  if (!id) process.exit(0);
  console.log(id);
} else if (args[0] === 'run' && args[1] === 'download') {
  const runId = args[2];
  const dir = args[args.indexOf('--dir') + 1];
  const runDir = state.runArtifactDirs[runId];
  if (!runDir) process.exit(1);
  mkdirSync(dir, { recursive: true });
  copyFileSync(join(runDir, 'Poki-external-unsigned.ipa'), join(dir, 'Poki-external-unsigned.ipa'));
  copyFileSync(join(runDir, 'Poki-signing.zip'), join(dir, 'Poki-signing.zip'));
} else if (args[0] === 'api' && path.includes('/actions/runs/')) {
  const runId = path.split('/').pop();
  const meta = state.runMeta[runId];
  if (!meta) process.exit(1);
  if (args.includes('--jq') && args[args.indexOf('--jq') + 1].includes('@tsv')) {
    console.log([meta.event, meta.head_branch, meta.head_sha, meta.conclusion, meta.path].join('\\t'));
  } else {
    console.log(JSON.stringify(meta));
  }
} else if (args[0] === 'api' && path.includes('/commits/') && path.endsWith('/pulls')) {
  console.log('');
} else if (args[0] === 'api' && path.includes('/commits/')) {
  const ref = path.split('/').pop();
  const sha = state.commits[ref];
  if (!sha) process.exit(1);
  console.log(sha);
} else if (args[0] === 'api' && path.includes('/releases/tags/')) {
  const tag = path.split('/').pop();
  const digest = state.signingDigests[tag];
  if (!digest) process.exit(1);
  console.log(digest);
} else if (args[0] === 'api' && path.includes('/branches/')) {
  process.exit(0);
} else {
  process.exit(1);
}
`;

const PUBLISH_GIT = `#!/usr/bin/env bash
case "$1" in
  rev-parse) echo "$SHA" ;;
  config) echo "github-actions[bot]" ;;
  tag)
    if [ "\${2:-}" = --list ]; then exit 0; fi
    ;;
  ls-remote) exit 0 ;;
  log) echo "- fixture commit (1234567)" ;;
  merge-base) exit 1 ;;
  push)
    node -e 'const fs = require("node:fs"); fs.appendFileSync(process.env.PUBLISH_LEDGER, JSON.stringify({ job: process.env.TEST_JOB, environment: process.env.TEST_ENV, kind: "tag-push", target: process.argv[1] }) + "\\n");' "\${*: -1}"
    ;;
  *) exit 1 ;;
esac
`;

function evalPublishJobEnv(job, ctx) {
  const out = {};
  for (const [key, raw] of Object.entries(job.env ?? {})) {
    const val = evalActionsField(raw, ctx);
    out[key] = val === null || val === undefined ? '' : String(val);
  }
  return out;
}

function executePublishWorkflow(t, workflow, rec, state, { onlyStep = null } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'publish-exec-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'bin'));
  mkdirSync(join(dir, 'deploy/cf-relay'), { recursive: true });
  symlinkSync(root, join(dir, 'pipeline'), 'dir');
  writeFileSync(join(dir, 'deploy/cf-relay/worker.js'), '// fixture\n');
  writeFileSync(join(dir, 'bin/gh'), PUBLISH_GH);
  chmodSync(join(dir, 'bin/gh'), 0o755);
  writeFileSync(join(dir, 'bin/git'), PUBLISH_GIT);
  chmodSync(join(dir, 'bin/git'), 0o755);
  const statePath = join(dir, 'state.json');
  const ledgerPath = join(dir, 'ledger.jsonl');
  writeFileSync(statePath, JSON.stringify(state));
  writeFileSync(ledgerPath, '');

  const recJson = rec ? JSON.stringify(rec) : '{}';
  const channel = rec?.channel ?? '';
  const baseCtx = {
    'github.event_name': 'push',
    'github.token': 'stub-token',
    'github.repository': 'example/poki',
    'github.sha': rec?.sha ?? BUILT,
    'inputs.verify_r2': false,
    'needs.read.result': 'success',
    'needs.read.outputs.rec': recJson,
    'needs.read.outputs.channel': channel,
  };

  const results = { read: 'success' };
  const activeJobs = [];
  let lastRun = { status: 0, stdout: '', stderr: '' };

  for (const [jobId, job] of Object.entries(workflow.jobs ?? {})) {
    if (jobId === 'read') continue;
    const jobCtx = { ...baseCtx };
    for (const dep of jobNeeds(job)) {
      jobCtx[`needs.${dep}.result`] = results[dep] ?? 'skipped';
    }
    if (!evalJobIf(job, jobCtx)) {
      results[jobId] = 'skipped';
      continue;
    }
    const environment = jobEnvironment(job, jobCtx);
    activeJobs.push({ id: jobId, environment, uses: job.uses ?? null });
    const jobEnv = evalPublishJobEnv(job, jobCtx);
    const stepCtx = { ...jobCtx, env: jobEnv };
    for (const [k, v] of Object.entries(jobEnv)) stepCtx[`env.${k}`] = v;

    for (const step of job.steps ?? []) {
      if (onlyStep && step.name !== onlyStep) continue;
      const stepRuns = step.if === undefined
        ? true
        : actionsTruthy(evalActionsExpr(String(step.if).trim().replace(/^\$\{\{\s*|\s*\}\}$/g, ''), stepCtx));
      if (!stepRuns || !step.run) continue;
      const runResult = spawnSync('bash', ['-e', '-c', step.run], {
        cwd: dir,
        encoding: 'utf8',
        env: {
          ...process.env,
          ...jobEnv,
          GITHUB_REPOSITORY: 'example/poki',
          GITHUB_SHA: rec?.sha ?? BUILT,
          GITHUB_STEP_SUMMARY: join(dir, 'summary.md'),
          PUBLISH_STATE: statePath,
          PUBLISH_LEDGER: ledgerPath,
          TEST_JOB: jobId,
          TEST_ENV: environment,
          PATH: `${join(dir, 'bin')}:${process.env.PATH}`,
        },
      });
      lastRun = runResult;
      if (runResult.status !== 0) {
        results[jobId] = 'failure';
        return { dir, activeJobs, status: runResult.status, output: runResult.stdout + runResult.stderr, ledger: [] };
      }
    }
    results[jobId] = 'success';
  }

  const ledger = readFileSync(ledgerPath, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map(line => JSON.parse(line));
  return { dir, activeJobs, status: lastRun.status, output: lastRun.stdout + lastRun.stderr, ledger };
}

test('proposing a main commit or rolling Pre-alpha when a failed hotfix shares the same tag binds publish to the tested main run, and hotfix proposals verify their IPA digest', t => {
  const dir = mkdtempSync(join(tmpdir(), 'promotion-f1-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const work = join(dir, 'repo');
  mkdirSync(join(work, 'native/ios-app'), { recursive: true });
  mkdirSync(join(work, '.github'), { recursive: true });
  writeFileSync(join(work, 'native/ios-app/VERSION'), '0.5.1\n');
  const git = (...args) => execFileSync('git', ['-C', work, ...args], { encoding: 'utf8' }).trim();
  git('init', '-q', '-b', 'main');
  git('add', 'native/ios-app/VERSION');
  git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test', '-c', 'commit.gpgSign=false', 'commit', '-qm', 'base');
  const collidingSha = git('rev-parse', 'HEAD');
  const collidingTag = 'app-0.5.1-prealpha.1';

  const mainRunDir = join(dir, 'main-run');
  const failedHotfixDir = join(dir, 'failed-hotfix');
  const goodHotfixDir = join(dir, 'good-hotfix');
  mkdirSync(mainRunDir);
  mkdirSync(failedHotfixDir);
  mkdirSync(goodHotfixDir);

  const mainIpa = join(mainRunDir, 'Poki-external-unsigned.ipa');
  makeIpa(mainIpa, '0.5.1', '1', 'passing-main-run-100');
  writeFileSync(join(mainRunDir, 'Poki-signing.zip'), 'main-signing-zip');

  const failedHotfixIpaName = 'Poki-external-0.5.1-1.ipa';
  const failedHotfixIpa = join(failedHotfixDir, failedHotfixIpaName);
  makeIpa(failedHotfixIpa, '0.5.1', '1', 'failed-hotfix-run-200');
  const failedHotfixSigning = join(failedHotfixDir, 'Poki-signing.zip');
  writeFileSync(failedHotfixSigning, 'failed-hotfix-signing-zip');
  const failedHotfixSha = fileSha256(failedHotfixIpa);
  writeFileSync(join(failedHotfixDir, 'SHA256SUMS'), `${failedHotfixSha}  ${failedHotfixIpaName}\n`);

  const goodHotfixIpaName = 'Poki-external-0.4.7-9969.ipa';
  const goodHotfixIpa = join(goodHotfixDir, goodHotfixIpaName);
  makeIpa(goodHotfixIpa, '0.4.7', '9969', 'passing-hotfix-run-862');
  const goodHotfixSigning = join(goodHotfixDir, 'Poki-signing.zip');
  writeFileSync(goodHotfixSigning, 'good-hotfix-signing-zip');
  const goodHotfixSha = fileSha256(goodHotfixIpa);
  writeFileSync(join(goodHotfixDir, 'SHA256SUMS'), `${goodHotfixSha}  ${goodHotfixIpaName}\n`);

  assert.notEqual(fileSha256(mainIpa), failedHotfixSha, 'fixture main and hotfix IPAs must differ');

  const f1Repo = {
    tags: {
      [collidingTag]: collidingSha,
      'app-0.4.7-prealpha.9969': HOTFIX_OK,
    },
    commits: { [collidingSha]: collidingSha, [HOTFIX_OK]: HOTFIX_OK },
    runs: {
      [collidingSha]: [{ databaseId: 100, status: 'completed', conclusion: 'success', url: RUN(100) }],
    },
    hotfixRuns: [
      { id: 200, run_number: 200, status: 'completed', conclusion: 'failure', display_title: 'Hotfix Pre-alpha 0.5.1', html_url: RUN(200), head_branch: 'main', event: 'workflow_dispatch' },
      { id: 862, run_number: 862, status: 'completed', conclusion: 'success', display_title: 'Hotfix Pre-alpha 0.4.7', html_url: RUN(862), head_branch: 'main', event: 'workflow_dispatch' },
    ],
    provenance: {
      200: { sha: collidingSha, version: '0.5.1', build: '1', ipa_sha256: failedHotfixSha },
      862: { sha: HOTFIX_OK, version: '0.4.7', build: '9969', ipa_sha256: goodHotfixSha },
    },
    releases: {
      [collidingTag]: hotfixRelease(collidingTag, failedHotfixIpaName, failedHotfixSha),
      'app-0.4.7-prealpha.9969': hotfixRelease('app-0.4.7-prealpha.9969', goodHotfixIpaName, goodHotfixSha),
    },
    jobs: {
      100: TESTS.map(name => ({ name, conclusion: 'success' })),
      862: HOTFIX_TESTS.map(name => ({ name, conclusion: 'success' })),
    },
    artifacts: { 100: [{ name: 'Poki-unsigned', expired: false }] },
    rolling: { 'app-prealpha-latest': [failedHotfixIpaName, 'Poki-signing.zip', 'SHA256SUMS'] },
  };

  mkdirSync(join(dir, 'bin'));
  writeFileSync(join(dir, 'bin/gh'), GH);
  chmodSync(join(dir, 'bin/gh'), 0o755);
  writeFileSync(join(dir, 'repo.json'), JSON.stringify(f1Repo));

  const runPromotion = (args, channelsObj = { soak_days: 3, promotions: [] }) => {
    writeFileSync(join(work, '.github/channels.json'), JSON.stringify(channelsObj, null, 2) + '\n');
    writeFileSync(join(work, 'native/ios-app/VERSION'), '0.5.1\n');
    const res = spawnSync('python3', [script, ...args], {
      cwd: work,
      encoding: 'utf8',
      env: { ...process.env, GH_STUB: join(dir, 'repo.json'), GH_REPO: 'example/poki', PATH: `${join(dir, 'bin')}:${process.env.PATH}` },
    });
    return {
      status: res.status,
      stdout: res.stdout,
      output: res.stdout + res.stderr,
      promotions: JSON.parse(readFileSync(join(work, '.github/channels.json'), 'utf8')).promotions,
    };
  };

  const publishWorkflow = parseWorkflowYaml(readFileSync(join(root, '.github/workflows/publish-promotion.yml'), 'utf8'));
  const basePublishState = () => ({
    releases: {
      [collidingTag]: { draft: false },
      'app-0.4.7-prealpha.9969': { draft: false },
    },
    created: {},
    rolling: {},
    releaseDirs: {
      [collidingTag]: failedHotfixDir,
      'app-0.4.7-prealpha.9969': goodHotfixDir,
    },
    releaseFiles: {
      [collidingTag]: [failedHotfixIpaName, 'Poki-signing.zip', 'SHA256SUMS'],
      'app-0.4.7-prealpha.9969': [goodHotfixIpaName, 'Poki-signing.zip', 'SHA256SUMS'],
    },
    commits: {
      [collidingTag]: collidingSha,
      'app-0.4.7-prealpha.9969': HOTFIX_OK,
    },
    signingDigests: {
      [collidingTag]: `sha256:${fileSha256(failedHotfixSigning)}`,
      'app-0.4.7-prealpha.9969': `sha256:${fileSha256(goodHotfixSigning)}`,
    },
    latestMainRun: { [collidingSha]: '100' },
    runArtifactDirs: { 100: mainRunDir },
    runMeta: {
      100: { event: 'push', head_branch: 'main', head_sha: collidingSha, conclusion: 'success', path: '.github/workflows/prealpha.yml' },
    },
  });

  // 1. Proposing by main commit SHA or empty rolling default binds to passing main push run 100,
  //    and publish-promotion.yml downloads run 100's IPA rather than the failed hotfix release.
  for (const input of [collidingSha, '']) {
    const proposed = runPromotion(['propose', 'beta', input, '']);
    assert.equal(proposed.status, 0, `input=${input || '(rolling)'}: ${proposed.output}`);
    assert.equal(proposed.promotions[0].built_by, RUN(100));

    const pending = runPromotion(['pending'], { soak_days: 3, promotions: proposed.promotions });
    assert.equal(pending.status, 0, pending.output);
    const rec = JSON.parse(pending.stdout);

    const published = executePublishWorkflow(t, publishWorkflow, rec, basePublishState(), {
      onlyStep: "The Pre-alpha run's build",
    });
    assert.equal(published.status, 0, published.output);
    assert.deepEqual(
      readFileSync(join(published.dir, 'prealpha/Poki-external-unsigned.ipa')),
      readFileSync(mainIpa),
      `input=${input || '(rolling)'} must publish the passing main run IPA, not the failed hotfix release`,
    );
    assert.equal(proposed.promotions[0].source_kind, 'run');
  }

  // 2. Proposing the colliding versioned tag explicitly still refuses the failed hotfix run 200.
  const refusedTag = runPromotion(['propose', 'beta', collidingTag, '']);
  assert.notEqual(refusedTag.status, 0);
  assert.match(refusedTag.output, /did not succeed \(failure\).*actions\/runs\/200/);

  // 3. Proposing a passing hotfix tag binds source_kind=release and ipa_sha256, downloads that
  //    exact release IPA, and rejects if the release IPA bytes change after proposal.
  const hotfixProposal = runPromotion(['propose', 'beta', 'app-0.4.7-prealpha.9969', '']);
  assert.equal(hotfixProposal.status, 0, hotfixProposal.output);
  assert.equal(hotfixProposal.promotions[0].source_kind, 'release');
  assert.equal(hotfixProposal.promotions[0].ipa_sha256, goodHotfixSha);

  const hotfixPending = runPromotion(['pending'], { soak_days: 3, promotions: hotfixProposal.promotions });
  assert.equal(hotfixPending.status, 0, hotfixPending.output);
  const hotfixRec = JSON.parse(hotfixPending.stdout);

  const hotfixDownloaded = executePublishWorkflow(t, publishWorkflow, hotfixRec, basePublishState(), {
    onlyStep: "The Pre-alpha run's build",
  });
  assert.equal(hotfixDownloaded.status, 0, hotfixDownloaded.output);
  assert.deepEqual(
    readFileSync(join(hotfixDownloaded.dir, 'prealpha/Poki-external-unsigned.ipa')),
    readFileSync(goodHotfixIpa),
  );

  // Tamper the hotfix release IPA (even updating its SHA256SUMS) while keeping the proposal's ipa_sha256.
  const tamperedDir = join(dir, 'tampered-hotfix');
  mkdirSync(tamperedDir);
  const tamperedIpa = join(tamperedDir, goodHotfixIpaName);
  makeIpa(tamperedIpa, '0.4.7', '9969', 'tampered-after-proposal');
  writeFileSync(join(tamperedDir, 'Poki-signing.zip'), 'good-hotfix-signing-zip');
  writeFileSync(join(tamperedDir, 'SHA256SUMS'), `${fileSha256(tamperedIpa)}  ${goodHotfixIpaName}\n`);
  const tamperedState = basePublishState();
  tamperedState.releaseDirs['app-0.4.7-prealpha.9969'] = tamperedDir;

  const rejectedTamper = executePublishWorkflow(t, publishWorkflow, hotfixRec, tamperedState, {
    onlyStep: "The Pre-alpha run's build",
  });
  assert.notEqual(rejectedTamper.status, 0, 'publish must refuse a hotfix release whose IPA digest changed after proposal');

  // 4. promotion.py pending refuses malformed pre-alpha Beta records missing source_kind/built_by/ipa_sha256.
  for (const bad of [
    { channel: 'beta', version: '0.5.1-beta.1', tag: 'app-0.5.1-beta.1', base_version: '0.5.1', build: '1', source: collidingTag, sha: collidingSha, built_by: RUN(100) },
    { channel: 'beta', version: '0.5.1-beta.1', tag: 'app-0.5.1-beta.1', base_version: '0.5.1', build: '1', source: collidingTag, source_kind: 'run', sha: collidingSha },
    { channel: 'beta', version: '0.4.7-beta.1', tag: 'app-0.4.7-beta.1', base_version: '0.4.7', build: '9969', source: 'app-0.4.7-prealpha.9969', source_kind: 'release', sha: HOTFIX_OK, built_by: RUN(862) },
  ]) {
    const res = runPromotion(['pending'], { soak_days: 3, promotions: [bad] });
    assert.notEqual(res.status, 0, `pending must reject incomplete record: ${JSON.stringify(bad)}`);
  }
});

// Older Poki and Poki Setup install whatever the Alpha releases carry, on every channel, so Beta
// and Stable must wait for their own GitHub approval environments, and Alpha compatibility records
// may only run on the Beta path after the Beta approval.
test('publish-promotion.yml gates Beta, Stable, and Alpha compatibility records on their matching approval environments', t => {
  const workflow = parseWorkflowYaml(readFileSync(join(root, '.github/workflows/publish-promotion.yml'), 'utf8'));

  const fixtureDir = mkdtempSync(join(tmpdir(), 'publish-approval-'));
  t.after(() => rmSync(fixtureDir, { recursive: true, force: true }));
  const runDir = join(fixtureDir, 'run');
  const betaSrcDir = join(fixtureDir, 'beta-src');
  mkdirSync(runDir);
  mkdirSync(betaSrcDir);
  makeIpa(join(runDir, 'Poki-external-unsigned.ipa'), '0.4.5', '1724', 'beta-fixture');
  writeFileSync(join(runDir, 'Poki-signing.zip'), 'beta-signing');
  makeIpa(join(betaSrcDir, 'Poki-external-0.4.5-1724.ipa'), '0.4.5', '1724', 'stable-fixture');
  writeFileSync(join(betaSrcDir, 'Poki-signing.zip'), 'stable-signing');

  const makeState = () => ({
    releases: {},
    created: {},
    rolling: {},
    releaseDirs: { 'app-0.4.5-beta.1': betaSrcDir },
    releaseFiles: { 'app-0.4.5-beta.1': ['Poki-external-0.4.5-1724.ipa', 'Poki-signing.zip'] },
    commits: {},
    signingDigests: {},
    latestMainRun: { [BUILT]: '44047275802' },
    runArtifactDirs: { 44047275802: runDir },
    runMeta: {
      44047275802: { event: 'push', head_branch: 'main', head_sha: BUILT, conclusion: 'success', path: '.github/workflows/prealpha.yml' },
    },
  });

  // Beta promotion: Alpha compatibility tag & rolling releases and Beta release all publish under
  // the `beta` approval environment, with Alpha records written before the Beta release.
  const betaRec = {
    channel: 'beta',
    version: '0.4.5-beta.1',
    tag: 'app-0.4.5-beta.1',
    base_version: '0.4.5',
    build: '1724',
    source: 'app-0.4.5-prealpha.1724',
    source_kind: 'run',
    sha: BUILT,
    built_by: RUN(44047275802),
  };
  const beta = executePublishWorkflow(t, workflow, betaRec, makeState());
  assert.equal(beta.status, 0, beta.output);
  const betaAlphaEvents = beta.ledger.filter(e =>
    (e.kind === 'tag-push' && e.target === 'refs/tags/app-0.4.5-alpha.1724')
    || (e.kind === 'release-publish' && ['app-alpha-latest', 'ios-alpha-latest'].includes(e.target)));
  const betaPublishIdx = beta.ledger.findIndex(e => e.kind === 'release-publish' && e.target === 'app-0.4.5-beta.1');
  assert.equal(betaAlphaEvents.length, 3, `expected Alpha tag + app-alpha-latest + ios-alpha-latest, got: ${JSON.stringify(beta.ledger)}`);
  assert.ok(betaPublishIdx >= 0, `expected Beta release publish, got: ${JSON.stringify(beta.ledger)}`);
  for (const event of [...betaAlphaEvents, beta.ledger[betaPublishIdx]]) {
    assert.equal(event.environment, 'beta', `Beta event ${JSON.stringify(event)} must run under environment 'beta'`);
  }
  const lastAlphaIdx = Math.max(...betaAlphaEvents.map(e => beta.ledger.indexOf(e)));
  assert.ok(lastAlphaIdx < betaPublishIdx, 'Alpha compatibility records must be written before the Beta release publishes');
  assert.ok(beta.activeJobs.some(j => j.id === 'mirror-beta' && j.uses === './.github/workflows/publish-r2.yml'));

  // Stable promotion: publishes only under `stable` and never touches Alpha compatibility records.
  const stableRec = {
    channel: 'stable',
    version: '0.4.5',
    tag: 'app-0.4.5',
    base_version: '0.4.5',
    build: '1724',
    source: 'app-0.4.5-beta.1',
    sha: BUILT,
  };
  const stable = executePublishWorkflow(t, workflow, stableRec, makeState());
  assert.equal(stable.status, 0, stable.output);
  const stablePublishes = stable.ledger.filter(e => e.kind === 'release-publish');
  assert.deepEqual(
    stablePublishes.map(e => ({ target: e.target, environment: e.environment })),
    [{ target: 'app-0.4.5', environment: 'stable' }],
  );
  assert.equal(
    stable.ledger.filter(e => /alpha/.test(e.target)).length,
    0,
    `stable promotion must not write Alpha compatibility records: ${JSON.stringify(stable.ledger)}`,
  );
  assert.equal(stable.activeJobs.some(j => j.id === 'mirror-beta'), false);

  // Empty and unknown channels publish nothing.
  for (const ignored of ['', 'alpha']) {
    const res = executePublishWorkflow(t, workflow, ignored ? { ...betaRec, channel: ignored } : null, makeState());
    assert.equal(res.status, 0, res.output);
    assert.equal(res.ledger.length, 0, `channel ${ignored || '(empty)'} must publish nothing`);
  }
});
