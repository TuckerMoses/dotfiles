# Packaging agent skills with Nix for several harnesses

Research date 2026-11-27. "Read" means I fetched the primary page or file; "snippet" means I only saw a search-result summary.

## Recommendation

Keep claude-materia as a plain git repo and marketplace, and keep it the only place a skill is written (option b). Add one thing on the Nix side: a Home Manager entry in the base layer that links the repo into `~/.claude/skills/` as a **skills-directory plugin**. On the Mac where you edit, the link points at your checkout through `mkOutOfStoreSymlink`, so edits are live. Every other machine gets a flake input pinned in `flake.lock`. Don't build a per-harness rendering layer yet (options a and c). Your skills are written for Claude Code, aiOS v0.1 only targets Claude Code, and session-F hasn't decided between importing and copying. A renderer would turn one of those undecided answers into code. When a second harness actually gets used, add a `skills` output to the materia flake and link it into `~/.agents/skills`, the one directory nearly every other harness now reads.

## Gotchas first

1. **Your skills are not portable yet, whatever the packaging.** The materia skills hard-code `~/.claude/plugins/data/claude-materia-claude-materia/` (park-session, adversarial-review) and `~/.claude/<skill>.local.md`. Several of them launch `claude` in tmux or dispatch Claude subagents from `agents/`. Another harness would load these files and then fail at run time. (Read: `skills/*/SKILL.md`, `CLAUDE.md` in the repo.)
2. **Today's editing loop is slower than the docs suggest.** Claude Code's docs say relative-path plugins in a marketplace added from a local directory "load in place", so edits apply with no version bump. On this Mac, `known_marketplaces.json` records claude-materia as a `directory` source, yet `claude plugin list --json` reports both plugins loading from `~/.claude/plugins/cache/claude-materia/.../0.16.0` and `.../2.0.0` (Claude Code 2.1.332). The repo's own CLAUDE.md requires a version bump plus `claude plugin update`. My guess is that the install predates the switch to a directory source, so the copy is stale. I haven't verified that. Reinstalling might give you live edits without any Nix work.
3. **Work machines may block the skills-directory route.** Any managed `strictKnownMarketplaces` allowlist that lacks a `{ "source": "skills-dir" }` entry silently stops `~/.claude/skills/<x>` plugins from loading. So does `strictPluginOnlyCustomization`. Plain `SKILL.md` folders still load in either case (read: code.claude.com plugins/org, plugins/loading).
4. **Switching to a skills-directory plugin changes the plugin's id.** `claude-materia@claude-materia` becomes `claude-materia@skills-dir`. The hard-coded data path still works because it's an ordinary writable directory. `${CLAUDE_PLUGIN_DATA}` would point somewhere new, but the skills don't use it.
5. **Two managers for one directory.** The `skills` CLI already owns `~/.agents/skills/{find-skills,herdr}` and links them into `~/.claude/skills/`. Home Manager can share those directories if each entry name has one owner.

## Comparison

| | (a) Each skill a derivation, rendered per harness | (b) Plain git marketplace; Nix pins and links it | (c) Marketplace repo is also a flake with per-harness outputs | (d) `skills` CLI outside Nix |
|---|---|---|---|---|
| Editing loop | Edit, rebuild, switch. Live only if you add an out-of-store dev mode | Live through `mkOutOfStoreSymlink` to the checkout (skills dir is watched; plugin parts need `/reload-plugins`) | Same as (b) for Claude; rebuild for the other outputs | Edit the source, then `npx skills update` (copies) |
| Second machine | `nix flake update` plus switch | `nix flake update claude-materia` plus switch, or `claude plugin update` if you keep the marketplace install | Same as (a) | `npx skills experimental_install` from the lock file; per machine, imperative |
| Read-only store breaks | Nothing for skills (Claude, Codex documented to follow symlinks; others unverified) | Nothing; state goes to `~/.claude/plugins/data` | Same | N/A: mutable copies |
| Upkeep | High: a layout function per harness that tracks six moving specs | Low: one HM entry, one flake input | Medium: one flake, and outputs grow only as harnesses get used | Low, but outside the lock file and HM |
| Fits work-layer rule | Yes | Yes | Yes | Weakly: separate state per machine |

(a) and (c) aren't wrong, just early: only `SKILL.md` folders travel between harnesses, while agents, commands and hooks differ in each. (c) is what (b) grows into without a rewrite. For (a), Kyure-A/agent-skills-nix and rytswd/skills.nix already exist.

## Evidence

### Formats and discovery paths

The Agent Skills spec (agentskills.io/specification, read) requires `name` (64 characters at most, lowercase and hyphens, matching the directory name) and `description` (1,024 at most). Optional fields are `license`, `compatibility`, `metadata` and `allowed-tools` (experimental). Claude Code adds `when_to_use`, `argument-hint`, `disable-model-invocation`, `context: fork`, `agent`, `hooks`, `paths`, `model` and others. It ignores fields it doesn't know, but uploading to claude.ai rejects them (code.claude.com/docs/en/skills, read).

| Harness | Global skill dirs | Project dirs | Symlinks / read-only | Source |
|---|---|---|---|---|
| Claude Code | `~/.claude/skills/` (+ plugins, managed dir, claude.ai sync) | `.claude/skills/`, up to repo root | Symlinked skill dirs supported. A folder with `.claude-plugin/plugin.json` loads as `<name>@skills-dir` and is "never copied" | skills, plugins/loading (read) |
| Codex | `~/.agents/skills`, `/etc/codex/skills` | `.agents/skills` up to repo root | "follows the symlink target" | learn.chatgpt.com/docs/build-skills (read; developers.openai.com redirects there) |
| pi | `~/.pi/agent/skills/`, `~/.agents/skills/`, `skills` settings array, `--skill` | `.pi/skills/`, `.agents/skills/` | Not found | Search snippets of pi docs v1.5.2 (pi.dev pages redirected in a loop; **snippet only**) |
| Gemini CLI | `~/.gemini/skills/`, `~/.agents/skills/` (wins over `.gemini`) | `.gemini/skills/`, `.agents/skills/` | Not stated; `/skills link` exists | geminicli.com/docs/cli/skills (read, updated 2026-04-30) |
| OpenCode | `~/.config/opencode/skills`, `~/.claude/skills`, `~/.agents/skills` | `.opencode/`, `.claude/`, `.agents/skills` | Not stated | opencode.ai/docs/skills (read) |
| Cursor | `~/.cursor/skills/`, `~/.agents/skills/`, `~/.claude/skills/`, `~/.codex/skills/` | `.cursor/`, `.agents/`, `.claude/`, `.codex/skills` | Not stated; CLI coverage not stated | cursor.com/docs/context/skills (read) |
| `skills` CLI | Per-agent table; project canonical `.agents/skills` | `-g` for global | Lock file `skills-lock.json` v2 with `computedHash`; whether it symlinks or copies isn't on the README | vercel-labs/skills README and docs/agents.md (read) |

Two consequences. First, `~/.agents/skills` reaches Codex, pi, Gemini, OpenCode and Cursor, but not Claude Code. Second, OpenCode and Cursor read *both* `~/.claude/skills` and `~/.agents/skills`, so putting the same skill in both places may show it twice there. I didn't verify how they resolve duplicates.

**Claude Code plugins.** `.claude-plugin/marketplace.json` holds `name`, `owner` and `plugins[]`, each entry with `name` and `source`. The source can be a relative path, `github`, `git-subdir`, `url`, `archive`, `npm` or `command`. Installed state lives in `~/.claude/plugins/` (`known_marketplaces.json`, `installed_plugins.json`, `cache/<mkt>/<plugin>/<version>/`, `data/<id>/`), all of it written by Claude Code. Updates arrive only when the computed version changes, and a pinned `version` in `plugin.json` holds users on the cached copy. Auto-update is off for third-party marketplaces by default. `CLAUDE_CODE_PLUGIN_SEED_DIR` takes a read-only, pre-built plugins tree ("Claude Code never writes to the seed and forces autoUpdate off"), which is the Nix-friendliest official mechanism. `CLAUDE_CODE_PLUGIN_DIRS` loads plugin folders for every session as `@inline`. (Read: plugin-marketplaces, plugins/host-marketplace.md, plugins/org.md, plugins/loading.md.)

**Codex plugins.** A root `plugin.json` is the new portable layout and `.codex-plugin/plugin.json` is the compatibility layout. The docs say "OpenAI also accepts legacy and Claude-compatible manifests", and `$REPO_ROOT/.claude-plugin/marketplace.json` is listed as a "legacy-compatible" marketplace path. `codex plugin marketplace add owner/repo@ref` exists, and the cache is `~/.codex/plugins/cache/<mkt>/<plugin>/<version>/` (developers.openai.com/plugins/build/plugins.md, read; undated). So Codex may accept claude-materia as it stands. **Untested.**

### What Nix and Home Manager provide (module sources read on master today)

- `programs.claude-code` (`modules/programs/claude-code/options.nix`, `default.nix`): `package`, `configDir`, `settings`, `mutableSettings`, `context` (CLAUDE.md), `mcpServers`, `enableMcpIntegration`, `lspServers`, `plugins` (attrsOf package-or-path), `marketplaces`, `skills` (attrset or a whole directory), `agents`/`agentsDir`, `commands`/`commandsDir`, `hooks`/`hooksDir`, `rules`/`rulesDir`, `outputStyles`. `plugins` links each one whole into `<configDir>/skills/<name>` as a skills-directory plugin (needs Claude Code 2.1.157 or later). It falls back to a `--plugin-dir` wrapper on older versions. `mutableSettings = true` turns `settings.json` into a real file, mode 600, that activation jq-merges with declared keys winning.
- `programs.codex` (`codex/options.nix`): `settings`, `mutableSettings`, `profiles`, `context` (AGENTS.md), `contextOverride`, `hooks`, `plugins`, `marketplaces`, `skills` (into `CODEX_HOME/skills`, which Codex's own docs don't list as a discovery path; **unverified** that Codex still reads it), `rules`.
- `programs.pi-coding-agent` (`pi-coding-agent.nix`): `settings`, `mutableSettings`, `keybindings`, `models`, `context`, `appendSystem`, `extraPackages`. It has **no skills option**.
- `programs.opencode` (`opencode.nix`): `settings`, `commands`, `agents`, `context`, `themes`, `tools`, `skills` (attrset or directory), `mutableSettings`.
- `programs.cursor` is the editor (VS Code module), not the agent CLI. I found no Gemini CLI module under `modules/programs/`.
- nixpkgs `pkgs/by-name` has `claude-code`, `codex`, `gemini-cli`, `opencode`, `pi-coding-agent` and `cursor-cli` (directory listing read; versions not checked).
- Community: **Kyure-A/agent-skills-nix** (README read) offers `programs.agent-skills.{sources.<n>.input/subdir, skills.explicit, skills.enableAll, targets.<agent>.enable}`. Sources are flake inputs with `flake = false`; global targets use a symlink tree. **rytswd/skills.nix** (README read) offers `programs.agent-skills.{skills, localSkills}` with per-agent toggles; `localSkills` symlinks to the live path. Neither handles Claude plugins or marketplaces.

### Known problems with the Nix store

- **settings.json deletion.** HM issue #9831 (read; opened 2026-08-20, still open) reports that Claude Code unlinks a store-symlinked `~/.claude/settings.json` within seconds of `home-manager switch`. It proposes copying a real 644 file during activation. Upstream anthropics/claude-code#88307 (read) was closed 2026-11-15 as "Fixed in Claude Code 2.1.247". The changelog line it cites describes Bash-sandbox cleanup rather than the background worker the reporter blamed, so the fix may be partial. Your settings.json is stowed today and points at a writable file in the aios repo, so this affects you only if you move it into HM. If you do, use `mutableSettings = true`.
- **Plugin and marketplace state is mutable by design.** `known_marketplaces.json`, `installed_plugins.json`, `cache/` and `data/` are all rewritten by Claude Code. `enabledPlugins` lives in settings.json. Don't put any of it in the store. The seed directory and the skills directory are the supported read-only paths.
- **Per-machine state.** Login tokens, `~/.claude.json`, sessions, memory and `plugins/data` stay outside Nix (Codex and pi likely the same; not verified).
- **The escape hatch.** `config.lib.file.mkOutOfStoreSymlink` links `$HOME` to a mutable path instead of the store. It's the standard HM pattern and I didn't re-read the manual today. It needs an absolute path, and the target has to exist on that machine.

## What to do first

1. Check whether the stale-cache theory in gotcha 2 is true: run `claude plugin uninstall`/`install` against the directory marketplace and see whether edits load in place. If they do, the editing loop on the Mac is fixed with no Nix at all.
2. Add `claude-materia` as a `flake = false` input in the dotfiles flake. In the HM base, add `home.file.".claude/skills/claude-materia".source = <checkout via mkOutOfStoreSymlink, or the input>`, and the same for `plugins/vault`. Choose between them with a per-host flag. Don't adopt `programs.claude-code.settings`, because aiOS owns settings.json for now.
3. Add a `validate.sh` check: `claude plugin list --json` must show `claude-materia@skills-dir` loading from the expected path.

## Defer until aiOS settles

- Per-harness outputs and `~/.agents/skills` (wait for session-F's import-or-copy answer and the harness experiment).
- Rewriting skills to drop the hard-coded `~/.claude` paths in favour of a harness-neutral data directory.
- Commands, agents and hooks for other harnesses. None of them share a format.
- Codex consuming the Claude marketplace directly.

## Questions only you can answer

1. Should claude-materia go on work machines at all (base layer), or only in the personal layer? And do work machines run Claude Code under managed settings that block skills-directory plugins?
2. Once Nix pins it, does the public `TuckerMoses/claude-materia` marketplace install still matter, for other people or for machines without Nix?
3. Which harness is second, and when? That decides whether `~/.agents/skills` is worth wiring now.
4. Should a skill's harness-specific parts live in the skill itself (frontmatter, `compatibility`) or in an adapter? That's the same question session-F asks about preferences.

## Sources

All read unless marked. agentskills.io/specification; code.claude.com/docs/en/{skills, plugin-marketplaces, plugins/host-marketplace, plugins/org, plugins/loading}; learn.chatgpt.com/docs/build-skills; developers.openai.com/plugins/build/plugins.md; geminicli.com/docs/cli/skills; opencode.ai/docs/skills; cursor.com/docs/context/skills; unpkg.com/@earendil-works/pi-coding-agent@1.5.2/docs/skills.md (snippet only); github.com/vercel-labs/skills (+ docs/agents.md); github.com/nix-community/home-manager/tree/master/modules/programs; home-manager issue #9831; anthropics/claude-code issue #88307; github.com/Kyure-A/agent-skills-nix; github.com/rytswd/skills.nix; nixpkgs `pkgs/by-name` via the GitHub API. Local files I read without changing them: the claude-materia manifests, CLAUDE.md and skills; `~/.claude/plugins/*.json`; `claude plugin list --json`; `aios-plan.md` (session-F), `capture-to-week.md` (F), `requirements-input-2026-11-24.md` section 9. I didn't use context7, because only its authenticate tool was available this session.
