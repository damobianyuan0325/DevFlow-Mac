# DevFlow 品牌资产

2026-10-30按用户要求原创设计：深墨绿圆角底，开放式D形路径从实心起点绕行到空心证据节点，表达开发过程可追溯。无字体或第三方图案依赖。

矢量源：`assets/DevFlow.svg`。本地AppKit生成器：`scripts/generate-icon.swift`。输出：1024px透明边缘PNG、多尺寸ICNS和浅深背景预览。ICNS包含16–1024及Retina表示，AppKit和iconutil读取通过。生成时修正过小尺寸阴影单位导致的方形伪影，保留一致几何。

```sh
swift -module-cache-path .build/icon-module-cache scripts/generate-icon.swift
bash scripts/build-app.sh
```

构建脚本将图标写入应用Contents/Resources并声明CFBundleIconFile，同时把PNG放进SwiftPM资源供侧栏使用。原生About面板与侧栏已看到实际图标。仓库中的源码与品牌资产适用根目录 LICENSE 的 MIT 许可；项目名称尚未完成商标检索。
