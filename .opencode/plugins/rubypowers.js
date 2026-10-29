/**
 * RubyPowers plugin for OpenCode.ai
 *
 * Supports both plugin APIs from one default export:
 * - V2 (OpenCode 2.x): `{ id, setup }`. Skills are added with ctx.skill.transform
 *   and the bootstrap goes into the system prompt of each model request.
 * - V1 (OpenCode 1.18.29+): `server()` returns the V1 hooks. Skills are added
 *   via the config hook and the bootstrap goes into the first user message.
 */

import path from 'path';
import fs from 'fs';
import { execSync } from 'child_process';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rubypowersSkillsDir = path.resolve(__dirname, '../../skills');
const handoffCreateScript = path.resolve(__dirname, '../../hooks/handoff-create');
const handoffRestoreScript = path.resolve(__dirname, '../../hooks/handoff-restore');

// Simple frontmatter extraction (avoid dependency on skills-core for bootstrap)
const extractAndStripFrontmatter = (content) => {
  const match = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) return { frontmatter: {}, content };

  const frontmatterStr = match[1];
  const body = match[2];
  const frontmatter = {};

  for (const line of frontmatterStr.split('\n')) {
    const colonIdx = line.indexOf(':');
    if (colonIdx > 0) {
      const key = line.slice(0, colonIdx).trim();
      const value = line.slice(colonIdx + 1).trim().replace(/^["']|["']$/g, '');
      frontmatter[key] = value;
    }
  }

  return { frontmatter, content: body };
};

const getBootstrapContent = () => {
  const skillPath = path.join(rubypowersSkillsDir, 'using-rubypowers', 'SKILL.md');
  if (!fs.existsSync(skillPath)) return null;

  const fullContent = fs.readFileSync(skillPath, 'utf8');
  const { content } = extractAndStripFrontmatter(fullContent);

  const toolMapping = `**Tool Mapping for OpenCode:**
When skills reference tools you don't have, substitute OpenCode equivalents:
- \`TodoWrite\` → \`todowrite\`
- \`Task\` tool with subagents → Use OpenCode's subagent system (@mention)
- \`Skill\` tool → OpenCode's native \`skill\` tool
- \`Read\`, \`Write\`, \`Edit\`, \`Bash\` → Your native tools

Use OpenCode's native \`skill\` tool to list and load rubypowers skills.`;

  return `<EXTREMELY_IMPORTANT>
You have RubyPowers: superpowers for Ruby and Rails.

**IMPORTANT: The using-rubypowers skill content is included below. It is ALREADY LOADED - you are currently following it. Do NOT use the skill tool to load "using-rubypowers" again - that would be redundant.**

${content}

${toolMapping}
</EXTREMELY_IMPORTANT>`;
};

// Reads every skills/<name>/SKILL.md into the V2 Skill.Info shape.
const loadSkills = () => {
  if (!fs.existsSync(rubypowersSkillsDir)) return [];

  return fs.readdirSync(rubypowersSkillsDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => path.join(rubypowersSkillsDir, entry.name, 'SKILL.md'))
    .filter((skillPath) => fs.existsSync(skillPath))
    .map((skillPath) => {
      const { frontmatter, content } = extractAndStripFrontmatter(fs.readFileSync(skillPath, 'utf8'));
      const name = frontmatter.name || path.basename(path.dirname(skillPath));
      const skill = { id: name, name, path: skillPath, content };
      if (frontmatter.description) skill.description = frontmatter.description;
      return skill;
    });
};

// Handoff capture is best-effort — don't block compaction on failure
const runHandoffCreate = (cwd) => {
  if (!fs.existsSync(handoffCreateScript)) return;
  try {
    execSync(`bash "${handoffCreateScript}" --trigger compact`, {
      cwd,
      timeout: 10000,
      stdio: ['pipe', 'pipe', 'pipe']
    });
  } catch (_e) {}
};

// Restore is best-effort — session continues without handoff on failure
const runHandoffRestore = (cwd) => {
  if (!fs.existsSync(handoffRestoreScript)) return null;
  try {
    const output = execSync(`bash "${handoffRestoreScript}"`, {
      cwd,
      timeout: 10000,
      stdio: ['pipe', 'pipe', 'pipe'],
      encoding: 'utf8'
    });
    if (!output || !output.trim()) return null;
    return JSON.parse(output.trim()).additionalContext || null;
  } catch (_e) {
    return null;
  }
};

// V2 plugin API
const setup = async (ctx) => {
  const directory = ctx.location?.directory || process.cwd();
  const skills = loadSkills();

  await ctx.skill.transform((editor) => {
    for (const skill of skills) {
      if (!editor.get(skill.id)) editor.add(skill);
    }
  });

  // Runs before each agent model request; changes are not stored in history.
  await ctx.session.hook('context', (event) => {
    const bootstrap = getBootstrapContent();
    if (bootstrap) event.system.push({ type: 'text', text: bootstrap });
  });

  // V2 has no post-compaction hook, so capture the handoff and hand it to the
  // compaction request. The summary then carries it into the new context.
  await ctx.session.hook('compaction', (event) => {
    runHandoffCreate(directory);
    const handoff = runHandoffRestore(directory);
    if (handoff) {
      event.system.push({
        type: 'text',
        text: `Keep the handoff document below in the summary. It is needed to continue the work after compaction.\n\n${handoff}`
      });
    }
  });
};

// V1 plugin API
const server = async ({ directory }) => ({
  // Inject skills path into live config so OpenCode discovers RubyPowers skills
  // without requiring manual symlinks or config file edits.
  // This works because Config.get() returns a cached singleton — modifications
  // here are visible when skills are lazily discovered later.
  config: async (config) => {
    config.skills = config.skills || {};
    config.skills.paths = config.skills.paths || [];
    if (!config.skills.paths.includes(rubypowersSkillsDir)) {
      config.skills.paths.push(rubypowersSkillsDir);
    }
  },

  // Inject bootstrap into the first user message (avoids per-turn token cost
  // of system messages and fixes model compatibility with Qwen and others).
  'experimental.chat.messages.transform': async (_input, output) => {
    const bootstrap = getBootstrapContent();
    if (!bootstrap || !output.messages.length) return;
    const firstUser = output.messages.find(m => m.info.role === 'user');
    if (!firstUser || !firstUser.parts.length) return;
    // Only inject once
    if (firstUser.parts.some(p => p.type === 'text' && p.text.includes('EXTREMELY_IMPORTANT'))) return;
    const ref = firstUser.parts[0];
    firstUser.parts.unshift({ ...ref, type: 'text', text: bootstrap });
  },

  // Capture handoff document before compaction
  'experimental.session.compacting': async () => {
    runHandoffCreate(directory || process.cwd());
  },

  // Restore handoff document after compaction
  'session.compacted': async () => {
    const context = runHandoffRestore(directory || process.cwd());
    if (context) return { additionalContext: context };
  }
});

export default { id: 'rubypowers', setup, server };
