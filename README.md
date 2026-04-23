[中文](README_CN.md) | English

# Mowen CLI

A command-line tool written in Zig for managing Markdown notes on the Mowen platform. Supports single-file management and batch uploads — **all modes support metadata tracking and subsequent editing**.

## Features

- ✅ **Single-file management**: Create, edit, set privacy
- ✅ **Batch upload**: Automatically scan and upload all .md files
- ✅ **Metadata tracking**: All upload methods save noteId for subsequent editing
- ✅ **Auto rate limiting**: 1 second/file to avoid triggering API limits
- ✅ **Tag management**: Add tags to notes
- ✅ **Flexible configuration**: Config file / environment variables / CLI arguments
- ✅ **Preview mode**: Dry-run mode without actual uploads
- ✅ **Zero dependencies**: Single executable binary
- ✅ **Cross-platform**: Windows/Linux/macOS

## Quick Start

### 1. Download

Download the executable for your platform from the [Releases](https://github.com/ohmycli/mowen-cli/releases) page.

Or build from source:

```bash
# Requires Zig 0.16.0
git clone https://github.com/ohmycli/mowen-cli.git
cd mowen-cli
zig build
```

The compiled executable is at `zig-out/bin/mowen-cli.exe` (Windows) or `zig-out/bin/mowen-cli` (Linux/macOS).

### 2. Configuration

Create a `config.json` file in the same directory as the executable:

```json
{
  "api_key": "your-api-key-here",
  "api_endpoint": "https://open.mowen.cn/api/open/api/v1/note/create",
  "timeout_ms": 30000,
  "default_tags": ["tech", "notes"],
  "auto_publish": false
}
```

**Configuration fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `api_key` | string | Yes | Mowen platform API key |
| `api_endpoint` | string | Yes | API endpoint URL |
| `timeout_ms` | number | Yes | Request timeout in milliseconds, range 1000-300000 |
| `default_tags` | array | No | Default tag list |
| `auto_publish` | boolean | No | Whether to auto-publish notes |

**Getting an API Key:**

1. Log in to the Mowen platform
2. Go to Personal Settings → API Management
3. Create a new API key
4. Copy the key to your config file

### 3. Usage

Mowen CLI provides two usage modes:

## Usage Modes

### Mode 1: Single-file Management (Recommended)

Ideal for daily note management, with support for subsequent editing and privacy settings.

#### Create a Note

```bash
# Create a new note
mowen-cli create README.md

# Create and auto-publish
mowen-cli create README.md --auto-publish

# Create with tags
mowen-cli create README.md --tags "tech,tutorial"

# Combined usage
mowen-cli create README.md --tags "blog,Zig" --auto-publish
```

After successful creation, the note ID is automatically saved to `.mowen/metadata.json` for subsequent editing.

#### Edit a Note

```bash
# Edit a previously created note (auto-finds noteId)
mowen-cli edit README.md

# Preview mode
mowen-cli edit README.md --dry-run
```

**Note**: Only notes created via the `create` command can be edited.

#### Set Privacy

```bash
# Set to private
mowen-cli set-privacy README.md --privacy private

# Set to public
mowen-cli set-privacy README.md --privacy public

# Set to rule-based visibility
mowen-cli set-privacy README.md --privacy rule
```

### Mode 2: Batch Upload

Ideal for importing a large number of files at once. **Now also supports saving metadata** for subsequent editing.

#### Basic Batch Upload

```bash
# Upload all .md files in the current directory
mowen-cli upload
```

Example output:
```
Found 5 markdown file(s)

[1/5] Uploading ./README.md... OK (ID: note_abc123)
[2/5] Uploading ./guide.md... OK (ID: note_def456)
[3/5] Uploading ./tutorial.md... FAILED (FileReadError)
[4/5] Uploading ./api.md... OK (ID: note_ghi789)
[5/5] Uploading ./faq.md... OK (ID: note_jkl012)

✓ Upload complete: 4 succeeded, 1 failed
  Metadata saved to .mowen/metadata.json
  You can now use 'edit' and 'set-privacy' commands on these files.
```

**New feature**: After batch upload, noteIds for all successfully uploaded files are automatically saved to `.mowen/metadata.json`. You can then use `edit` and `set-privacy` commands!

#### Preview Mode

```bash
# Only scan files, no actual upload
mowen-cli upload --dry-run
```

Example output:
```
Found 3 markdown file(s)

[DRY RUN MODE - No files will be uploaded]

  - ./README.md
  - ./guide.md
  - ./tutorial.md
```

#### Add Tags

```bash
# Add tags to uploaded notes
mowen-cli upload --tags "blog,tech sharing,Zig"
```

#### Auto-publish

```bash
# Auto-publish notes after upload
mowen-cli upload --auto-publish
```

#### Combined Usage

```bash
# Batch upload with auto-publish and custom tags
mowen-cli upload --auto-publish --tags "tech,notes"

# Use a temporary API Key
mowen-cli upload --api-key YOUR_API_KEY --tags "important"
```

### Mode Comparison

| Feature | Single-file (`create`/`edit`/`set-privacy`) | Batch upload (`upload`) |
|---------|----------------------------------------------|------------------------|
| **File count** | Single file | All .md files in current directory |
| **Metadata management** | ✅ Saved to `.mowen/metadata.json` | ✅ Saved to `.mowen/metadata.json` |
| **Subsequent editing** | ✅ Supports `edit` command | ✅ Supports `edit` command |
| **Privacy settings** | ✅ Supports `set-privacy` command | ✅ Supports `set-privacy` command |
| **Use case** | Daily note management | One-time batch import |
| **Recommendation** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

**Good news**: Both modes now support full metadata management! You can safely use batch upload and still edit and set privacy afterwards.

**Suggestions**:
- For daily single-file operations: Use `create`/`edit`/`set-privacy` commands
- For first-time bulk import: Use the `upload` command for quick batch uploading

## Configuration Priority

When the same setting is configured in multiple places, priority is as follows (highest to lowest):

1. **CLI arguments**: `--api-key`, `--auto-publish`, etc.
2. **Environment variables**: `MOWEN_API_KEY`, `MOWEN_API_ENDPOINT`
3. **Config file**: `config.json`
4. **Default values**

### Environment Variables

The following environment variables are supported:

```bash
# Windows PowerShell
$env:MOWEN_API_KEY="your-api-key"
$env:MOWEN_API_ENDPOINT="https://open.mowen.cn/api/open/api/v1/note/create"

# Linux/macOS
export MOWEN_API_KEY="your-api-key"
export MOWEN_API_ENDPOINT="https://open.mowen.cn/api/open/api/v1/note/create"
```

## CLI Reference

### Global Options

```bash
mowen-cli --help              # Show help information
mowen-cli --version           # Show version information
```

### create Command

Create a new note.

```bash
mowen-cli create <file> [options]

Options:
  --api-key <KEY>           Override configured API Key
  --tags <TAG1,TAG2>        Add tags (comma-separated)
  --auto-publish            Auto-publish the note
  --dry-run                 Preview mode, no actual upload

Examples:
  mowen-cli create README.md
  mowen-cli create guide.md --tags "tech,tutorial" --auto-publish
  mowen-cli create doc.md --dry-run
```

### edit Command

Edit a previously created note.

```bash
mowen-cli edit <file> [options]

Options:
  --api-key <KEY>           Override configured API Key
  --dry-run                 Preview mode, no actual upload

Examples:
  mowen-cli edit README.md
  mowen-cli edit guide.md --dry-run
```

### set-privacy Command

Set note privacy.

```bash
mowen-cli set-privacy <file> --privacy <public|private|rule> [options]

Options:
  --privacy <TYPE>          Privacy type: public, private, rule (rule-based visibility)
  --api-key <KEY>           Override configured API Key
  --dry-run                 Preview mode, no actual operation

Examples:
  mowen-cli set-privacy README.md --privacy private
  mowen-cli set-privacy guide.md --privacy public
```

### upload Command

Batch upload all .md files in the current directory.

```bash
mowen-cli upload [options]

Options:
  --api-key <KEY>           Override configured API Key
  --tags <TAG1,TAG2>        Add tags (comma-separated)
  --auto-publish            Auto-publish notes
  --dry-run                 Preview mode, no actual upload

Examples:
  mowen-cli upload
  mowen-cli upload --dry-run
  mowen-cli upload --tags "blog,tech" --auto-publish
  mowen-cli upload --api-key YOUR_KEY
```

## Supported Markdown Syntax

The following Markdown syntax is currently supported:

- ✅ Headings (H1-H6)
- ✅ Paragraphs
- ✅ Bold, italic
- ✅ Links
- ✅ Lists (ordered, unordered)
- ✅ Code blocks
- ✅ Blockquotes
- ✅ Horizontal rules

## FAQ

### Q: What should I do if upload fails?

A: Check the following:
1. Is the API Key correct?
2. Is the network connection working?
3. Is the API endpoint URL correct?
4. Is the Markdown file format valid?

### Q: What's the difference between `create` and `upload`?

A:
- **`create`**: Single-file operation, ideal for daily note management
- **`upload`**: Batch operation, ideal for importing a large number of files at once

**Both now support metadata saving**, and both can use `edit` and `set-privacy` commands afterwards!

### Q: Can I edit files after batch upload?

A: **Yes!** Starting from v0.1.0, the `upload` command automatically saves noteIds for all successfully uploaded files to `.mowen/metadata.json`. After batch upload, you can use:

```bash
# Edit a batch-uploaded file
mowen-cli edit README.md

# Set privacy
mowen-cli set-privacy README.md --privacy private
```

### Q: Why does the `edit` command say metadata not found?

A: Possible reasons:
1. The file was never uploaded via `create` or `upload`
2. The `.mowen/metadata.json` file was deleted or corrupted
3. The file path has changed (moved or renamed)

**Solutions**:
- For new files, use `mowen-cli create <file>` to create
- If the file was uploaded but metadata is lost, re-running `create` will overwrite the original note

### Q: Where is metadata stored?

A: Metadata is stored in the `.mowen/metadata.json` file in the current directory, recording file paths and their corresponding noteIds.

### Q: Can I upload files in subdirectories?

A:
- **`create`/`edit`/`set-privacy`**: Supports files at any path
- **`upload`**: Only scans the current directory, excluding subdirectories

### Q: Why is the upload speed so slow?

A: To avoid triggering API rate limits, the program automatically limits to 1 file per second. This is normal behavior.

### Q: How do I batch delete uploaded notes?

A: The tool currently only supports upload functionality. For deletion, please use the Mowen platform web interface.

### Q: Does the config file have to be in the same directory as the executable?

A: Yes. The program looks for `config.json` in the current working directory. It's recommended to place the executable and config file in the same directory and run the program from there.

### Q: What if a file fails during batch upload?

A: A single file failure won't affect other files from continuing to upload. After completion, the success and failure counts are displayed. You can check the failure reason and re-run.

## Development

### Requirements

- Zig 0.16.0 or higher

### Build

```bash
# Development build
zig build

# Release build (optimized)
zig build -Doptimize=ReleaseFast

# Run tests
zig build test
```

### Project Structure

```
mowen-cli/
├── src/
│   ├── main.zig           # Main entry point (CLI command handling)
│   ├── config.zig         # Configuration management (file/env/CLI)
│   ├── scanner.zig        # File scanning and reading
│   ├── parser.zig         # Markdown lexing and parsing
│   ├── converter.zig      # Markdown → NoteAtom conversion
│   ├── note_atom.zig      # Mowen note format definition and JSON serialization
│   ├── uploader.zig       # API calls (create/edit/set-privacy)
│   └── metadata.zig       # Metadata management (noteId tracking)
├── tests/
│   ├── config_test.zig    # Configuration module tests
│   ├── parser_test.zig    # Parser tests
│   └── scanner_test.zig   # Scanner tests
├── build.zig              # Build script
├── config.example.json    # Example config file
└── README.md              # This document
```

## Contributing

Issues and Pull Requests are welcome!

## License

MIT License

## Changelog

### v0.1.0 (2026-04-22)

**Core Features**
- ✅ Single-file management: `create`, `edit`, `set-privacy` commands
- ✅ Batch upload: `upload` command, auto-scans current directory
- ✅ **Metadata management**: `upload` command now also saves noteId for subsequent editing!
- ✅ Markdown parsing: Supports headings, paragraphs, bold, links, blockquotes, code blocks, horizontal rules
- ✅ Configuration management: Supports config file, environment variables, CLI arguments
- ✅ Rate limiting: Auto 1 second/request to avoid triggering API limits
- ✅ Preview mode: Dry-run support

**Testing**
- ✅ 27 unit tests, all passing
- ✅ Configuration management tests
- ✅ Markdown parser tests
- ✅ File scanner tests

**Key Improvements**
- 🎉 Batch upload now supports metadata saving for subsequent editing and privacy settings

---

**Note**: This tool is for learning and personal use only. Please comply with the Mowen platform's terms of service and API limits.
