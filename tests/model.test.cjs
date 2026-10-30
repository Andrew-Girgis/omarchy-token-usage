const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Model = require('../Model.js');
const format = (n, digits = 0) => n.toFixed(digits);

assert.equal(Model.compact(null, format), '—');
assert.equal(Model.compact(4513225167, format), '4.5B');
assert.deepEqual(Model.timeSegments({agent_seconds: 80, you_seconds: 40, overlap_seconds: 20}), [60, 20, 20]);
assert.deepEqual(Model.projectRows([{name: 'a', value: 100, seconds: 5}, {name: 'b', value: 10, seconds: 60}], true), [{name: 'b', value: 60}, {name: 'a', value: 5}]);

// Every shared tooltip sink passes through our helper. Markup from any source
// must never reach the shell's AutoText widgets, including translated tooltips.
const attack = '<img src="https://example.invalid/tracker"> & <b>unsafe</b>';
assert(!/[<>&]/.test(Model.sharedText(attack)));
assert(Model.sharedText(attack).includes('https://example.invalid/tracker'));
for (const filename of fs.readdirSync(path.resolve(__dirname, '..')).filter(f => f.endsWith('.qml'))) {
  const qml = fs.readFileSync(path.resolve(__dirname, '..', filename), 'utf8');
  for (const sink of qml.matchAll(/tooltipText:\s*([^\n]+)/g)) {
    assert(sink[1].startsWith('Model.sharedText('), `${filename}: unguarded shared tooltip`);
  }
}
const text = fs.readFileSync(path.resolve(__dirname, '../UsageText.qml'), 'utf8');
assert(text.includes('textFormat: Text.PlainText'));
console.log('Model helpers, markup handling, and shared tooltip sinks passed');
