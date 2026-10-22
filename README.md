# JSON格式化工具（macOS / SwiftUI）

参照 VS Code 编辑器风格实现的 macOS 原生 JSON 工具：格式化 / 压缩、文本·树状双视图、行号显示、检索替换、导入导出，支持深色 / 浅色主题。

![文本视图（深色）](docs/screenshots/text-view.png)
![浅色主题](docs/screenshots/text-view-light.png)

## 功能

| 能力 | 说明 |
| --- | --- |
| 格式化 | 自研解析器（保留键顺序与数字原文），缩进 2 空格美化 |
| 压缩 | 一键输出紧凑单行 JSON（`⌥⌘M` 或顶栏「压缩」） |
| 一键修复 | 解析失败时修补常见非标准写法后重新美化，并在状态栏列出修复项（顶栏「修复」/ `⌥⌘R`） |
| 主题 | 深色 / 浅色切换，配色对齐 VS Code Dark+ / Light+，选择本地持久化 |
| 文本视图 | `NSTextView` 编辑器，等宽字体、行内可编辑、支持撤销/重做 |
| 行号 | 左侧行号栏（`NSRulerView`）：随滚动/换行/字号对齐，软换行只在首行编号，当前行加亮；顶栏 `#` 按钮或 `⌥⌘L` 开关，选择持久化 |
| 树状视图 | 可折叠节点、`{ n }` / `[ n ]` 计数、VS Code 语法配色 |
| 检索替换 | 底部查找栏：命中高亮 + 当前命中橙色标记、上下跳转、单次/全部替换 |
| 高级检索 | `Aa` 区分大小写、`.*` 正则（替换支持 `$1` 捕获组） |
| 字号调节 | 顶栏左侧滑杆 9–28 pt，实时生效 |
| 导入 / 导出 | 顶栏按钮或面板选择文件；也支持拖入 `.json` 文件或 JSON 文本 |
| 错误提示 | 解析失败给出「第 X 行 第 Y 列：原因」，替换破坏结构时保留原文并提示 |
| 应用图标 | VS Code 风格 JSON 代码块图标，随 `.app` 打包 |

## 界面布局

- **顶栏**：左侧「字号滑杆 + 主题按钮 + 行号开关」，中间「文本视图 / 树状视图」切换，右侧「导入 / 格式化 / 压缩 / 修复 / 导出」。
- **底部**：查找替换栏默认常显（`⌘F` 聚焦输入框，`Esc` 或右侧 `×` 收起），包含查找/替换输入、计数、大小写与正则开关、上下跳转。
- 深色为主题默认值，可在顶栏太阳/月亮按钮或 `⌥⌘T` 切换。

## 快捷键

| 快捷键 | 动作 |
| --- | --- |
| ⌘O | 导入 JSON 文件 |
| ⌘S | 导出 |
| ⇧⌘C | 复制全部内容 |
| ⌘F | 查找与替换 |
| ⌘G / ⇧⌘G | 下一个 / 上一个命中 |
| ⌥⌘F | 格式化 |
| ⌥⌘M | 压缩为单行 |
| ⌥⌘R | 一键修复异常 JSON |
| ⌥⌘T | 切换深色 / 浅色主题 |
| ⌥⌘L | 显示 / 隐藏行号 |
| ⌘1 / ⌘2 | 文本视图 / 树状视图 |
| Esc | 关闭查找栏 |

## 构建运行

```bash
./build.sh          # 编译 release 并打包 build/JSON格式化工具.app
./build.sh run      # 打包后启动（会先结束旧进程）
./tools/make_icns.sh  # 重新生成应用图标（assets/AppIcon.icns）
```

依赖：Xcode 命令行工具（Swift 5.9+，macOS 13+）。

## 结构

```
Sources/JSONFormatter/
├── JSONFormatterApp.swift      应用入口 + 菜单命令
├── Models/
│   ├── JSONNode.swift          解析器 / 序列化（保留顺序、数字原文、错误行列号）
│   ├── AppTheme.swift          深/浅色主题与 VS Code 语法配色
│   ├── JSONRepair.swift        异常 JSON 修复：注释/单引号/裸键/尾随逗号/缺失逗号等
│   └── AppModel.swift          文档状态、格式/压缩/修复/导入导出/替换/主题
├── Editor/
│   ├── JSONTextView.swift      NSTextView 桥接 + 查找高亮 + 主题着色 + 行号栏装配
│   ├── LineNumberRulerView.swift  行号栏（NSRulerView，软换行/滚动/字号同步）
│   ├── FindState.swift         匹配计算（字面量 / 正则）
│   └── EditorController.swift  选中、滚动、可撤销替换
├── Views/
│   ├── ContentView.swift       主界面（顶栏 / 底部查找栏 / 拖放）
│   ├── FindBar.swift           查找替换栏（底部）
│   └── JSONTreeView.swift      树状视图
└── Support/
    ├── SelfTest.swift          JF_SELFTEST=1 核心断言
    └── SnapshotSupport.swift   JF_SNAPSHOT=path 窗口自渲染截图

tools/
├── make_icon.swift              绘制 1024 图标母版
└── make_icns.sh                 PNG → iconset → ICNS
assets/AppIcon.icns             应用图标（打包时写入 .app/Contents/Resources）
```

## 调试开关

```bash
JF_SELFTEST=1 build/JSON格式化工具.app/Contents/MacOS/JSONFormatter       # 解析/查找断言
JF_SNAPSHOT=/tmp/a.png JF_SNAPSHOT_EXIT=1 .../JSONFormatter               # 窗口截图后退出
JF_SNAPSHOT_QUERY=userPhone ...                                          # 截图时预填查找词
JF_SNAPSHOT_MODE=tree ...                                                # 截图时用树状视图
JF_SNAPSHOT_THEME=light ...                                              # 截图时使用浅色主题
JF_SNAPSHOT_FILE=/tmp/a.json ...                                         # 截图前先载入指定文件
```

## 已知取舍

- 缩进固定 2 空格（未做可配置）。
- 文本视图默认按宽度软换行，折行续行不缩进（不显示悬挂缩进）。
- 正则模式的单次替换用字面量替换文本，`$1` 展开仅用于「全部替换」与整体替换。
