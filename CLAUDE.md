# AeroGesture

macOS daemon that translates trackpad swipe gestures into workspace-switching commands for [AeroSpace](https://github.com/nikitabobko/AeroSpace) tiling window manager.

## Stack

- **Language**: Swift 5.9 | **Platform**: macOS 13+ (Ventura)
- **Package Manager**: Swift Package Manager (SPM)
- **Dependencies**: TOMLKit (0.6.0+) for TOML config parsing
- **Frameworks**: AppKit, ApplicationServices (accessibility/gesture APIs)
- **Deployment**: launchd daemon (`com.aerogesture.plist`)

## Architecture

Single-target executable with flat source layout in `Sources/aerogesture/`:

| File | Responsibility |
|------|---------------|
| `main.swift` | Entry point, CLI args, signal handling, PID file |
| `GestureDetector.swift` | Trackpad gesture detection (Direction, GestureState, SwipeAxis enums + GestureDetector class) |
| `AeroSpaceSocket.swift` | IPC with AeroSpace via Unix socket (ClientRequest/ServerAnswer, SwipeError) |
| `Config.swift` | TOML config loading (GestureConfig, WorkspaceConfig, Config structs via Codable) |
| `AccessibilityCheck.swift` | macOS accessibility permission verification |

Config lives at `~/.config/aerogesture/config.toml` (see `config.toml.example` for schema).

## Build & Run

```bash
swift build                          # Debug build
swift build -c release               # Release build
swift run aerogesture                # Build and run
swift run aerogesture --config path  # Custom config path
swift package resolve                # Resolve deps
swift package clean                  # Clean build artifacts
```

## Install & Service

```bash
cp -f .build/release/aerogesture /usr/local/bin/aerogesture
cp -f com.aerogesture.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.aerogesture.plist
kill -HUP $(cat /tmp/aerogesture.pid)   # Reload config (SIGHUP)
```

## Logs

```bash
tail -f /tmp/aerogesture.stdout.log
tail -f /tmp/aerogesture.stderr.log
```

## Verification

After any code change, always run:
```bash
swift build
```
No test suite or linter is configured yet. Compilation is the quality gate.

---

## Rules

### MCP Serena (MANDATORY)

When Serena MCP tools are available in the session, you MUST use them as your primary interface for code navigation and editing:

- **Always** use `get_symbols_overview` and `find_symbol` for understanding code structure before reading full files
- **Always** use `find_symbol` with `include_body=True` to read specific symbol implementations instead of reading entire files
- **Always** use `replace_symbol_body`, `insert_before_symbol`, `insert_after_symbol` for code modifications instead of raw file edits
- **Always** use `find_referencing_symbols` to understand symbol usage and impact before refactoring
- **Always** use `rename_symbol` for renaming instead of manual find-and-replace
- **Always** check and read Serena project memories (`list_memories`, `read_memory`) for relevant context before starting work
- **Never** read an entire file when Serena symbolic tools can give you just the information you need
- Only fall back to raw file reads/edits when operating on non-code files (configs, markdown, plists) or when Serena tools are unavailable

### Shell Commands

- Always use non-interactive flags: `cp -f`, `mv -f`, `rm -f` -- never let commands hang on prompts
- Do not use interactive editors or commands requiring TTY input

### Code Changes

- Follow existing Swift conventions: camelCase for vars/functions, PascalCase for types
- Use enums for fixed sets of values, classes for stateful components, structs with Codable for config
- Use `// MARK: -` section comments consistent with existing style in `main.swift`
- Do not add SwiftLint, formatters, or CI config unless explicitly asked

### Git & Workflow

- Work is NOT complete until `git push` succeeds
- Always `git pull --rebase` before pushing
- Use `swift build` as the pre-commit quality gate

### Progressive Documentation

For task-specific context beyond this file, consult:
- `config.toml.example` -- configuration schema and defaults
- `com.aerogesture.plist` -- launchd service definition
- `README.md` -- user-facing documentation
- `.serena/` -- Serena project memories for deeper architecture context
