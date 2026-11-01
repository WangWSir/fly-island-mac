## Fly Island for Mac v1.0.0

macOS 版灵动岛。把**系统通知**、**剪贴板历史**、**媒体控制**收进屏幕顶部的刘海区域。原生 Swift + AppKit + SwiftUI，无 Electron / Tauri，常驻内存约 60 MB。

### 功能

- **通知**：双通道接入。辅助功能读横幅，实测通知发出后 **0.3s** 弹出预览；`usernoted` 数据库做事实来源（系统落库本身约 5s 延迟）。点击预览可跳转来源应用，未读数显示在刘海右侧。
- **剪贴板**：文本 / 图片 / 文件路径历史，搜索、收藏、单条删除、一键回填；自动跳过密码管理器的敏感类型；本机持久化。
- **媒体**：读取系统 NowPlaying，显示封面、标题、歌手、**单行歌词**、进度，支持上一首 / 播放暂停 / 下一首。控制走系统媒体键事件，兼容忽略 `MRMediaRemoteSendCommand` 的播放器（如汽水音乐）。
- **交互**：折叠 / 通知预览 / 悬停展开 / 点击展开 四态弹簧动画；四个标签页统一高度，切换不跳动；点岛外或 Esc 收起；岛外区域鼠标穿透。

### 安装

1. 下载 `FlyIsland-1.0.0-macos-universal.zip`（Apple Silicon + Intel 通用），解压后把 `FlyIsland.app` 拖进「应用程序」
2. 首次打开会被 Gatekeeper 拦（未签名未公证）：
   - 右键 `FlyIsland.app` → **打开** → 弹窗里再点「打开」，或
   - `xattr -dr com.apple.quarantine /Applications/FlyIsland.app`
3. 授权：系统设置 → 隐私与安全性 → **完全磁盘访问权限** 与 **辅助功能** → 勾选 FlyIsland
4. 重启应用

### 说明

- 最低系统：macOS 14.0
- 本包为 ad-hoc 签名，未公证；不接受则自行编译：`UNIVERSAL=1 SIGN_ID=- ./build.sh`
- 通知与媒体都走系统私有路径（`usernoted` 数据库、`MediaRemote` 框架、通知中心 AX 树），系统升级后可能需要适配

SHA256（zip）见 Release 附件 `SHA256SUMS.txt`。
