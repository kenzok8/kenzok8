<div align="center">

[![Typing SVG](https://readme-typing-svg.demolab.com?font=Fira+Code&weight=600&size=28&duration=3000&pause=1000&color=00FFFF&center=true&vCenter=true&width=600&lines=Hi%2C+I'm+kenzok8;OpenWrt+Package+Maintainer;mihomo+%C2%B7+sing-box+%C2%B7+dae;Feeds%2C+Firmware+%26+LuCI+Apps;10k%2B+Stars+Across+The+Feed)](https://git.io/typing-svg)

[![OpenWrt](https://img.shields.io/badge/OpenWrt-000000?style=for-the-badge&logo=openwrt&logoColor=00ffff)](https://openwrt.org/)
[![Shell](https://img.shields.io/badge/Shell-000000?style=for-the-badge&logo=gnubash&logoColor=00ffff)](https://www.gnu.org/software/bash/)
[![Lua](https://img.shields.io/badge/Lua-000000?style=for-the-badge&logo=lua&logoColor=00ffff)](https://www.lua.org/)
[![Go](https://img.shields.io/badge/Go-000000?style=for-the-badge&logo=go&logoColor=00ffff)](https://go.dev/)
[![C](https://img.shields.io/badge/C%2FC%2B%2B-000000?style=for-the-badge&logo=c&logoColor=ff9900)](https://en.cppreference.com/)

</div>

---

### `// THE_FEED`

> 一条从代理内核到路由器的完整流水线。每个仓库都能单独用 —— 合起来是闭环：

```text
fork ▶ collect ▶ gate ▶ build ▶ serve ▶ install
```

| Layer | Project | What it does | |
|:---|:---|:---|---:|
| Fork | [`wall`](https://github.com/kenzok8/wall) | 代理内核集合，所有修包的源头 | ![Stars](https://img.shields.io/github/stars/kenzok8/wall?style=flat-square&label=%E2%98%85&labelColor=0d1117&color=00ffff) |
| Collect | [`openwrt-packages`](https://github.com/kenzok8/openwrt-packages) | OpenWrt 常用软件包总集 | ![Stars](https://img.shields.io/github/stars/kenzok8/openwrt-packages?style=flat-square&label=%E2%98%85&labelColor=0d1117&color=00ffff) |
| Collect | [`small-package`](https://github.com/kenzok8/small-package) | 每日自动同步上游库软件 | ![Stars](https://img.shields.io/github/stars/kenzok8/small-package?style=flat-square&label=%E2%98%85&labelColor=0d1117&color=00ffff) |
| Collect | [`small`](https://github.com/kenzok8/small) | 精简分发源 — mihomo / sing-box / dae / passwall | ![Stars](https://img.shields.io/github/stars/kenzok8/small?style=flat-square&label=%E2%98%85&labelColor=0d1117&color=00ffff) |
| Gate | [`litte`](https://github.com/kenzok8/litte) | 双 SDK × 22 架构编译门禁，绿了才落 wall | ![Stars](https://img.shields.io/github/stars/kenzok8/litte?style=flat-square&label=%E2%98%85&labelColor=0d1117&color=00ffff) |
| Build | [`openwrt_Build`](https://github.com/kenzok8/openwrt_Build) | 一键多设备固件编译 | ![Stars](https://img.shields.io/github/stars/kenzok8/openwrt_Build?style=flat-square&label=%E2%98%85&labelColor=0d1117&color=00ffff) |
| Build | [`compile-package`](https://github.com/kenzok8/compile-package) | small-package 每日编译出 ipk / apk | ![Stars](https://img.shields.io/github/stars/kenzok8/compile-package?style=flat-square&label=%E2%98%85&labelColor=0d1117&color=00ffff) |
| Install | [`openwrt-clashoo`](https://github.com/kenzok8/openwrt-clashoo) | 开箱即用的 mihomo / sing-box LuCI 代理插件 | ![Stars](https://img.shields.io/github/stars/kenzok8/openwrt-clashoo?style=flat-square&label=%E2%98%85&labelColor=0d1117&color=00ffff) |
| Install | [`openwrt-daede`](https://github.com/kenzok8/openwrt-daede) | 基于 eBPF 的高性能透明代理 — dae / daed 后端 | ![Stars](https://img.shields.io/github/stars/kenzok8/openwrt-daede?style=flat-square&label=%E2%98%85&labelColor=0d1117&color=00ffff) |

> **Serve** — 编译产物与固件统一分发在 [`down.dllkids.xyz`](https://down.dllkids.xyz/)

---

### `// MODULES`

<details>
<summary><b>🛰️ PROXY_CORES</b> — 代理内核与源码维护</summary>
<br>

| Project | Description |
|:--------|:------------|
| [`trojan`](https://github.com/kenzok8/trojan) | Trojan 一键安装脚本 + trojan-go |
| [`trojan-go`](https://github.com/kenzok8/trojan-go) | Go 实现的 Trojan 代理，多路复用 / CDN 中转 |
| [`trojan-plus`](https://github.com/kenzok8/trojan-plus) | Trojan 的实验性增强分支 |
| [`dae`](https://github.com/kenzok8/dae) | 基于 eBPF 的 Linux 高性能透明代理 |
| [`quic-go`](https://github.com/kenzok8/quic-go) | quic-go 性能分支，dae 官方 go.mod 引用 |
| [`outbound`](https://github.com/kenzok8/outbound) | URL 驱动的代理出站库 |
| [`redsocks`](https://github.com/kenzok8/redsocks) | 任意 TCP/UDP 连接的透明重定向器 |
| [`dns2socks`](https://github.com/kenzok8/dns2socks) | DNS2SOCKS 的干净源码镜像 |
| [`pdnsd`](https://github.com/kenzok8/pdnsd) | 支持 TCP 查询的缓存 DNS 代理 |
| [`tcping`](https://github.com/kenzok8/tcping) | 测量 TCP 连接延迟 |
| [`v2dat`](https://github.com/kenzok8/v2dat) | 解包 v2ray geodata 数据 |
| [`simple-obfs`](https://github.com/kenzok8/simple-obfs) | 简易混淆插件 |
| [`shadowsocksr-libev`](https://github.com/kenzok8/shadowsocksr-libev) | SSR libev 实现 |
| [`ssocks`](https://github.com/kenzok8/ssocks) | sSocks 分支 |

</details>

<details>
<summary><b>🧱 FIRMWARE_TOOLING</b> — 固件编译与内核支持</summary>
<br>

| Project | Description |
|:--------|:------------|
| [`imagebuilder`](https://github.com/kenzok8/imagebuilder) | 带 BTF 内核的在线快速固件生成 |
| [`vmlinux-btf`](https://github.com/kenzok8/vmlinux-btf) | 给 OpenWrt 固件补内核 BTF，dae / daed 依赖 |
| [`Bulid_Wrt`](https://github.com/kenzok8/Bulid_Wrt) | OpenWrt 官方源码纯净编译 |
| [`gh-action-sdk`](https://github.com/kenzok8/gh-action-sdk) | 通过 SDK 构建软件包的 GitHub CI action |
| [`golang`](https://github.com/kenzok8/golang) | OpenWrt Go 编译环境 |
| [`ucl`](https://github.com/kenzok8/ucl) | UCL 1.03 无损压缩库镜像 |

</details>

<details>
<summary><b>🔄 AUTOMATION</b> — 每天自己跑的那部分</summary>
<br>

| Project | Description |
|:--------|:------------|
| [`AutoSync`](https://github.com/kenzok8/AutoSync) | 自动拉取上游、同步多个本地仓库 |
| [`Repo-Sync`](https://github.com/kenzok8/Repo-Sync) | 仓库间同步流水线 |
| [`jell`](https://github.com/kenzok8/jell) | 聚合软件源，small-package 的替代通道 |
| [`compile-jell`](https://github.com/kenzok8/compile-jell) | jell 仓库每日编译 |

</details>

<details>
<summary><b>🧩 LUCI_APPS</b> — 路由器上看得见的那一层</summary>
<br>

| Project | Description |
|:--------|:------------|
| [`openwrt-clashoo`](https://github.com/kenzok8/openwrt-clashoo) | 简洁稳定、开箱即用的 mihomo / sing-box 代理插件 |
| [`openwrt-daede`](https://github.com/kenzok8/openwrt-daede) | dae / daed 的 LuCI 前端，eBPF 透明代理 |
| [`luci-app-openclaw`](https://github.com/kenzok8/luci-app-openclaw) | OpenClaw for OpenWrt / ImmortalWrt |

</details>

---

<div align="center">

```
┌──────────────────────────────────────┐
│  FEED:  down.dllkids.xyz             │
└──────────────────────────────────────┘
```

</div>
