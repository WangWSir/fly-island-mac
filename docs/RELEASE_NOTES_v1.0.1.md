## Fly Island for Mac v1.0.1

修复：**岛周围一圈点不动**。

### 问题

悬浮面板为了绘制阴影，窗口比岛本身大一圈（左、右、下各 45pt）。这圈透明区域会把鼠标点击吃掉，不会传给下面的应用——表现就是岛的周围（菜单栏两侧、浏览器标签栏上方）凭空出现一块"死区"，点哪都没反应。

v1.0.0 只做了 `hitTest` 层面的过滤，但 `hitTest` 返回 `nil` 只是让 SwiftUI 收不到事件，窗口本身依旧把点击消化掉了，不会穿透到下层。

### 修复

按光标位置动态开关 `ignoresMouseEvents`：

- 光标进入岛内 → 恢复接收事件（按钮、列表、拖动都正常）
- 光标离开岛 → 立即把鼠标事件让给下层窗口
- 拖动/划选中途不切换，避免打断手势
- 0.1s 轮询之外额外挂了全局 `mouseMoved` 监听，快速划过也不会漏

实测：岛下方 30pt、岛左右两侧边缘的点击 100% 穿透；岛内点击、悬停展开均不受影响。

### 安装

1. 下载 `FlyIsland-1.0.1-macos-universal.zip`（Apple Silicon + Intel 通用），解压后把 `FlyIsland.app` 拖进「应用程序」
2. 首次打开会被 Gatekeeper 拦（未签名未公证）：
   - 右键 `FlyIsland.app` → **打开** → 弹窗里再点「打开」，或
   - `xattr -dr com.apple.quarantine /Applications/FlyIsland.app`
3. 授权：系统设置 → 隐私与安全性 → **完全磁盘访问权限** 与 **辅助功能** → 勾选 FlyIsland
4. 重启应用

> 从 v1.0.0 升级：直接覆盖 `/Applications/FlyIsland.app` 即可，**不需要重新授权**（bundle id 不变），重启应用生效。

### 说明

- 最低系统：macOS 14.0
- ad-hoc 签名，未公证
- 通知与媒体都走系统私有路径（`usernoted`、`MediaRemote`、通知中心 AX 树），系统升级后可能需要适配

SHA256（zip）见 Release 附件 `SHA256SUMS.txt`。
