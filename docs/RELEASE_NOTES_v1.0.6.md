# v1.0.6

## 修复

### 接扩展屏后岛跑到外接屏

原来窗口按 `NSScreen.main` 定位，而 `NSScreen.main` 是「当前有焦点的屏幕」——点一下扩展屏上的窗口，岛就跟着跑到扩展屏（那块没有刘海，位置也错），内置刘海屏反而空着。

改为按屏幕能力选定目标屏，与焦点无关：

| 优先级 | 条件 | 说明 |
|---|---|---|
| 1 | 有刘海（`auxiliaryTopLeftArea` + `auxiliaryTopRightArea`） | 内建 MacBook 屏，正常情况 |
| 2 | 内建屏（`CGDisplayIsBuiltin`） | 合盖或用非刘海机型 |
| 3 | 带菜单栏的主显示器 | 无内建屏，如 Mac mini / Studio |

目标屏在启动时确定，只随显示器配置变化（插拔、改分辨率、镜像）刷新；把焦点切到扩展屏不会再让岛移动。扩展屏上不再出现岛，也不影响扩展屏的鼠标点击。

## 完整功能

- **通知**：辅助功能读横幅做实时预览（~0.3s），usernoted 数据库做事实源；系统通知中心清空后 0.4s 同步清空本地列表
- **剪贴板**：文本/图片/文件历史，搜索、收藏、持久化，过滤密码管理器敏感类型
- **媒体**：读取 NowPlaying，封面/标题/歌手/单行歌词/进度，上一首 / 播放暂停 / 下一首
- **歌词**：按曲目请求网易云 / LRCLIB，LRC 按进度取当前行，本地缓存

## 安装

下载 `FlyIsland-1.0.6-macos-universal.zip`（Apple Silicon + Intel 通用），解压后拖进「应用程序」。

首次启动需在系统设置授权：

1. 隐私与安全性 → **完全磁盘访问权限** → 勾选 FlyIsland（读系统通知）
2. 隐私与安全性 → **辅助功能** → 勾选 FlyIsland（实时预览、全局 Esc）

未签名版本首次打开如被 Gatekeeper 拦截：

```bash
xattr -dr com.apple.quarantine /Applications/FlyIsland.app
```

## 系统要求

macOS 14.0+，带刘海的 Mac（MacBook Pro 14/16、MacBook Air 13/15 M2 及之后）。无刘海机型会贴在菜单栏正中显示。
