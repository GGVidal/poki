import { readFileSync } from 'node:fs';

const file = process.argv[2] ?? 'docs/research/esp-1163/trials.jsonl';
const rows = readFileSync(file, 'utf8').trim().split('\n').map(JSON.parse);
const modes = ['server_vad', 'semantic_vad'];
const samples = ['all', ...new Set(rows.map(row => row.sample))];
const rate = { text_tokens: [4, 24, 0.4], audio_tokens: [32, 64, 0.4], image_tokens: [5, 0, 0.5] };

function distribution(values) {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (!sorted.length) return { n: 0 };
  const middle = Math.floor(sorted.length / 2);
  return {
    n: sorted.length,
    p50: sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2,
    p95: sorted[Math.ceil(sorted.length * 0.95) - 1],
    min: sorted[0],
    max: sorted.at(-1),
  };
}

function cost(events) {
  let usd = 0, missing = 0;
  for (const { type, usage } of events) {
    if (type === 'conversation.item.input_audio_transcription.completed') {
      if (usage?.type === 'tokens') usd += (1.25 * usage.input_tokens + 5 * usage.output_tokens) / 1e6;
      else if (usage?.type === 'duration') usd += 0.003 * usage.seconds / 60;
      else missing++;
    }
    if (type !== 'response.done') continue;
    if (!usage?.input_token_details || !usage.output_token_details) { missing++; continue; }
    const input = usage.input_token_details;
    const output = usage.output_token_details;
    const cached = input.cached_tokens_details ?? {};
    for (const [modality, [inRate, outRate, cachedRate]] of Object.entries(rate)) {
      const discount = cached[modality] ?? 0;
      usd += ((input[modality] ?? 0) * inRate + (output[modality] ?? 0) * outRate - discount * (inRate - cachedRate)) / 1e6;
    }
    if ((input.cached_tokens ?? 0) !== Object.values(cached).reduce((sum, value) => sum + value, 0)) missing++;
  }
  return { usd, missing };
}

function stats(group) {
  const observed = group.filter(row => row.result);
  const successful = observed.filter(row => row.result.success);
  const events = observed.flatMap(row => row.events);
  const { usd, missing } = cost(events);
  const count = key => observed.filter(row => row.result[key] > 0).length;
  const sum = key => observed.reduce((total, row) => total + row.result[key], 0);
  const gapCut = row => {
    if (row.speech.length < 2) return false;
    const [first, second] = row.speech;
    return row.events.some(event => event.type === 'input_audio_buffer.speech_stopped' &&
      event.audioEndMs >= first[1] - 100 && event.audioEndMs < second[0]);
  };
  return {
    trials: group.length,
    measured: observed.length,
    successes: successful.length,
    targetsReached: observed.filter(row => row.result.final === row.result.expected).length,
    trialsCut: count('earlyCutCount'),
    cuts: sum('earlyCutCount'),
    trialsGapCut: observed.filter(gapCut).length,
    trialsEarlyToolRequest: observed.filter(row => row.actions.some(action =>
      ['open_app', 'open_settings', 'tap_text'].includes(action.name) && action.atMs < row.speech.at(-1)[1])).length,
    trialsEarlyDispatch: count('earlyDispatchCount'),
    wrongEffects: sum('wrongEffectCount'),
    duplicateEffects: sum('duplicateEffectCount'),
    missingVadStop: observed.filter(row => !row.events.some(event => event.type === 'input_audio_buffer.speech_stopped')).length,
    failed: group.filter(row => row.failed || row.errors.length).length,
    toolErrorTrials: observed.filter(row => row.actions.some(action =>
      action.error || action.toolState === 'failed' || action.previewState === 'failed')).length,
    canceledResponses: events.filter(event => event.type === 'response.done' && event.status === 'cancelled').length,
    responses: events.filter(event => event.type === 'response.created').length,
    vadMs: distribution(observed.map(row => row.result.finalVadWaitMs)),
    actionMs: distribution(successful.map(row => row.result.firstEffectiveMs)),
    confirmedMs: distribution(successful.map(row => row.result.confirmedMs)),
    confirmAfterDispatchMs: distribution(successful.map(row => row.result.confirmedMs - row.result.firstEffectiveMs)),
    sendLatenessMs: distribution(observed.map(row => row.maxReplayLatenessMs)),
    listedRateUsd: Number(usd.toFixed(6)),
    missingUsageEvents: missing,
  };
}

function paired(group) {
  const baseline = group.filter(row => row.mode === modes[0] && row.result?.success);
  const delta = baseline.flatMap(row => {
    const candidate = group.find(other => other.round === row.round && other.sample === row.sample && other.mode === modes[1] && other.result?.success);
    return candidate ? [candidate.result.firstEffectiveMs - row.result.firstEffectiveMs] : [];
  });
  return { ...distribution(delta), candidateFaster: delta.filter(ms => ms < 0).length, baselineFaster: delta.filter(ms => ms > 0).length };
}

const tally = Object.fromEntries(samples.map(sample => {
  const group = rows.filter(row => sample === 'all' || row.sample === sample);
  return [sample, {
    [modes[0]]: stats(group.filter(row => row.mode === modes[0])),
    [modes[1]]: stats(group.filter(row => row.mode === modes[1])),
    pairedSemanticMinusServerMs: paired(group),
  }];
}));
console.log(JSON.stringify(tally, null, 2));
