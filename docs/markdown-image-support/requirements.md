# Markdown 图片上传支持 - 需求

## 1. 背景

现有 `mowen-cli` 已经可以把 Markdown 转成墨问 `NoteAtom` 并调用 `note/create` 和 `note/edit`。
墨问 API 不是直接接收 Markdown 字符串，而是接收结构化的 `NoteAtom`，图片必须先上传成独立文件，再用 `image` 节点引用 `fileId`。

本需求的目标是：用户只要在 `.md` 里写标准图片语法，CLI 就能自动上传图片，并在墨问文档里正常显示。

## 2. 目标

- 识别 Markdown 图片语法。
- 自动上传本地图片和远程图片。
- 把图片写入墨问 `NoteAtom.image` 节点。
- 保持正文顺序和多图顺序。
- 保留现有文本、链接、粗体、引用转换行为。

## 3. 功能需求

### FR1: 图片语法识别

- 支持标准语法 `![alt](src)`。
- `src` 支持本地相对路径、本地绝对路径、`http://`、`https://`。
- `alt` 需要保留，写入图片说明。
- 不支持 `data:` URI、HTML `<img>`、base64 内联图片。
- `title` 属性不是 MVP 必需项。

### FR2: 图片资源上传

- 本地图片走 `/api/open/api/v1/upload/prepare` + multipart 投递。
- 远程图片走 `/api/open/api/v1/upload/url`。
- 图片类型遵守墨问限制：`gif/jpeg/jpg/png/webp`。
- 本地图片最大 50MB，远程图片最大 30MB。
- 同一篇笔记内重复引用同一个图片源，只上传一次。

### FR3: 笔记嵌入

- 图片上传成功后，生成 `type: "image"` 的 `NoteAtom`。
- `attrs.uuid` 保存 `fileId`。
- `attrs.alt` 保存图片描述。
- `attrs.align` 默认 `center`。
- 图片是 block 节点。
- 如果图片出现在段落中间，允许把段落拆成多个块，保证显示顺序不变。

### FR4: 错误处理

- Markdown 解析失败时，沿用现有纯文本降级策略。
- 图片语法能解析但上传失败时，当前文件失败，不生成缺图笔记。
- 错误信息必须包含图片来源、失败阶段、失败原因。

### FR5: 速率与配额

- 图片上传请求也必须遵守墨问接口限频。
- `note/create`、`note/edit`、`upload/url`、`upload/prepare` 共用同一套节流策略。
- 批量上传时，图片请求次数计入总耗时和总请求数。

## 4. 非功能要求

- 同一轮执行中，同一图片源应复用同一个 `fileId`。
- 不修改原始 Markdown 文件。
- 不破坏现有文本、链接、粗体、引用能力。
- 对无法识别或无法访问的图片源，要给出明确报错，不要静默丢图。

## 5. 验收标准

- Markdown 文档中的图片能在墨问笔记里显示。
- 本地图片和远程图片都能上传。
- 图片顺序与原文一致。
- 重复图片只上传一次。
- 失败场景有明确错误提示。
