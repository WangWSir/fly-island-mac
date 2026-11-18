# v1.0.8

## 修复

### 多出系统通知中心里没有的通知（Stash / BetterDisplay 等）

FlyIsland 直接读 `usernoted` 数据库，而数据库里有两种记录：

| 记录类型 | 特征 | 系统通知中心 | FlyIsland（旧） |
|---|---|---|---|
| 真正推给用户的 | `presented=1` | 显示 | 显示 ✅ |
| 后台静默投递 | `presented=0` | **从不显示** | 显示 ❌ 凭空多出来 |

Stash（`ws.stash.app.mac`，每次配置更新都发一条「配置已更新」，4 分钟内能来 5 条）、BetterDisplay 这类应用走的是静默通道：只落库、不弹横幅、不进通知中心。旧版本按时间窗口把库里记录全铺进列表，于是出现一堆通知中心看不到的条目。

修复：读取时按 `presented` 字段过滤，只保留系统真正展示过的通知。

实测（同一份数据库）：

| | 记录数 |
|---|---|
| 近 7 天全部记录 | 29 |
| 其中 `presented=0`（静默） | 24（Stash 12、BetterDisplay 11、hayaku 1） |
| 修复后载入 | 5（WorkBuddy 3 + 微信 2） |

`presented` 为 NULL 的记录按「展示过」处理，不会误杀老格式数据。

## 完整功能

- **通知**：辅助功能读横幅做实时预览（~0.3s），usernoted 数据库做事实源；系统通知中心清空后 0.4s 同步清空本地列表
- **剪贴板**：文本/图片/文件历史，搜索、收藏、持久化，过滤密码管理器敏感类型
- **媒体**：读取 NowPlaying，封面/标题/歌手/单行歌词/进度，上一首 / 播放暂停 / 下一首
- **歌词**：按曲目请求网易云 / LRCLIB，LRC 按进度取当前行，本地缓存
- **多屏**：固定在内置刘海屏，合盖/无刘海屏时隐藏（设置 → 常规 → 扩展屏显示 可改）

## 安装

下载 `FlyIsland-1.0.8-macos-universal.zip`（Apple Silicon + Intel 通用），解压后拖进「应用程序」。

升级务必先退出旧版本（菜单栏图标 → 退出 Fly Island），否则旧进程继续跑旧代码。

首次启动需在系统设置授权：

1. 隐私与安全性 → **完全磁盘访问权限** → 勾选 FlyIsland（读系统通知）
2. 隐私与安全性 → **辅助功能** → 勾选 FlyIsland（实时预览、全局 Esc）

未签名版本首次打开如被 Gatekeeper 拦截：

```bash
xattr -dr com.apple.quarantine /Applications/FlyIsland.app
```

## 系统要求

macOS 14.0+，带刘海的 Mac（MacBook Pro 14/16、MacBook Air 13/15 M2 及之后）。无刘海机型（Mac mini / Studio / iMac）贴在主屏菜单栏正中显示。
