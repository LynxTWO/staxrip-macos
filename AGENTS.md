# StaxRip Mac development

This is an independent native Mac prototype. Keep claims about Windows StaxRip compatibility explicit and tested. Do not copy Windows application code or assets without checking their license.

## Workflow

- Keep main as the tested baseline. Work on focused branches and open pull requests with behavior, checks and remaining limitations.
- Preserve local user work. Do not merge or publish releases without explicit authorization.
- Use SwiftUI for the interface and an AppKit AVPlayerView bridge for preview. SwiftUI VideoPlayer crashed on the original development runtime.
- Use system frameworks first. Do not silently download or execute third-party encoding tools.
- Clearly distinguish editable future encoder configurations from real native preset exports. Never silently ignore a setting when executing a queue job.
- Never overwrite source media or existing encoded outputs. Publish completed exports without replacing existing files; clean up only temporary files owned by the current operation.
- Saved session files are untrusted data. Validate format version, bounds, paths, IDs and configuration values before applying them. Do not execute a session as code or launch processing when a session opens.
- Keep source paths and media private. Test using generated synthetic fixtures and do not commit local media, personal sessions, binaries, absolute user paths or credentials.
- Run `swift test` and a focused native UI check for relevant changes. State unsupported formats and untested platforms honestly.
- Use `./build.command` for the local development app. Do not claim its ad-hoc signature is notarization.
