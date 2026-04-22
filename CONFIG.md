# 配置文件说明

`config.example.json` 是墨问 CLI 工具的配置文件示例。

## 配置文件位置

- **Linux/macOS**: `~/.mowen/config.json`
- **Windows**: `%USERPROFILE%\.mowen\config.json`

你也可以使用 `--config` 参数指定自定义配置文件路径。

## 配置字段说明

### api_key (必需)
- **类型**: 字符串
- **说明**: 墨问 API 密钥
- **获取方式**: 访问 [墨问开放平台](https://open.mowen.cn) 获取 API Key

### api_endpoint (可选)
- **类型**: 字符串
- **默认值**: `https://open.mowen.cn/api/open/api/v1/note/create`
- **说明**: 墨问 API 端点地址

### timeout_ms (可选)
- **类型**: 整数
- **默认值**: `30000` (30 秒)
- **有效范围**: 1000-300000 (1 秒到 5 分钟)
- **说明**: HTTP 请求超时时间（毫秒）

### default_tags (可选)
- **类型**: 字符串数组
- **默认值**: `[]`
- **说明**: 默认标签列表
- **示例**: `["blog", "tech"]`

### auto_publish (可选)
- **类型**: 布尔值
- **默认值**: `false`
- **说明**: 是否自动发布笔记

## 使用示例

1. 复制示例文件到配置目录：
   ```bash
   # Linux/macOS
   mkdir -p ~/.mowen
   cp config.example.json ~/.mowen/config.json
   
   # Windows
   mkdir %USERPROFILE%\.mowen
   copy config.example.json %USERPROFILE%\.mowen\config.json
   ```

2. 编辑配置文件，填入你的 API Key：
   ```json
   {
     "api_key": "your-actual-api-key",
     "api_endpoint": "https://open.mowen.cn/api/open/api/v1/note/create",
     "timeout_ms": 30000,
     "default_tags": ["blog"],
     "auto_publish": true
   }
   ```

## 配置优先级

配置可以从多个来源加载，优先级从高到低：

1. **命令行参数** (最高优先级)
   ```bash
   mowen-cli --api-key "xxx" --api-endpoint "https://..."
   ```

2. **环境变量**
   ```bash
   export MOWEN_API_KEY="xxx"
   export MOWEN_API_ENDPOINT="https://..."
   ```

3. **配置文件** (最低优先级)
   ```json
   {
     "api_key": "xxx",
     "api_endpoint": "https://..."
   }
   ```
