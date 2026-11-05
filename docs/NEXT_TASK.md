# Next task — establish truthful cross-platform acceptance evidence

Suggested follow-up, not authorization for server mutation or acquisition.
Use a separate branch/worktree and recheck current state before choosing scope.

1. Reproduce album cover/title navigation on Home, Library, artist discography,
   and search in the existing native and PWA clients while a queue is playing.
   Assert correct details route and unchanged queue/order/current item/position
   (allow normal elapsed playback). Test Play/Shuffle separately. Fix only failures.
2. Capture equivalent Home, Search, Library, album, artist, Books, Settings, and
   Now Playing views on iPhone, iPad, macOS, and the PWA. Agree shared token values
   from the current native UI; map CSS/Flutter values and fix measured divergence.
3. Verify account/bootstrap with two real clients, then separately test favorites,
   preferences, progress conflicts, presence staleness, remote controls, and queue
   handoff. Mark missing mechanisms as missing, not covered by pairing tests.
4. Before extending acquisition, finish auditing metadata-provider test I/O and prove media safety
   on fixtures: provider outage, ambiguous match, collision, interruption, rollback,
   and decoded-audio integrity. Version the existing server-only account source
   through a reviewed, credential-free change; preserve the current deployed system.

For each selected item use [quality gates](agents/QUALITY_GATES.md) and create
an evidence report. Do not broaden a navigation fix into a server rewrite.
Music Assistant/Home Assistant evaluation is optional research, not a dependency
or a substitute for testing KB clients. The prior acquisition-dispatcher task is
historical, no longer an unconditional next step.
