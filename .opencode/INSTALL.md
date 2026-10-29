# Installing RubyPowers for OpenCode

## Prerequisites

- [OpenCode.ai](https://opencode.ai) installed

## Installation

For users upgrading from a pre-8.0.0 install, replace the old package entry
`superpowers-ruby@git+https://github.com/lucianghinda/superpowers-ruby.git` in
`opencode.json` with
`rubypowers@git+https://github.com/lucianghinda/rubypowers.git`. Remove any old
symlinks or clone as described in the migration section, then follow these
install instructions.

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

Restart OpenCode. That's it — the plugin auto-installs and registers all skills.

Verify by asking: "Tell me about your RubyPowers"

## Migrating from the old symlink-based install

If you previously installed superpowers-ruby using `git clone` and symlinks,
remove the old setup. This also applies if you now have a legacy RubyPowers
symlink install; remove both names if both are present:

```bash
# Remove old symlinks
rm -f ~/.config/opencode/plugins/superpowers.js
rm -f ~/.config/opencode/plugins/rubypowers.js
rm -rf ~/.config/opencode/skills/superpowers-ruby
rm -rf ~/.config/opencode/skills/rubypowers

# Optionally remove the cloned repo
rm -rf ~/.config/opencode/superpowers-ruby
rm -rf ~/.config/opencode/rubypowers

# Remove an old skills.paths entry from opencode.json if you added one
```

Then follow the installation steps above.

## Usage

Use OpenCode's native `skill` tool:

```
use skill tool to list skills
use skill tool to load rubypowers/brainstorming
```

## Updating

RubyPowers updates automatically when you restart OpenCode.

To pin a specific version (use `plugin` instead of `plugins` on OpenCode 1.x):

```json
{
  "plugins": ["rubypowers@git+https://github.com/lucianghinda/rubypowers.git#v8.0.1"]
}
```

## Troubleshooting

### Plugin not loading

1. Check logs: `opencode run --print-logs "hello" 2>&1 | grep -i rubypowers`
2. Verify the plugin line in your `opencode.json`. OpenCode 2.x reads `plugins`, 1.x reads `plugin`.
3. Make sure you're running OpenCode 2.x, or 1.18.29 or newer

### Skills not found

1. Use `skill` tool to list what's discovered
2. Check that the plugin is loading (see above)

### Tool mapping

When skills reference Claude Code tools:
- `TodoWrite` → `todowrite`
- `Task` with subagents → `@mention` syntax
- `Skill` tool → OpenCode's native `skill` tool
- File operations → your native tools

## Getting Help

- Report issues: https://github.com/lucianghinda/rubypowers/issues
- Full documentation: https://github.com/lucianghinda/rubypowers/blob/main/docs/README.opencode.md
