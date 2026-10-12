# Paloma Morse — native clients

Read `docs/native-clients/ARCHITECTURE.txt` and the brief for your assigned branch.
The released baseline is v0.4.20. `main` continues to build the existing client.

- `feature/macos-swiftui`: Claude owns visual macOS work under `apps/macos/`.
  Start with `docs/native-clients/CLAUDE-MACOS.txt`.
- `feature/desktop-qt`: reserved for Windows/Linux Qt UI.
  Start with `docs/native-clients/CLAUDE-QT.txt` only when explicitly assigned.
- `refactor/shared-audio-core`: Codex owns shared core extraction, adapters and CI.
  Read `docs/native-clients/CORE-INTEGRATION.txt`.

Use the assigned worktree. Do not switch other worktrees or rewrite another
branch. Never include unrelated local files or secrets in commits. Do not push,
merge to main, tag or publish a release without the user's instruction.

The C++ implementation in `ui/native/` is currently authoritative. `core/audio/`
is a reserved destination until the extraction is integrated. Do not copy/fork
DSP code into UI targets. The production sound is clean only. Use the protocol
and UI-service contract in `shared/contracts/`.

Preserve the released `ui/`, `server/`, signing configuration and release workflow
while working on visual tasks. Report required shared changes as dependencies
for the core branch. Do not use Electron, Chromium, WebView, Node.js or browser
audio inside new native clients.

Use real platform components and accessibility. Preview data belongs in preview
or test support; do not present simulated engine/key/network status as live.
