import { readFileSync } from 'node:fs';

const specURL = new URL('./data/voice-behavior-spec.json', import.meta.url);
export const voiceBehaviorSpec = JSON.parse(readFileSync(specURL, 'utf8'));
export const VOICE_SPEC_VERSION = voiceBehaviorSpec.version;
export const VOICE_SECTION_IDS = voiceBehaviorSpec.sections.map(section => section.id);
export const lockCheckGuidance = voiceBehaviorSpec.lock_check;

const SCREEN_IMAGE_TOOLS = ['look', 'do', 'open_app'];
const NUMBERED_TOOLS = ['look', 'do'];

function formatList(items, conjunction) {
  if (items.length <= 1) return items.join('');
  if (items.length === 2) return `${items[0]} ${conjunction} ${items[1]}`;
  return `${items.slice(0, -1).join(', ')} ${conjunction} ${items.at(-1)}`;
}

export function resolveVoiceLanguageName(code) {
  if (typeof code === 'string' && Object.hasOwn(voiceBehaviorSpec.language_names, code)) {
    return voiceBehaviorSpec.language_names[code];
  }
  try {
    if (/^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$/.test(code ?? '')) {
      return new Intl.DisplayNames(['en'], { type: 'language' }).of(code) || 'English';
    }
  } catch {}
  return 'English';
}

function matchesClause(clause, { role, host, toolSet }) {
  if (!clause.roles.includes(role)) return false;
  if (clause.hosts && !clause.hosts.includes(host)) return false;
  if (clause.requires_non_empty_tools && toolSet.size === 0) return false;
  if (clause.requires_all_tools && !clause.requires_all_tools.every(name => toolSet.has(name))) return false;
  if (clause.requires_any_tools && !clause.requires_any_tools.some(name => toolSet.has(name))) return false;
  if (clause.forbids_tools && clause.forbids_tools.some(name => toolSet.has(name))) return false;
  return true;
}

export function buildVoicePrompt({ role, language, tools = [], host = 'phone' }) {
  const orderedTools = [...new Set(tools.filter(name => typeof name === 'string' && name.length > 0))];
  const toolSet = new Set(orderedTools);
  const languageName = resolveVoiceLanguageName(language);
  const screenTools = formatList(SCREEN_IMAGE_TOOLS.filter(name => toolSet.has(name)), 'and');
  const numberedTools = formatList(NUMBERED_TOOLS.filter(name => toolSet.has(name)), 'or');
  const values = {
    language: languageName,
    lock_check: voiceBehaviorSpec.lock_check,
    screen_tools: screenTools,
    numbered_tools: numberedTools,
    cancel_tool: 'cancel_current_task',
  };

  const sections = [];
  const clauseIds = [];
  for (const section of voiceBehaviorSpec.sections) {
    const selected = [];
    for (const clause of voiceBehaviorSpec.clauses) {
      if (clause.section !== section.id) continue;
      if (!matchesClause(clause, { role, host, toolSet })) continue;
      const text = clause.text.replace(/\{([a-z_]+)\}/g, (_, key) => values[key] ?? '');
      selected.push({ id: clause.id, text });
      clauseIds.push(clause.id);
    }
    if (selected.length > 0) {
      sections.push({ id: section.id, title: section.title, clauses: selected });
    }
  }

  const text = sections
    .map(section => `# ${section.title}\n${section.clauses.map(clause => clause.text).join('\n')}`)
    .join('\n\n');

  return {
    templateVersion: voiceBehaviorSpec.version,
    role,
    mode: role === 'realtime' ? 'realtime' : 'live',
    host,
    language: language ?? '',
    languageName,
    tools: orderedTools,
    sectionIds: sections.map(section => section.id),
    clauseIds,
    sections,
    text,
  };
}

export function compareVoicePrompts(left, right) {
  const differences = [];
  if (left.templateVersion !== right.templateVersion) {
    differences.push(`templateVersion: ${left.templateVersion} !== ${right.templateVersion}`);
  }
  if (JSON.stringify(left.sectionIds) !== JSON.stringify(right.sectionIds)) {
    differences.push(`sectionIds: ${JSON.stringify(left.sectionIds)} !== ${JSON.stringify(right.sectionIds)}`);
  }
  if (JSON.stringify(left.clauseIds) !== JSON.stringify(right.clauseIds)) {
    differences.push(`clauseIds: ${JSON.stringify(left.clauseIds)} !== ${JSON.stringify(right.clauseIds)}`);
  }
  if (left.text !== right.text) {
    differences.push(`text length ${left.text.length} vs ${right.text.length}`);
  }
  return {
    equal: differences.length === 0,
    versionMatch: left.templateVersion === right.templateVersion,
    sectionIdsMatch: JSON.stringify(left.sectionIds) === JSON.stringify(right.sectionIds),
    clauseIdsMatch: JSON.stringify(left.clauseIds) === JSON.stringify(right.clauseIds),
    textMatch: left.text === right.text,
    differences,
  };
}
