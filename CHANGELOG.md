# Changelog

All notable changes to this project will be documented in this file.

## [v0.1.0](https://github.com/ohmycli/mowen-cli/releases/tag/v0.1.0) (2026-04-22)

### 核心功能

- 单文件管理：`create`、`edit`、`set-privacy` 命令
- 批量上传：`upload` 命令，自动扫描当前目录
- 元数据管理：`upload` 命令现在也会保存 noteId，支持后续编辑
- Markdown 解析：支持标题、段落、粗体、链接、引用、代码块、分隔线
- 配置管理：支持配置文件、环境变量、命令行参数
- 限频控制：自动 1 秒/次，避免触发 API 限制
- 预览模式：dry-run 支持

### 测试

- 27 个单元测试全部通过
- 配置管理测试
- Markdown 解析器测试
- 文件扫描器测试
