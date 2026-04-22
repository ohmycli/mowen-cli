# Mowen CLI Implementation - Steering Document

## Overview

This steering document outlines the implementation plan for mowen-cli, a Zig-based command-line tool that uploads Markdown files from the current directory to the Mowen platform.

## Goals

1. **Primary Goal**: Create a functional CLI tool that can batch upload Markdown files to Mowen platform
2. **Quality Goal**: Ensure robust error handling and user-friendly progress feedback
3. **Extensibility Goal**: Design modular architecture for future enhancements (image upload, advanced MD parsing)

## Scope

### In Scope
- Markdown file scanning in current directory
- Basic Markdown parsing (headings, bold, links, quotes)
- API integration with Mowen OpenAPI
- Rate limiting (1 req/sec) and quota management (100 req/day)
- Configuration management (API key, tags, auto-publish)
- Progress display and error reporting
- Dry-run mode for preview

### Out of Scope (Future Phases)
- Recursive directory scanning
- Image/audio/PDF upload
- Advanced Markdown syntax (tables, code blocks with syntax highlighting)
- Upload history tracking
- Interactive mode

## Technical Approach

### Architecture
- **Modular Design**: Separate concerns into scanner, parser, converter, uploader modules
- **Dependency**: Use zig-framework for HTTP client and file system operations
- **Error Handling**: Graceful degradation - skip failed files and report at end

### Key Technical Decisions

1. **Markdown Processing Strategy**: Rich text mode with fallback
   - Parse MD syntax and map to NoteAtom structure
   - If parsing fails, fallback to plain text upload
   - MVP supports: headings, paragraphs, bold, links, quotes (no italic)

2. **Configuration Management**
   - Default path: `~/.mowen/config.json` (cross-platform)
   - Support environment variable: `MOWEN_API_KEY`
   - Support CLI flag: `--api-key`

3. **Rate Limiting**
   - Sleep 1 second between uploads
   - Retry on 429 (rate limit): 3 attempts with exponential backoff (2s, 5s, 10s)

4. **Progress Display**
   - Use `\r` carriage return for same-line updates
   - Format: `[2/10] Uploading: example.md...`

## Implementation Phases

### Phase 1: Project Setup (Tasks 1.1-1.4)
- Create project structure
- Setup build configuration
- Implement basic CLI framework
- Create placeholder modules

**Success Criteria**: Project compiles and runs with `--help` flag

### Phase 2: Configuration (Tasks 2.1-2.3)
- Implement Config struct
- Support multiple config sources (file, env, CLI)
- Add config validation

**Success Criteria**: Can load API key from config file or environment

### Phase 3: Markdown Parsing (Tasks 3.1-3.4)
- Implement tokenizer for MD syntax
- Build AST parser
- Create MdNode data structures
- Add unit tests

**Success Criteria**: Can parse sample MD files into AST

### Phase 4: NoteAtom Conversion (Tasks 4.1-4.3)
- Implement NoteAtom data structures
- Create MD-to-NoteAtom converter
- Implement JSON serialization

**Success Criteria**: Can convert parsed MD to valid NoteAtom JSON

### Phase 5: File Scanning (Tasks 5.1-5.2)
- Implement directory scanner
- Add file filtering logic

**Success Criteria**: Can list all .md files in current directory

### Phase 6: API Integration (Tasks 6.1-6.4)
- Implement API client
- Add authentication
- Implement rate limiting
- Add retry logic

**Success Criteria**: Can successfully upload a single note to Mowen

### Phase 7: Batch Upload (Tasks 7.1-7.3)
- Implement batch upload orchestration
- Add progress display
- Implement error collection and reporting

**Success Criteria**: Can upload multiple files with progress feedback

### Phase 8: Testing & Polish (Tasks 8.1-8.3)
- Create test fixtures
- Write integration tests
- Add dry-run mode

**Success Criteria**: All tests pass, dry-run works correctly

### Phase 9: Documentation (Tasks 9.1-9.2)
- Write README with usage examples
- Document configuration options

**Success Criteria**: Users can understand how to use the tool from README

## Risk Management

### High Priority Risks

1. **Risk**: Markdown parsing complexity
   - **Mitigation**: Start with simple regex-based parser, fallback to plain text
   - **Contingency**: If parsing is too complex, ship MVP with plain text only

2. **Risk**: NoteAtom JSON serialization
   - **Mitigation**: Use std.json.stringify with custom serialization logic
   - **Contingency**: Manually construct JSON strings if needed

3. **Risk**: API rate limiting too restrictive
   - **Mitigation**: Clear progress display, dry-run mode for preview
   - **Contingency**: Add batch size limit warning

### Medium Priority Risks

1. **Risk**: Cross-platform path handling
   - **Mitigation**: Use std.fs.getAppDataDir() for config path
   - **Testing**: Test on Windows and Linux

2. **Risk**: Large file handling
   - **Mitigation**: Stream file reading, set reasonable size limits
   - **Contingency**: Skip files over 1MB with warning

## Success Metrics

1. **Functionality**: Can upload 10 MD files successfully in one run
2. **Reliability**: Handles network errors gracefully, reports failures clearly
3. **Usability**: Clear progress feedback, helpful error messages
4. **Performance**: Respects rate limits, completes 10 files in ~10 seconds

## Timeline

- **Estimated Duration**: 15-18 days (based on tasks.md)
- **Critical Path**: Phase 3 (MD parsing) → Phase 4 (NoteAtom conversion) → Phase 6 (API integration)
- **Milestone 1**: End of Phase 4 - Can convert MD to NoteAtom JSON
- **Milestone 2**: End of Phase 6 - Can upload single file to API
- **Milestone 3**: End of Phase 8 - Full batch upload with testing

## Next Steps

1. Create individual spec documents for each phase
2. Start with Phase 1 implementation (project setup)
3. Validate API integration early with a simple test upload
4. Iterate based on testing feedback

## References

- Requirements: `docs/requirements.md`
- Design: `docs/design.md`
- Tasks: `docs/tasks.md`
- Mowen API: https://mowen.apifox.cn/295621359e0
- Reference Implementation: https://github.com/z4656207/mowen-mcp-server
