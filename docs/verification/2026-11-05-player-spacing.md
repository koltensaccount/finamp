# Now Playing spacing and title readability

Title previously competed with two action buttons in one row and was forced to
one line. Give it the full available width, up to three wrapped lines, and a
full-title tooltip. Artist/action row stays below. Use existing theme typography,
20px side insets, and12px between metadata and transport controls. Remove the
large gap before bottom actions in landscape and cluster portrait controls.
Increase the controller's reserved content height to account for wrapped text.

Full Flutter suite94 passes. Visual/device verification and installed build
follow separately; this report does not certify overflow at every text scale.
No playback engine, queue, media source or acquisition behavior changed here.
MAM automation is held pending verification of official rules, per user request.
