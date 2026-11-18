import test from 'node:test';
import assert from 'node:assert/strict';
import { MARKER, PHRASE, SIGNATURES_BRANCH, STATUS_CONTEXT, VERSION, agrees, run } from '../.github/scripts/contributor-agreement.mjs';

const repo = 'o/r';
const alice = { login: 'alice', id: 7, type: 'User' };
const pull = (number, user = alice, sha = `sha${number}`) => ({ number, state: 'open', user, head: { sha } });

// A small stand-in for the GitHub API: one signatures branch, comments and statuses per pull request.
function fakeGitHub({ pulls = [], file = null, conflicts = 0 } = {}) {
  const gh = { pulls, file, branch: file !== null, comments: {}, statuses: {}, calls: [], nextId: 1, conflicts };
  gh.api = async (path, { method = 'GET', body, bot = false } = {}) => {
    gh.calls.push({ method, path, bot });
    let m;
    if (path.startsWith(`/repos/${repo}/contents/signatures.json`)) {
      if (method === 'GET') return gh.file === null ? null : { sha: `v${gh.file.length}`, content: Buffer.from(gh.file).toString('base64') };
      assert.equal(body.branch, SIGNATURES_BRANCH);
      if (gh.conflicts-- > 0) {
        gh.file = JSON.stringify({ signatures: [{ login: 'bob', id: 9, agreement_version: VERSION }] });
        throw Object.assign(new Error('conflict'), { status: 409 });
      }
      assert.equal(body.sha, gh.file === null ? undefined : `v${gh.file.length}`);
      gh.file = Buffer.from(body.content, 'base64').toString('utf8');
      return {};
    }
    if (path === `/repos/${repo}/git/ref/heads/${SIGNATURES_BRANCH}`) return gh.branch ? {} : null;
    if (path === `/repos/${repo}/git/trees`) { gh.pendingFile = body.tree[0].content; return { sha: 'tree' }; }
    if (path === `/repos/${repo}/git/commits`) { assert.deepEqual(body.parents, []); return { sha: 'commit' }; }
    if (path === `/repos/${repo}/git/refs`) { gh.branch = true; gh.file = gh.pendingFile; return {}; }
    if ((m = path.match(/\/statuses\/(.+)$/))) { assert.equal(body.context, STATUS_CONTEXT); assert.equal(bot, false); gh.statuses[m[1]] = body.state; return {}; }
    if ((m = path.match(/\/issues\/(\d+)\/comments/))) {
      const list = (gh.comments[m[1]] ||= []);
      if (method === 'GET') return list;
      assert.equal(bot, true);
      list.push({ id: gh.nextId++, user: { type: 'Bot' }, body: body.body });
      return {};
    }
    if ((m = path.match(/\/issues\/comments\/(\d+)$/))) {
      Object.values(gh.comments).flat().find((c) => c.id === Number(m[1])).body = body.body;
      return {};
    }
    if ((m = path.match(/\/pulls\/(\d+)$/))) return gh.pulls.find((p) => p.number === Number(m[1])) || null;
    if (path.startsWith(`/repos/${repo}/pulls?`)) return gh.pulls;
    throw new Error(`unexpected ${method} ${path}`);
  };
  return gh;
}

const opened = (pr) => ({ eventName: 'pull_request_target', event: { pull_request: pr }, repo });
const commented = (pr, user, body) => ({ eventName: 'issue_comment', repo, event: { issue: { number: pr.number, pull_request: {} }, comment: { user, body, html_url: 'https://github.com/o/r/pull/1#issuecomment-1' } } });
const signatures = (gh) => JSON.parse(gh.file).signatures;

test('the phrase must be a line of its own', () => {
  assert.ok(agrees(PHRASE));
  assert.ok(agrees(`Read it.\n\n  ${PHRASE.toLowerCase()}.  \n`));
  assert.ok(agrees(`**${PHRASE}**`));
  assert.ok(!agrees(`> ${PHRASE}`));
  assert.ok(!agrees(`I do not think ${PHRASE} applies`));
  assert.ok(!agrees(''));
});

test('a new contributor is asked once and the status waits', async () => {
  const pr = pull(1);
  const gh = fakeGitHub({ pulls: [pr] });
  assert.equal(await run({ ...opened(pr), api: gh.api }), 'asked');
  assert.equal(gh.statuses.sha1, 'pending');
  assert.equal(gh.comments[1].length, 1);
  assert.ok(gh.comments[1][0].body.startsWith(MARKER) && gh.comments[1][0].body.includes('@alice'));
  await run({ ...opened(pr), api: gh.api });
  assert.equal(gh.comments[1].length, 1);
});

test('agreeing starts the signatures branch and turns every open pull request of theirs green', async () => {
  const [first, second, other] = [pull(1), pull(2), pull(3, { login: 'bob', id: 9, type: 'User' })];
  const gh = fakeGitHub({ pulls: [first, second, other] });
  await run({ ...opened(first), api: gh.api });
  await run({ ...opened(second), api: gh.api });
  const result = await run({ ...commented(first, alice, PHRASE), api: gh.api, now: () => new Date('2026-11-18T04:00:00Z') });
  assert.equal(result, 'recorded');
  assert.deepEqual(signatures(gh), [{ login: 'alice', id: 7, agreement_version: VERSION, signed_at: '2026-11-18T04:00:00.000Z', pull_request: 1, comment: 'https://github.com/o/r/pull/1#issuecomment-1' }]);
  assert.deepEqual(gh.statuses, { sha1: 'success', sha2: 'success' });
  assert.ok(gh.comments[1][0].body.includes('on record'));
  assert.ok(gh.comments[2][0].body.includes('on record'));
  assert.equal(gh.comments[3], undefined);
});

test('a later pull request from someone who agreed passes without a comment', async () => {
  const pr = pull(5);
  const gh = fakeGitHub({ pulls: [pr], file: JSON.stringify({ signatures: [{ login: 'alice-old-name', id: 7, agreement_version: VERSION }] }) });
  assert.equal(await run({ ...opened(pr), api: gh.api }), 'signed');
  assert.equal(gh.statuses.sha5, 'success');
  assert.deepEqual(gh.comments[5], []);
});

test('an agreement to an older version does not count', async () => {
  const pr = pull(5);
  const gh = fakeGitHub({ pulls: [pr], file: JSON.stringify({ signatures: [{ login: 'alice', id: 7, agreement_version: VERSION - 1 }] }) });
  assert.equal(await run({ ...opened(pr), api: gh.api }), 'asked');
});

test('nobody can agree for the author', async () => {
  const pr = pull(1);
  const gh = fakeGitHub({ pulls: [pr] });
  const result = await run({ ...commented(pr, { login: 'mallory', id: 66, type: 'User' }, PHRASE), api: gh.api });
  assert.match(result, /not from the pull request author/);
  assert.equal(gh.file, null);
  assert.deepEqual(gh.statuses, {});
});

test('other comments and comments on issues are ignored', async () => {
  const pr = pull(1);
  const gh = fakeGitHub({ pulls: [pr] });
  assert.match(await run({ ...commented(pr, alice, 'What is the Poki Contributor Agreement?'), api: gh.api }), /^skip/);
  const onIssue = commented(pr, alice, PHRASE);
  delete onIssue.event.issue.pull_request;
  assert.match(await run({ ...onIssue, api: gh.api }), /^skip/);
  assert.equal(gh.calls.length, 0);
});

test('maintainers and bots are not asked', async () => {
  for (const user of [{ login: 'JosssphZhou', id: 1, type: 'User' }, { login: 'poki-repo-bot[bot]', id: 2, type: 'Bot' }]) {
    const pr = pull(1, user);
    const gh = fakeGitHub({ pulls: [pr] });
    assert.equal(await run({ ...opened(pr), api: gh.api }), 'exempt');
    assert.equal(gh.statuses.sha1, 'success');
    assert.equal(gh.comments[1], undefined);
  }
});

test('two agreements saved at the same moment both survive', async () => {
  const pr = pull(1);
  const gh = fakeGitHub({ pulls: [pr], file: JSON.stringify({ signatures: [] }), conflicts: 1 });
  await run({ ...commented(pr, alice, PHRASE), api: gh.api });
  assert.deepEqual(signatures(gh).map((s) => s.login), ['bob', 'alice']);
});
