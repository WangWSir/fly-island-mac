## Fly Island for Mac v1.0.3

修复：**通知中心清空后，新通知不再提醒**。

### 问题

增量拉取用 `rec_id` 单调递增判断新增（`WHERE rec_id > 上次最大值`）。系统通知中心被「清空」后，数据库的自增序列可能变化，新通知的 `rec_id` 不再严格递增，一旦比内存里记的 `lastID` 小，就会被当作「已处理」永久漏掉——表现就是清空过一次后，微信等新通知不弹预览、不进列表。

### 修复

改用 `seenIDs` 集合判定新增：

- 每次读取「近 7 天」全部记录（量很小），是否新增由「这个 id 见没见过」决定，与数值大小无关
- poll 时用数据库当前记录集合收缩 `seenIDs`，防止无限增长
- 运行中实测新通知 **0.02s** 检测到并弹预览

### 安装

1. 下载 `FlyIsland-1.0.3-macos-universal.zip`（Apple Silicon + Intel 通用），解压后把 `FlyIsland.app` 拖进「应用程序」
2. 首次打开被 Gatekeeper 拦：右键 → 打开 → 再点「打开」，或 `xattr -dr com.apple.quarantine /Applications/FlyIsland.app`
3. 授权：系统设置 → 隐私与安全性 → **完全磁盘访问权限** 与 **辅助功能** → 勾选 FlyIsland
4. 重启应用

> 从 v1.0.0+ 升级：覆盖安装即可，bundle id 不变，无需重新授权。

### 说明

- 最低系统：macOS 14.0
- ad-hoc 签名，未公证
- 通知与媒体走系统私有路径，系统升级后可能需要适配

SHA256（zip）见 Release 附件 `SHA256SUMS.txt`。
