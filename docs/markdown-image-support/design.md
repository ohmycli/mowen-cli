# Markdown 图片上传支持 - 设计

## 1. 设计原则

- 保留现有 `scanner -> parser -> converter -> uploader -> note/create` 主流程。
- 图片上传单独抽成资源层，不混进笔记上传接口。
- 图片是 block 节点，inline 图片需要在转换阶段提升并拆分段落。

## 2. 总体流程

```text
md 文件
  -> parser 识别文本 / 图片
  -> converter 收集图片引用
  -> image_uploader 解析 source 类型
  -> 本地图: upload/prepare + multipart
  -> 远程图: upload/url
  -> note_atom builder 生成最终 NoteAtom
  -> uploader 调 note/create 或 note/edit
```

## 3. 模块划分

### 3.1 `src/parser.zig`

- 在现有 token 流里加入 `image`。
- 识别 `![alt](src)`。
- 保留文本顺序，不把图片吞掉。
- 解析到图片时，不直接丢弃前后的文本。

### 3.2 `src/image_uploader.zig`

- 新增图片资源上传器。
- 输入：图片来源、Markdown 文件路径、API 配置。
- 输出：墨问返回的 `fileId`。
- 内部维护 `source -> fileId` 缓存，同一篇笔记内复用。

### 3.3 `src/note_atom.zig`

- 增加 `image` 节点。
- 结构建议：

```zig
image: struct {
    attrs: struct {
        uuid: []const u8,
        alt: []const u8 = "",
        align: []const u8 = "center",
    },
}
```

- JSON 序列化必须输出 `type: "image"` 和 `attrs`。

### 3.4 `src/converter.zig`

- 负责把 Markdown 结构转成最终 `NoteAtom`。
- 遇到图片时，先通过 `image_uploader` 拿 `fileId`。
- 如果一个段落里混有文字和图片，拆成多个块，按原始顺序输出。

### 3.5 `src/main.zig`

- 在 `create`、`edit`、`upload` 流程里注入图片解析上下文。
- 统一处理 note 上传和图片上传的限频。

## 4. 图片处理规则

- 远程图片：直接调用 `upload/url`，再取返回的 `fileId`。
- 本地图片：先调用 `upload/prepare` 拿表单，再按文档里的 multipart 方式投递。
- `src` 作为本地路径时，按 Markdown 文件所在目录解析相对路径。
- 图片上传失败时，终止当前文件，避免生成残缺笔记。
- `alt` 原样保留，`align` 默认 `center`。

## 5. 关键权衡

- 墨问的图片是 block 节点，不是 inline 节点，所以 Markdown 里的内联图片必须做 block 化处理。
- 远程上传依赖目标 URL 可访问，存在防盗链或超时风险。
- 本地上传比远程上传更稳定，但需要先读本地文件。

## 6. 测试点

- 解析 `![alt](src)` 是否成功。
- 本地图片是否正确转成 `fileId`。
- 远程图片是否正确转成 `fileId`。
- 图片在正文中的顺序是否保持。
- 重复图片是否复用缓存。
