# Agent guidance research and design rationale

Official sources read **before repository edits**, 2026-11-05. These are design
inputs, not claims that instructions can enforce model behavior perfectly.

| Source | Applicable finding | Repository choice |
| --- | --- | --- |
| [OpenAI: AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md) | Codex discovers root-to-working-directory guidance; override files can shadow AGENTS; default combined limit is 32 KiB. | Lean root; no overrides; explicit scoped links so root-launched tools can read them. |
| [OpenAI: skills](https://learn.chatgpt.com/docs/build-skills) | Skills expose a name/description first and load workflow content on demand. | Avoid a giant always-loaded prompt. Plain linked guides suffice here; no speculative custom skill or autonomous agent machinery. |
| [OpenAI: reviewing rules](https://developers.openai.com/blog/custom-code-review-rules-for-codex) | Scope important compatibility constraints; use CI for deterministic checks. | Preserve identity/playback invariants in scope guides; check broken links, adapter drift and evidence presence mechanically. |
| [Google Antigravity: rules](https://antigravity.google/docs/rules) | AGENTS/GEMINI are recognized without frontmatter; rules are cumulative. Nested directories below workspace are not automatically loaded. Rules-directory files need valid trigger frontmatter. | Root GEMINI adapter and explicit scope routing. No unnecessary rules directory or unsupported trigger spelling. |
| [Gemini CLI: project context](https://geminicli.com/docs/cli/gemini-md/) | GEMINI.md discovery is hierarchical; memory display/reload lets users inspect loaded context. | Short GEMINI pointer, with explicit read instruction rather than relying on cross-tool include syntax. |
| [Claude Code: memory](https://code.claude.com/docs/en/memory) | Keep rules concise, concrete and consistent; CLAUDE supports file imports. Instruction text is context, not an enforcement mechanism. | CLAUDE imports AGENTS; avoid duplicated product rules or assumptions about AGENTS support on older clients. |
| [GitHub Copilot: custom instructions](https://docs.github.com/en/copilot/concepts/prompting-and-context/custom-instructions) and [support matrix](https://docs.github.com/en/copilot/reference/custom-instructions-support) | Repository-wide .github/copilot-instructions.md is supported across more surfaces; AGENTS support varies. | Tiny repository adapter to the same contract; no custom agent definition or redundant policy set. |

Synthesis (our design judgment): stable intent, clear scope, a discoverable source
map and observable acceptance tests are more useful than repeating the same
aspirational feature list in every assistant's prompt. Native discovery rules
still differ; repository precedence describes document ownership and does not
pretend to override any assistant's system/user instruction hierarchy.

## Optional device-ecosystem integrations

[Music Assistant installation](https://www.music-assistant.io/installation/)
documents standalone deployment as well as Home Assistant installation.
Its [Jellyfin provider](https://www.music-assistant.io/music-providers/jellyfin/)
connects an existing music library. The [Home Assistant integration](https://www.home-assistant.io/integrations/music_assistant/)
exposes Music Assistant players as controllable media-player entities.

Inference: this is a useful optional interoperability candidate, not evidence
that Finamp/KB Music clients can become remote-controlled players or transfer
their queues. Before adopting it, record supported client/player transports,
authentication, queue/position semantics, foreground/background behavior, network
boundaries, offline fallback, failure recovery, and a two-device prototype in an
architecture decision. Do not install it or make onboarding depend on it here.

## Discovery audit and limits

- Both existing Git worktrees had only the old root AGENTS.md; no checked-in
  GEMINI/CLAUDE/Copilot or Antigravity workspace rules were found. A separate
  device source snapshot had no Git metadata and was left alone.
- The installed Antigravity built-in rules documentation independently describes
  directory-based AGENTS/GEMINI discovery. No global assistant settings changed.
- New root adapters, scoped links and generated web snapshot are structurally
  checked. This is not an end-to-end live model adherence test.
- Codex CLI is installed (0.162.1). Gemini CLI, Claude CLI and Antigravity CLI
  commands were unavailable on PATH during audit. Interactive assistant discovery
  is **unverified**, not passed. To smoke-test in the actual workspace: start a
  fresh session and ask for loaded instruction paths, product invariants and
  applicable scope before any edits. In Gemini CLI inspect `/memory show` after
  `/memory reload`; in Claude inspect `/memory`. In Antigravity inspect active
  workspace rules. Copilot support depends on the selected client/surface.
- Test discovery from repository root and from lib/backend, plus the existing
  PWA workspace. Confirm album taps, offline preservation, sync distinctions,
  no production media writes, and blocked-check reporting. A harmless scenario
  should not trigger unrelated acquisition or deployment. Capture actual results
  before promoting the discovery status to verified.
