import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { describeScreen, elementStates } from '../src/interaction.mjs';
import { fixture, value } from './fixture.mjs';

// Issue #609: what an agent needs to see in the reply text, without a picture.
test('element states name disabled, selected and adjustable controls', () => {
  assert.deepEqual(elementStates({ role: 'Button', label: 'Undo', enabled: false }), ['disabled']);
  assert.deepEqual(elementStates({ role: 'Button', label: 'Undo', trait_names: ['Button', 'Not Enabled'] }), ['disabled']);
  assert.deepEqual(elementStates({ role: 'Button', label: 'Photos', selected: true }), ['selected']);
  assert.deepEqual(elementStates({ role: 'Adjustable', label: 'Exposure', value: '+0.0' }), ['adjustable']);
  assert.deepEqual(elementStates({ role: 'Button', label: 'OK' }), []);
  const screen = describeScreen({ foreground: { bundle_id: 'com.example' }, elements: [] }, [
    { role: 'Button', label: 'Undo', enabled: false, frame: { x: 0, y: 0, width: 40, height: 20 } },
    { role: 'Adjustable', label: 'Exposure', value: '+0.0', frame: { x: 0, y: 30, width: 200, height: 20 } },
  ]);
  assert.ok(screen.text.includes('Button: Undo (disabled)'), JSON.stringify(screen.text));
  assert.ok(screen.text.includes('Adjustable: Exposure = +0.0 (adjustable)'), JSON.stringify(screen.text));
});

test('wait_for keeps a match from a read that answered after the timeout', { timeout: 20000 }, async t => {
  const f = await fixture(t);
  await f.set({ axDelayMs: 1300 });
  const result = await f.call('wait_for', { text: 'First', timeout: 1 });
  assert.ok(!result.isError, JSON.stringify(result.content[0]));
  assert.equal(value(result).matched, true);
});

test('take_screenshot past the point size sends the device pixels, never an upscale', { timeout: 20000 }, async t => {
  const f = await fixture(t);
  await sharp({ create: { width: 300, height: 600, channels: 3, background: 'white' } }).png().toFile(f.image);
  const shot = await f.call('take_screenshot', { max_width: 5000 });
  const image = shot.content.find(c => c.type === 'image');
  const { width } = await sharp(Buffer.from(image.data, 'base64')).metadata();
  assert.ok(width <= 300, `width ${width}`);
});
