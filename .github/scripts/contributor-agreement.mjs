// One-time contributor sign-off. Runs from .github/workflows/contributor-agreement.yml.
//
// A pull request's author agrees to CONTRIBUTOR_AGREEMENT.md once, by commenting the line in
// PHRASE on a pull request. The agreement is saved to signatures.json on the SIGNATURES_BRANCH
// branch and covers every later pull request. Each pull request gets a commit status named
// STATUS_CONTEXT: pending until its author has agreed, success after.
//
// This script reads only event data and the API. It never checks out or runs pull request code.
import { readFileSync } from 'node:fs';

export const VERSION = 1; // Matches "Version N" in CONTRIBUTOR_AGREEMENT.md. Raise both to ask everyone again.
export const PHRASE = 'I agree to the Poki Contributor Agreement';
export const MARKER = '<!-- poki-contributor-agreement -->';
export const STATUS_CONTEXT = 'Contributor agreement';
export const SIGNATURES_BRANCH = 'contributor-signatures';
export const SIGNATURES_FILE = 'signatures.json';
// Maintainers, who are not asked. Bots are never asked.
const EXEMPT = new Set(['josssphzhou', 'zhehanzhang']);

// True when one line of the comment is the phrase. A quoted line ("> I agree ...") does not count.
export function agrees(body) {
  const want = PHRASE.toLowerCase();
  return String(body || '').split('\n').some((line) => line.trim().replace(/^[*_`"“]+|[*_`"”.!。]+$/g, '').replace(/\s+/g, ' ').toLowerCase() === want);
}

export const exempt = (user) => !user || user.type === 'Bot' || EXEMPT.has(String(user.login).toLowerCase());

export const hasSigned = (store, user) => store.signatures.some((s) => s.id === user.id && s.agreement_version === VERSION);

const links = (repo) => ({
  agreement: `https://github.com/${repo}/blob/main/CONTRIBUTOR_AGREEMENT.md`,
  record: `https://github.com/${repo}/blob/${SIGNATURES_BRANCH}/${SIGNATURES_FILE}`,
});

export function askBody(repo, login) {
  const { agreement } = links(repo);
  return `${MARKER}
Thanks for the pull request, @${login}. Before it can be merged, please agree once to the [Poki Contributor Agreement](${agreement}). It says you have the right to submit your contributions and that you release them under AGPL-3.0-only. It covers this pull request and all your later ones, so you will not be asked again.

To agree, comment on this pull request from your own account with this line:

\`\`\`
${PHRASE}
\`\`\`

**If an AI agent opened this for you**, the agreement is still yours to give. Read it, then post the comment yourself or tell your agent to.

感谢你的贡献。合并前请先同意一次 [Poki 贡献者协议](${agreement})：你确认有权提交这些贡献，并以 AGPL-3.0-only 许可发布。只需同意一次，之后的 pull request 不会再询问。请用你自己的账号在本 pull request 下评论上面那一行英文原文。`;
}

export function thanksBody(repo, login) {
  const { agreement, record } = links(repo);
  return `${MARKER}
Thanks, @${login}. Your agreement to the [Poki Contributor Agreement](${agreement}) is [on record](${record}) and covers your later pull requests too. 已记录你的同意，之后的 pull request 不会再询问。`;
}

// The store lives on its own branch, so saving an agreement never touches main.
export async function loadStore(api, repo) {
  const file = await api(`/repos/${repo}/contents/${SIGNATURES_FILE}?ref=${SIGNATURES_BRANCH}`);
  if (!file) return { sha: null, store: { agreement: 'CONTRIBUTOR_AGREEMENT.md', signatures: [] } };
  return { sha: file.sha, store: JSON.parse(Buffer.from(file.content, 'base64').toString('utf8')) };
}

async function saveStore(api, repo, store, sha, message) {
  const text = JSON.stringify(store, null, 2) + '\n';
  if (sha || await api(`/repos/${repo}/git/ref/heads/${SIGNATURES_BRANCH}`)) {
    return api(`/repos/${repo}/contents/${SIGNATURES_FILE}`, { method: 'PUT', bot: true, body: { message, branch: SIGNATURES_BRANCH, content: Buffer.from(text).toString('base64'), ...(sha ? { sha } : {}) } });
  }
  // First agreement: start the branch with a commit that has no parent, so it holds only this file.
  const tree = await api(`/repos/${repo}/git/trees`, { method: 'POST', bot: true, body: { tree: [{ path: SIGNATURES_FILE, mode: '100644', type: 'blob', content: text }] } });
  const commit = await api(`/repos/${repo}/git/commits`, { method: 'POST', bot: true, body: { message, tree: tree.sha, parents: [] } });
  return api(`/repos/${repo}/git/refs`, { method: 'POST', bot: true, body: { ref: `refs/heads/${SIGNATURES_BRANCH}`, sha: commit.sha } });
}

// Adds one agreement. Two people agreeing at the same moment collide on the file's sha; the
// loser reads the file again and retries.
export async function record(api, repo, entry) {
  for (let attempt = 0; ; attempt++) {
    const { sha, store } = await loadStore(api, repo);
    if (store.signatures.some((s) => s.id === entry.id && s.agreement_version === entry.agreement_version)) return store;
    store.signatures.push(entry);
    try {
      await saveStore(api, repo, store, sha, `Record contributor agreement: ${entry.login}`);
      return store;
    } catch (e) {
      if (attempt >= 4 || ![409, 422].includes(e.status)) throw e;
    }
  }
}

async function setStatus(api, repo, sha, state, description) {
  await api(`/repos/${repo}/statuses/${sha}`, { method: 'POST', body: { state, context: STATUS_CONTEXT, description, target_url: links(repo).agreement } });
}

async function upsertComment(api, repo, number, body, { create }) {
  const comments = await api(`/repos/${repo}/issues/${number}/comments?per_page=100`);
  const mine = (comments || []).find((c) => c.user?.type === 'Bot' && c.body?.startsWith(MARKER));
  if (mine) { if (mine.body !== body) await api(`/repos/${repo}/issues/comments/${mine.id}`, { method: 'PATCH', bot: true, body: { body } }); }
  else if (create) await api(`/repos/${repo}/issues/${number}/comments`, { method: 'POST', bot: true, body: { body } });
}

async function markSigned(api, repo, pr, { thank }) {
  await setStatus(api, repo, pr.head.sha, 'success', `${pr.user.login} has agreed`);
  // Pull requests that were never asked stay quiet.
  await upsertComment(api, repo, pr.number, thanksBody(repo, pr.user.login), { create: thank });
}

export async function run({ eventName, event, repo, api, now = () => new Date() }) {
  let pr = event.pull_request;
  let comment = null;
  if (eventName === 'issue_comment') {
    if (!event.issue?.pull_request || !agrees(event.comment?.body)) return 'skip: not an agreement comment';
    pr = await api(`/repos/${repo}/pulls/${event.issue.number}`);
    // Only the author's own account can agree for the author.
    if (!pr || event.comment.user?.id !== pr.user?.id) return 'skip: comment is not from the pull request author';
    comment = event.comment;
  }
  if (!pr || pr.state !== 'open') return 'skip: pull request is not open';
  const author = pr.user;
  if (exempt(author)) {
    await setStatus(api, repo, pr.head.sha, 'success', 'Not needed for maintainers and bots');
    return 'exempt';
  }
  let { store } = await loadStore(api, repo);
  if (hasSigned(store, author)) {
    await markSigned(api, repo, pr, { thank: false });
    return 'signed';
  }
  if (!comment) {
    await setStatus(api, repo, pr.head.sha, 'pending', `Waiting for ${author.login} to agree once`);
    await upsertComment(api, repo, pr.number, askBody(repo, author.login), { create: true });
    return 'asked';
  }
  store = await record(api, repo, {
    login: author.login, id: author.id, agreement_version: VERSION,
    signed_at: now().toISOString(), pull_request: pr.number, comment: comment.html_url,
  });
  await markSigned(api, repo, pr, { thank: true });
  // Their other open pull requests turn green too.
  const open = await api(`/repos/${repo}/pulls?state=open&per_page=100`);
  for (const other of open || []) {
    if (other.number !== pr.number && other.user?.id === author.id) await markSigned(api, repo, other, { thank: false });
  }
  return 'recorded';
}

// Comments and the signatures file are written as Poki Repo Bot when its token is there
// (BOT_TOKEN). Everything else uses the workflow's own token, and so do those writes when the
// bot's token is missing or GitHub refuses it (the app lacks a permission).
function githubApi(env) {
  const call = async (token, path, method, body) => fetch(`https://api.github.com${path}`, {
    method,
    headers: { authorization: `Bearer ${token}`, accept: 'application/vnd.github+json', 'content-type': 'application/json', 'x-github-api-version': '2022-11-28' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return async (path, { method = 'GET', body, bot = false } = {}) => {
    let res = await call((bot && env.BOT_TOKEN) || env.GITHUB_TOKEN, path, method, body);
    if (res.status === 403 && bot && env.BOT_TOKEN) {
      console.log(`Poki Repo Bot was refused ${method} ${path}; using the workflow token`);
      res = await call(env.GITHUB_TOKEN, path, method, body);
    }
    if (res.status === 404 && method === 'GET') return null;
    if (!res.ok) throw Object.assign(new Error(`${method} ${path}: ${res.status} ${await res.text()}`), { status: res.status });
    return res.status === 204 ? null : res.json();
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  run({ eventName: process.env.GITHUB_EVENT_NAME, event, repo: process.env.GITHUB_REPOSITORY, api: githubApi(process.env) })
    .then((result) => console.log(result))
    .catch((e) => { console.error(e); process.exit(1); });
}
