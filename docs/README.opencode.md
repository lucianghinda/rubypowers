# RubyPowers for OpenCode

Complete guide for using RubyPowers with [OpenCode.ai](https://opencode.ai).

## Installation

Users upgrading from a pre-8.0.0 install should replace the old plugin line
with the RubyPowers line below, clean up the old symlink or clone paths, and
then follow these installation steps.

Add RubyPowers to your `opencode.json` (global or project-level).

OpenCode 2.x uses the `plugins` key:

```json
{
  "plugins": ["rubypowers@git+https://github.com/lucianghinda/rubypowers.git"]
}
```

OpenCode 1.x (1.18.29 or newer) uses the `plugin` key:

```json
{
  "plugin": ["rubypowers@git+https://github.com/lucianghinda/rubypowers.git"]
}
```

Restart OpenCode. The plugin auto-installs via Bun and registers all skills automatically.

Verify by asking: "Tell me about RubyPowers"

### Migrating from the old symlink-based install

If you previously installed superpowers-ruby using `git clone` and symlinks,
remove the old setup. Also remove the RubyPowers legacy symlink name if present:

```bash
# Remove old symlinks
rm -f ~/.config/opencode/plugins/rubypowers.js
rm -f ~/.config/opencode/plugins/superpowers.js
rm -rf ~/.config/opencode/skills/rubypowers
rm -rf ~/.config/opencode/skills/superpowers-ruby

# Optionally remove the cloned repo
rm -rf ~/.config/opencode/rubypowers
rm -rf ~/.config/opencode/superpowers-ruby

# Remove skills.paths from opencode.json if you added one for superpowers
```

Then follow the installation steps above.

## Usage

### Finding Skills

Use OpenCode's native `skill` tool to list all available skills:

```
use skill tool to list skills
```

### Loading a Skill

```
use skill tool to load rubypowers/brainstorming
```

### Personal Skills

Create your own skills in `~/.config/opencode/skills/`:

```bash
mkdir -p ~/.config/opencode/skills/my-skill
```

Create `~/.config/opencode/skills/my-skill/SKILL.md`:

```markdown
---
name: my-skill
description: Use when [condition] - [what it does]
---

# My Skill

[Your skill content here]
```

### Project Skills

Create project-specific skills in `.opencode/skills/` within your project.

**Skill Priority:** Project skills > Personal skills > RubyPowers skills

## Updating

RubyPowers updates automatically when you restart OpenCode. The plugin is re-installed from the git repository on each launch.

To pin a specific version, use a branch or tag (use `plugin` instead of `plugins` on OpenCode 1.x):

```json
{
  "plugins": ["rubypowers@git+https://github.com/lucianghinda/rubypowers.git#v8.0.3"]
}
```

## How It Works

One default export supports both OpenCode plugin APIs.

On OpenCode 2.x (`setup`):

1. **Registers every skill** in `skills/` with `ctx.skill.transform`.
2. **Injects bootstrap context** into the system prompt of each model request with the `context` session hook.
3. **Keeps the handoff across compaction** with the `compaction` session hook. It writes the handoff document and adds it to the compaction request, so the summary keeps it.

On OpenCode 1.x (`server`):

1. **Registers the skills directory** via the `config` hook.
2. **Injects bootstrap context** into the first user message via the `experimental.chat.messages.transform` hook.
3. **Writes and restores the handoff** via the `experimental.session.compacting` and `session.compacted` hooks.

### Tool Mapping

Skills written for Claude Code are automatically adapted for OpenCode:

- `TodoWrite` → `todowrite`
- `Task` with subagents → OpenCode's `@mention` system
- `Skill` tool → OpenCode's native `skill` tool
- File operations → Native OpenCode tools

## Troubleshooting

### Plugin not loading

1. Check OpenCode logs: `opencode run --print-logs "hello" 2>&1 | grep -i rubypowers`
2. Verify the plugin line in your `opencode.json` is correct. OpenCode 2.x reads `plugins`, 1.x reads `plugin`.
3. Make sure you're running OpenCode 2.x, or 1.18.29 or newer

### Skills not found

1. Use OpenCode's `skill` tool to list available skills
2. Check that the plugin is loading (see above)
3. Each skill needs a `SKILL.md` file with valid YAML frontmatter

### Bootstrap not appearing

1. Check that the plugin is loading (see above)
2. Restart OpenCode after config changes

## Getting Help

- Report issues: https://github.com/lucianghinda/rubypowers/issues
- Main documentation: https://github.com/lucianghinda/rubypowers
- OpenCode docs: https://opencode.ai/docs/
