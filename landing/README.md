# Octo 产品站

设计：Apple 风格浅色页面，系统字体、克制动效、真实产品截图。使用 baoyu-design 方法；发布骨架参考本机 shotpad/landing，按 Octo 品牌重写页面。

运行 `node build.mjs`，再用 `python3 -m http.server 4328 --bind 127.0.0.1 --directory dist` 预览。无依赖安装步骤。`wrangler deploy` 发布到配置中的独立产品域名。

版本号从仓库根 `VERSION` 读取；网页模板使用 `{{VERSION}}`，构建时校验 R2 下载地址并为图片、CSS 和 JS 生成内容哈希。

0.5.0 增加“版本更新内容”模块，首图使用维护者本轮提供的最新工作区截图；列表、图标图来自原生应用离屏导出。网站只提供说明和附件下载，不访问访客本地文件、不嵌入第三方统计。
