# Next task — close audited workflow blockers

Use the [shared workflow contracts](WORKFLOWS.md), not either client's existing
UI as an unquestioned template. Choose the simplest effective outcome and align
both clients. The matrix records the pre-fix audit baseline; tested corrections
are in [verification](verification/2026-11-05-shared-workflows.md).

1. Complete safe build/release and real iPhone checks for the staged playback
   fixes: natural track-end, repeat, queue selection, timer cancellation,
   Previous/Play-Pause/Next, lock screen, headset and background interruptions.
   Source fixes are not an updated installed app or deployed image.
2. Enforce account identity/authorization at all PWA proxy boundaries. Remove
   unauthenticated service/master-token fallback; prove account isolation and
   revoke behavior with fixtures before deployment. Coordinate existing sessions
   so enforcement does not silently break normal sign-in or media streams.
3. Replace the PWA placeholder reader with actual selected EPUB content and
   truthful progress/format-continuation behavior. Until real alignment exists,
   do not advertise paired sync. Verify against known distinct book fixtures.
4. Address persistent queue/favorites, honest requests/metadata and device handoff
   using the contract matrix. Do not infer handoff from registration/presence.
5. Run matched screen comparisons after these functional blockers. Record shared
   design-token decisions and intentional platform adaptations; avoid duplicating
   every advanced settings page without a user task it serves.

This proposed order does not authorize broad production media writes,
acquisition, deletion, migrations, credential rotation or use of the inherited
Aubrey deployment scripts. Music Assistant/Home Assistant remain optional,
research-backed candidates rather than required dependencies.
