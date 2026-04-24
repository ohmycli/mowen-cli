# Markdown 图片上传支持 - Tasks

## 执行顺序

建议按 `数据模型 -> 解析器 -> 图片上传器 -> 主流程接入 -> 测试` 的顺序实现。

## Task 1: 扩展 NoteAtom 数据模型

**目标**: 让墨问笔记结构能表达图片。

**工作内容**:

- [ ] 修改 `mowen-cli/src/note_atom.zig`
- [ ] 新增 `image` 节点类型
- [ ] 定义 `uuid`、`alt`、`align` 属性
- [ ] 更新 JSON 序列化，输出 `type: "image"`
- [ ] 更新内存释放逻辑

**验收标准**:

- `NoteAtom` 能序列化图片节点。
- 现有 `doc/paragraph/text/quote/codeblock` 行为不回退。

---

## Task 2: 解析 Markdown 图片语法

**目标**: 识别 `![alt](src)` 并保留文本顺序。

**工作内容**:

- [ ] 修改 `mowen-cli/src/parser.zig`
- [ ] 在 token 流里加入 `image`
- [ ] 解析 `alt` 和 `src`
- [ ] 处理段落中图片前后的文本切分
- [ ] 处理本地路径和 URL 的基础识别

**验收标准**:

- 图片 token 能被正确识别。
- `Hello ![a](x.png) world` 这类输入不会丢失前后文本。

---

## Task 3: 实现图片上传器

**目标**: 把图片源转换成墨问 `fileId`。

**工作内容**:

- [ ] 新建 `mowen-cli/src/image_uploader.zig`
- [ ] 实现远程图片上传，调用 `/api/open/api/v1/upload/url`
- [ ] 实现本地图片上传，调用 `/api/open/api/v1/upload/prepare` 后执行 multipart 投递
- [ ] 从上传结果里提取 `fileId`
- [ ] 增加 `source -> fileId` 缓存
- [ ] 加上 429 / 超时重试

**验收标准**:

- 本地图片和远程图片都能返回 `fileId`。
- 同一篇笔记里重复引用同一图片时只上传一次。

---

## Task 4: 接入笔记构建流程

**目标**: 在创建/编辑笔记前先把图片资源解析完。

**工作内容**:

- [ ] 修改 `mowen-cli/src/converter.zig`
- [ ] 把图片上传结果写入最终 `NoteAtom.image`
- [ ] 如果段落里混有图片，拆成多个块
- [ ] 修改 `mowen-cli/src/main.zig`
- [ ] 在 `create`、`edit`、`upload` 三条路径里注入图片上下文
- [ ] 统一图片和笔记的限频控制

**验收标准**:

- 最终发送给墨问的请求体里，图片节点使用真实 `fileId`。
- 图片上传失败时，当前文件明确失败。

---

## Task 5: 补测试

**目标**: 验证图片支持的核心路径。

**工作内容**:

- [ ] 扩展 `mowen-cli/tests/parser_test.zig`
- [ ] 增加图片语法解析测试
- [ ] 增加本地图片上传测试
- [ ] 增加远程图片上传测试
- [ ] 增加重复图片缓存测试
- [ ] 增加端到端测试样例

**验收标准**:

- 解析、上传、嵌入、失败场景都有覆盖。
- 现有测试保持通过。

---

## Task 6: 文档同步

**目标**: 让用户知道如何写图片。

**工作内容**:

- [ ] 更新 `mowen-cli/README.md`
- [ ] 增加图片语法示例
- [ ] 说明本地/远程图片限制
- [ ] 说明图片失败时的行为

**验收标准**:

- 用户能看懂图片支持范围和限制。
