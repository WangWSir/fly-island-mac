## Fly Island for Mac v1.0.2

新行为：**通知列表与系统通知中心保持一致**。

### 变化

之前 FlyIsland 的通知列表只增不减，即使在系统通知中心点了「清空」，这边的历史也还在。

现在每次拉取都会与系统通知数据库对账：

- 通知中心被**清空** → FlyIsland 列表同步清空（实测 < 1s）
- 单条通知被划掉 → 对应条目同步消失
- 列表只保留**最近 7 天**的记录（数据库里常年积累的守护进程残留不再出现）
- 新通知到达不受影响（横幅通道 0.3s 预览、数据库通道 0.02s 检测，均实测）

### 原理

系统通知中心「清空」时会把 `usernoted` 数据库里对应的 `record` 行删掉，所以以数据库当前内容为准做对账，即可与右侧的通知中心保持一致；7 天保留期用于过滤数据库中不会过期、但也不在通知中心展示的老记录。

### 安装

1. 下载 `FlyIsland-1.0.2-macos-universal.zip`（Apple Silicon + Intel 通用），解压后把 `FlyIsland.app` 拖进「应用程序」
2. 首次打开被 Gatekeeper 拦：右键 → 打开 → 再点「打开」，或 `xattr -dr com.apple.quarantine /Applications/FlyIsland.app`
3. 授权：系统设置 → 隐私与安全性 → **完全磁盘访问权限** 与 **辅助功能** → 勾选 FlyIsland
4. 重启应用

> 从 v1.0.0 / v1.0.1 升级：覆盖安装即可，bundle id 不变，**无需重新授权**。

### 说明

- 最低系统：macOS 14.0
- ad-hoc 签名，未公证
- 通知与媒体走系统私有路径（`usernoted`、`MediaRemote`、通知中心 AX 树），系统升级后可能需要适配

SHA256（zip）见 Release 附件 `SHA256SUMS.txt`。
