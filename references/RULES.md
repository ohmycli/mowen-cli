# mowen-cli-v2 Rules & Architecture

## Red Lines

- Never commit config.json or any file containing API keys
- Never use `std.debug.print("[DEBUG]...")` in production code — use `log.*` functions
- Never break the Api vtable interface contract
- All commands must go through App context, never access config/io directly from main
- Keep main.zig under 100 lines — command logic belongs in commands/

## Verification Commands

```bash
zig build                          # Must compile cleanly
zig build test                     # All tests must pass
zig build run -- --version         # Should print version
zig build run -- --help            # Should print help
```

## Architecture

```
main.zig (slim: arg parse + table dispatch)
  └─> App (allocator, io, config, api, log)
        ├─> commands/create.zig
        ├─> commands/edit.zig
        ├─> commands/set_privacy.zig
        └─> commands/upload.zig
              └─> core/api.zig (vtable interface)
                    └─> infra/http_api.zig (implementation)
```

### Module Dependency Flow

```
main.zig → app.zig → config.zig, core/api.zig, log.zig
commands/* → app.zig, scanner.zig, converter.zig, metadata.zig, core/types.zig
converter.zig → parser.zig, core/types.zig
parser.zig → core/types.zig (via build.zig "note_atom" import)
infra/http_api.zig → core/api.zig, core/types.zig, log.zig
```

## Doc Index

| File | Purpose |
|------|---------|
| README.md | User-facing documentation |
| references/RULES.md | This file — red lines, architecture, verification |
| src/main.zig | Entry point, arg parsing, command dispatch |
| src/app.zig | App context struct |
| src/core/types.zig | NoteAtom, NoteRequest data types |
| src/core/api.zig | Api vtable interface |
| src/infra/http_api.zig | HTTP implementation of Api |
| src/commands/*.zig | Command implementations |
| src/parser.zig | Markdown tokenizer |
| src/converter.zig | Markdown → NoteAtom |
| src/config.zig | Config loading (file/env/cli) |
| src/metadata.zig | Note metadata persistence |
| src/scanner.zig | File scanner |
| src/log.zig | Logging wrapper |
| src/trace.zig | Trace context |
