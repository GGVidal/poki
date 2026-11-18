import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../..');
const read = rel => readFileSync(resolve(root, rel), 'utf8');

const harnessTools = new Set([
  'look', 'do', 'routines', 'status',
  'web_open', 'web_read', 'web_click', 'web_type', 'web_handoff',
  'report_plan', 'finish_task',
]);

test('App Harness prompts preserve tool, routing, evidence, and safety contracts', () => {
  const agentSystem = read('native/ios-app/Poki/Chat/Harness/agent-system.md');
  const harnessSwift = read('native/ios-app/Poki/Chat/Harness/Harness.swift');
  const combined = `${agentSystem}\n${harnessSwift}`;

  assert.ok(agentSystem.trim().length > 0);
  const snakeNames = [...agentSystem.matchAll(/\b[a-z]+(?:_[a-z]+)+\b/g)].map(m => m[0]);
  const unknownTools = [...new Set(snakeNames)].filter(name => !harnessTools.has(name));
  assert.deepEqual(unknownTools, [], `agent-system.md names unknown snake_case tools: ${unknownTools.join(', ')}`);

  assert.match(agentSystem, /latest message/i);
  assert.match(agentSystem, /Markdown table/);
  assert.match(combined, /web_open/);
  assert.match(combined, /web_handoff/);
  assert.match(combined, /report_plan/);
  assert.match(combined, /currentStep/);
  assert.match(combined, /finish_task\(success=true\)/);
  assert.match(combined, /finish_task\(success=false\)/);
  assert.match(combined, /screen:\s*locked/);
  assert.match(combined, /handoff:\s*\{kind:\s*"password"/);
  assert.match(combined, /Messages or notifications/);
  assert.match(combined, /Return/);
  assert.match(combined, /scrolling down|scroll down/i);
  assert.match(combined, /no longer changes|stops changing/i);
  assert.match(combined, /purchase/);
  assert.match(harnessSwift, /swipe down on the Home Screen to search/);
  assert.match(harnessSwift, /say the app is not installed only when that search finds nothing/);
  assert.match(harnessSwift, /routines \{action: \\"save\\"/);

  for (const text of [agentSystem, harnessSwift]) {
    assert.doesNotMatch(text, /[—–]/, 'Public prompt files avoid em and en dashes');
  }
  assert.doesNotMatch(agentSystem, /ESP-\d+/i);
  assert.doesNotMatch(agentSystem, /\p{Script=Han}/u);
});

test('Agent prompts preserve device execution, verification, and safety contracts', () => {
  const piApp = read('agent/prompts/pi-app.md');
  const callDraft = read('agent/prompts/call-draft.md');
  const combined = `${piApp}\n${callDraft}`;

  assert.match(piApp, /latest message/i);
  assert.match(piApp, /report_plan/);
  assert.match(piApp, /currentStep/);
  assert.match(piApp, /unlock_device/);
  assert.match(combined, /handle_alert/);
  assert.match(combined, /Messages or notifications/);
  assert.match(combined, /purchase/);
  assert.match(combined, /text_verified/);
  assert.match(combined, /Return/);
  assert.match(combined, /scrolling down|scroll down/i);
  assert.match(combined, /no longer changes|stops changing/i);
  assert.match(combined, /finish_task\(success=true\)/);
  assert.match(combined, /finish_task\(success=false\)/);
  assert.match(callDraft, /bundle_id/);
  assert.match(callDraft, /failed_step/);
  assert.match(callDraft, /remaining_steps/);

  for (const text of [piApp, callDraft]) {
    assert.doesNotMatch(text, /[—–]/);
    assert.doesNotMatch(text, /ESP-\d+/i);
    assert.doesNotMatch(text, /\p{Script=Han}/u);
  }
});
