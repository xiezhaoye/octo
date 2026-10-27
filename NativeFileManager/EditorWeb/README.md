# 文档预览资源

Octo 的分栏文档编辑使用原生 NSTextView，保留系统输入法、选择、撤销及剪贴板行为。Markdown 预览使用与 XMark 相同的 unified + remark-parse + remark-gfm 技术栈，再通过 mdast-util-to-hast / hast-util-to-html 转为 HTML。HTML 和 Markdown 输出均由 DOMPurify 净化，在禁止脚本的 sandbox iframe 中显示。JSON 使用原生 JSON.parse 校验并显示折叠树。

这不是整个 XMark/Tiptap 工作区的复制，不包含所见即所得编辑、Mermaid 或数学公式扩展。HTML 默认不执行脚本，不加载远程资源或相邻文件资源。

`Sources/DualPane/Resources/Editor/` 的 bundle、HTML 和第三方许可均随应用打包，构建和运行无需 Node、网络或 XMark。只有修改预览脚本后需要重建 bundle：

```sh
cd NativeFileManager
node EditorWeb/build.mjs /absolute/path/to/xmark
```

脚本从指定 XMark 的现有 node_modules 解析组件，不修改 XMark，不安装依赖，并收集完整依赖图的许可证。生成的 preview.js 和 THIRD_PARTY_NOTICES.txt 必须一起保留。

当前复用的主要版本：unified 11、remark-parse 11、remark-gfm 4、mdast-util-to-hast 13、hast-util-to-html 9、DOMPurify 3。确切版本记录在生成的许可文件中。
