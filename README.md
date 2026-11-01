# Fly Island for Mac

macOS 版灵动岛。仿 [fly-island](https://github.com/flyl1u/fly-island) 的形态，把 **系统通知（微信 / QQ 等）**、**剪贴板历史**、**媒体控制** 收进屏幕顶部的刘海区域。

原生 Swift + AppKit + SwiftUI，无 Electron、无 Tauri，常驻内存约 60 MB。

---

## 功能

| 模块 | 能力 |
|---|---|
| 通知 | **双通道**：辅助功能读横幅做秒级提醒（实测 0.3s），usernoted 数据库做事实来源（系统落库本身约 5s 延迟）；新消息弹出预览，点击跳转对应应用；未读计数显示在刘海右侧 |
| 剪贴板 | 文本 / 图片 / 文件路径历史，搜索、收藏、单条删除、一键回填剪贴板；自动跳过密码管理器等敏感类型；持久化到本机 |
| 媒体 | 读取系统 NowPlaying（音乐、浏览器、播客），显示封面、标题、歌手、**单行歌词**、进度，支持上一首 / 播放暂停 / 下一首 |
| 交互 | 折叠 / 通知预览 / 悬停展开 / 点击展开 四态，弹簧动画；四个标签页统一高度（296pt），切换不跳动；点击岛外或 Esc 收起 |

## 安装

```bash
cd FlyIsland
./build.sh              # 产出 build/FlyIsland.app
cp -R build/FlyIsland.app /Applications/
open /Applications/FlyIsland.app
```

已构建版本也在 `/Applications/FlyIsland.app`。

## 首次运行：两个权限

设置页有状态指示与跳转按钮（状态栏图标 → 设置）。

1. **完全磁盘访问权限** —— 读取系统通知数据库，缺它则通知列表为空
   系统设置 → 隐私与安全性 → 完全磁盘访问权限 → 勾选 FlyIsland
2. **辅助功能** —— 实时横幅通知（缺它预览会比系统落库慢约 5 秒）+ 全局 Esc 收起
   系统设置 → 隐私与安全性 → 辅助功能 → 勾选 FlyIsland

授权后点设置页的「重新检查」或重启应用。

## 签名

用本地自签名证书签名，好处是**指定要求（Designated Requirement）只绑定 bundle id + 证书根，不含代码哈希**，重编译换二进制不会让 TCC 授权失效。

```bash
./Tools/make_signing_cert.sh   # 一次性：生成并导入 "FlyIsland Development" 证书
./build.sh                     # 之后每次构建自动用它签名
```

验证：

```bash
codesign -d -r- /Applications/FlyIsland.app
# designated => identifier "com.flyisland.mac" and certificate root = H"3a51..."
```

没生成证书时 build.sh 会退回 ad-hoc 签名（每次重编译需重新授权）。

## 使用

- **悬停**刘海 → 自动展开（可在设置里关）
- **点击**刘海 → 展开并固定，点击外部 / Esc 收起
- 顶部标签：左 通知、剪贴板；右 音乐、设置（中间被物理刘海隔开，正好利用这块空隙）
- 通知行点击 → 打开来源应用；剪贴板行点击 → 复制回剪贴板
- 状态栏胶囊图标 → 快速打开各面板、开机自启、退出

## 实现要点

| 能力 | 做法 |
|---|---|
| 通知（实时） | 辅助功能遍历 `com.apple.notificationcenterui` 的窗口，取 `subrole=AXNotificationCenterBanner` 的元素：`AXAttributedDescription` 形如「App名 标题, 副标题, 正文」，配合子元素 `id=title/body` 还原字段；横幅 UUID 去重。轮询 0.35s，实测通知发出后 ~0.3s 弹出预览 |
| 通知（事实源） | 只读 `~/Library/Group Containers/group.com.apple.usernoted/db2/db`，解析 `record.data` 的 plist（`req.titl` / `req.body`）；优先直接只读打开原库（零拷贝），失败退回快照；kqueue 监听 db 与 -wal，落盘即拉取，另有 0.3s 兜底轮询。系统落库延迟实测 ~5s，故仅作列表与跳转的依据 |
| 通知去重 | 实时通道弹过「应用+标题」后 10s 内，数据库通道补齐同一条时不再重复弹 |
| 媒体（读） | macOS 15.4 起 `mediaremoted` 只服务 `com.apple.*` 进程，因此由 `/usr/bin/perl`（bundle id `com.apple.perl`）加载 `libislandmedia.dylib`，通过 `MediaRemote.framework` 私有符号读元数据，stdout 逐行 JSON 回传（2s 轮询 + 串行队列，父进程消失自杀） |
| 媒体（控制） | `MRMediaRemoteSendCommand` 对部分播放器只回 `ok` 不动作（实测汽水音乐如此）。改为投递 NX_KEYTYPE 媒体键事件（等于按 F8/F9/F10），由系统派发给当前 NowPlaying 应用；无「辅助功能」权限时退回 MediaRemote 命令，媒体键 1.6s 内未生效也自动补一次命令。命令下发后 0.35s 主动拉一次状态，切歌界面秒更新 |
| 交互陷阱 | 岛卡片上不能挂 `onTapGesture` —— 父级手势会吞掉展开态里所有按钮的点击，点击手势只挂在折叠态/预览态上 |
| 剪贴板 | `NSPasteboard.changeCount` 轮询，过滤 `org.nspasteboard.*` 敏感类型 |
| 歌词 | 系统 NowPlaying 不含歌词。曲目变化时按「歌名 + 歌手」请求网易云歌词接口（带时间轴），失败退回 LRCLIB（部分只有纯文本，按行均分时间）；解析 LRC 后按播放进度取当前行，结果缓存到 `cache/lyrics-*.json`。只发送歌名/歌手/时长，可在设置里关闭 |
| 刘海几何 | `NSScreen.auxiliaryTopLeftArea / auxiliaryTopRightArea` 反推刘海宽度（本机 220pt），`safeAreaInsets.top` 取高度（38pt） |
| 窗口 | 无边框 `NSPanel`，重写 `constrainFrameRect` 才能贴屏幕顶端；`isFloatingPanel` 会重置 level，须先设它再设 `statusBar+1`；`hitTest` 只在岛形区域命中，其余区域鼠标穿透 |

## 目录

```
FlyIsland/
├── build.sh                     # 一键构建
├── Info.plist
├── Native/island_media.m        # MediaRemote 适配（导出 mr_run / mr_stream / mr_command）
├── Resources/media/mediaremote.pl  # perl 宿主
├── Sources/
│   ├── main.swift / AppDelegate.swift / SelfTest.swift
│   ├── Models.swift / Settings.swift
│   ├── Services/                # AppInfo / MediaService / ClipboardService / NotificationService / AXNotificationWatcher
│   └── UI/                      # IslandLayout / IslandModel / IslandPanel / Theme / 各视图 / RenderMode
└── Tools/make_icon.swift        # 生成 AppIcon.icns
```

## 调试

```bash
FlyIsland.app/Contents/MacOS/FlyIsland --selftest   # 打印三条数据链路状态
FlyIsland.app/Contents/MacOS/FlyIsland --render /tmp/out   # 离屏渲染各状态 PNG
FlyIsland.app/Contents/MacOS/FlyIsland --demo       # 启动后自动展开/切换/收起
```

## 已知限制

- 系统把通知写进数据库有 **约 5 秒延迟**（实测），实时预览靠辅助功能通道弥补；关掉辅助功能权限则只剩数据库通道
- 只能拿到**已投递到通知中心**的通知；用户在系统设置里关掉的通知不会出现
- 通知内容读取依赖微信 / QQ 保持登录并开启系统通知
- 系统不提供第三方监听他人通知的公开 API，此处走的是通知数据库 + 辅助功能两条私有路径，系统升级后可能需要适配
- 媒体信息依赖私有框架 `MediaRemote`，同样可能在系统升级后失效

调试开关补充：`--axtest` 打印辅助功能抓到的横幅，`--axtest --axtree` 打印通知中心 AX 树（排查横幅结构变化时用）。

## License

[MIT](LICENSE)
