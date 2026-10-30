#!/usr/bin/env bash
# Test: Plugin API shape
# Verifies the plugin default export works with the OpenCode V2 API ({ id, setup })
# and the V1 API (server()), using mock objects instead of a running OpenCode.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Test: Plugin API shape ==="

if ! command -v node >/dev/null 2>&1; then
    echo "  [SKIP] node not found"
    exit 0
fi

# Run in a throwaway git repo so the handoff hooks do not touch this repository.
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
git -C "$WORK_DIR" init -q

PLUGIN_PATH="$REPO_ROOT/.opencode/plugins/rubypowers.js" WORK_DIR="$WORK_DIR" \
node --input-type=module <<'EOF'
const mod = await import(process.env.PLUGIN_PATH);
const plugin = mod.default;
const fail = (msg) => { console.log(`  [FAIL] ${msg}`); process.exit(1); };
const pass = (msg) => console.log(`  [PASS] ${msg}`);

console.log('Test 1: Default export shape...');
if (!plugin || plugin.id !== 'rubypowers') fail('default export has no id "rubypowers"');
if (typeof plugin.setup !== 'function') fail('default export has no setup function');
if (typeof plugin.server !== 'function') fail('default export has no V1 server function');
const namedExports = Object.keys(mod).filter((key) => key !== 'default');
if (namedExports.length) fail(`unexpected named exports: ${namedExports.join(', ')}`);
pass('default export is { id, setup, server }');

console.log('Test 2: V2 setup registers skills and hooks...');
const added = [];
const hooks = {};
const ctx = {
  location: { directory: process.env.WORK_DIR },
  skill: {
    transform: async (fn) => fn({ get: () => undefined, add: (skill) => added.push(skill) })
  },
  session: {
    hook: async (name, fn) => { hooks[name] = fn; }
  }
};
await plugin.setup(ctx);
const usingSkill = added.find((skill) => skill.id === 'using-rubypowers');
if (!usingSkill) fail('using-rubypowers skill was not added');
if (!usingSkill.path.endsWith('skills/using-rubypowers/SKILL.md')) fail(`wrong skill path: ${usingSkill.path}`);
if (!usingSkill.description) fail('skill description missing');
if (usingSkill.content.startsWith('---')) fail('skill content still has frontmatter');
const foldedSkill = added.find((skill) => skill.id === 'hwc-forms-validation');
if (!foldedSkill) fail('hwc-forms-validation skill was not added');
if (!foldedSkill.description.startsWith('Handle Hotwire form workflows')) fail(`YAML folded description not resolved: ${foldedSkill.description}`);
pass(`${added.length} skills added`);
if (!hooks.context || !hooks.compaction) fail('context and compaction hooks not registered');
pass('context and compaction hooks registered');

console.log('Test 3: V2 context hook adds the bootstrap to the system prompt...');
const contextEvent = { system: [], messages: [] };
await hooks.context(contextEvent);
const bootstrapPart = contextEvent.system.find((part) => part.type === 'text' && part.text.includes('EXTREMELY_IMPORTANT'));
if (!bootstrapPart) fail('bootstrap not added to event.system');
if (contextEvent.messages.length) fail('context hook changed messages');
pass('bootstrap added to event.system');

console.log('Test 4: V2 compaction hook passes the handoff to the summary request...');
const compactionEvent = { system: [], messages: [] };
await hooks.compaction(compactionEvent);
const handoffPart = compactionEvent.system.find((part) => part.text.includes('<handoff-restored>'));
if (!handoffPart) fail('handoff not added to compaction system prompt');
pass('handoff added to compaction system prompt');

console.log('Test 5: V1 server() returns the V1 hooks...');
const v1 = await plugin.server({ directory: process.env.WORK_DIR });
for (const key of ['config', 'experimental.chat.messages.transform', 'experimental.session.compacting', 'session.compacted']) {
  if (typeof v1[key] !== 'function') fail(`V1 hook missing: ${key}`);
}
const config = {};
await v1.config(config);
if (!config.skills.paths.some((p) => p.endsWith('/skills'))) fail('V1 config hook did not add the skills path');
pass('V1 hooks present and config hook adds the skills path');
EOF

echo ""
echo "=== All plugin API tests passed ==="
