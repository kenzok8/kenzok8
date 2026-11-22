# 一键安装脚本

五个插件（clashoo、daede、honk、tower、usque）的统一安装入口：安装、卸载、升级、依赖补全都在这一个脚本里。以后各仓库的安装入口都会收敛到这里。

## 一键安装

在路由器上执行（需要 root）：

```sh
wget -O /tmp/onekey-install.sh https://cdn.jsdelivr.net/gh/kenzok8/kenzok8@main/scripts/install.sh \
  && ash /tmp/onekey-install.sh
```

没有 wget 时用 curl：

```sh
curl -fsSL https://cdn.jsdelivr.net/gh/kenzok8/kenzok8@main/scripts/install.sh \
  -o /tmp/onekey-install.sh && ash /tmp/onekey-install.sh
```

也可以管道执行并直接带子命令（无参数时进交互菜单，菜单同样可用）：

```sh
wget -O- https://cdn.jsdelivr.net/gh/kenzok8/kenzok8@main/scripts/install.sh \
  | ash -s install all
```

> 注意：jsDelivr 对 `@main` 有约 12 小时缓存。脚本刚更新后立刻拉到的可能是旧版，等缓存过期或用 commit 钉住版本。

## 交互菜单

```
===== kenzok8 插件一键安装 =====
  1. 安装 clashoo
  2. 安装 daede
  3. 安装 honk
  4. 安装 tower
  5. 安装 usque
  6. 自定义安装（多选/全选）
  7. 卸载（单选/多选/全选）
  8. 更新升级（单选/多选/全选）
  9. 查看已安装状态
  0. 退出
```

插件顺序一律按字母序。子界面（6/7/8）里可多选：输入编号或插件名，空格或逗号分隔，`a` 表示全部，`q` 返回。

## 子命令

```sh
ash install.sh install all              # 一键安装全部五个
ash install.sh install clashoo daede    # 安装指定插件（可多选，也可用编号 1 2）
ash install.sh install honk             # 单独安装一个
ash install.sh uninstall all            # 卸载全部（默认保留配置）
ash install.sh uninstall tower --purge  # 卸载并清理配置与状态
ash install.sh update all               # 升级全部已安装的插件
ash install.sh update daede             # 升级单个
ash install.sh list                     # 查看安装状态与版本
```

多选模式下单个插件失败不中断其余，结束时汇总成功 / 失败 / 跳过；退出码非 0 当且仅当有失败项。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `GH_PROXY` | `https://ghfast.top/` | GitHub 镜像前缀；设为空字符串则只直连 |
| `DAEDE_CORE` | `both` | daede 装哪个核心：`dae` / `daed` / `both` |
| `SKIP_BTF` | `0` | 设为 `1` 跳过 BTF 检查与补装 |
| `ONEKEY_PURGE_USQUE_ACCOUNT` | `0` | 设为 `1` 允许非交互下删除 usque 账号文件（见下） |

## 工作方式

- **软件源**：自动配置聚合源（`down.dllkids.xyz/openwrt-feed`），25.12 写 apk 源、24.10 写 opkg 源。配源时会先装源的签名公钥并按内置指纹校验（apk 与 opkg 的 key 分开处理），指纹不符直接停止，不会静默跳过。
- **clashoo / honk / tower**：走源安装。honk 有内核门：25.12 要求内核 6.12+，24.10 要求 6.6.40+（装 linux66 实验包，会明确提示），不满足直接报错不硬装；架构只限 x86_64 / aarch64 / arm。
- **daede**：走 daed 子源的 `manifest-daede.txt` 精确取包并做 SHA256 校验（聚合源里有同名异源的 dae/daed 包，裸按包名装可能选错）。manifest 不可用时退到包索引解析，再退到 GitHub 最新正式 Release。装前补 BTF 与 Geo 数据。
- **usque**：不在聚合源里，从 GitHub 最新正式 Release 取包，用 Release 自带的 `SHA256SUMS` 验 hash。MIPS 架构未经真机验收，会打印提示。
- **依赖**：主靠包管理器自动解析。脚本只补包管理器补不了的三类：Geo 数据、vmlinux-btf（按内核精确匹配，同系列可代，跨系列不装）、下载/校验工具。内核模块与运行内核不匹配时脚本无能为力，会明确报错（换固件或找同内核源），不尝试编译。
- **共存提醒**：clashoo / daede / honk 都是透明代理，同时安装没问题，但同时启用会抢流量入口；一次装两个以上时脚本会提醒只启用其中一个。

## 卸载

默认只删包、保留配置；`--purge` 才清理配置与状态：

- clashoo：核心删不掉时（例如 nikki 依赖它提供的 mihomo）保留配置，不做 purge 清理，避免破坏包管理器状态。
- daede：显式删 `luci-app-daede` + `dae` + `daed` 三个包，不留孤儿核心。
- usque：`/etc/usque/config.json` 含账号私钥，purge 前会二次确认；非交互下必须显式设 `ONEKEY_PURGE_USQUE_ACCOUNT=1` 才删，否则保留。

## 常见失败

| 现象 | 原因 / 处理 |
|---|---|
| `聚合源与 GitHub 均不可达` | 设备无网络，或两个上游都连不上；检查网络后再试 |
| `源公钥指纹与内置信任锚点不符` | 下载的公钥被篡改或源端已换 key；不要绕过，请反馈 |
| `honk 需要内核 6.12+` | 固件内核太旧，只能升级固件 |
| `BTF 未就绪` | 内核无内置 BTF 且无匹配的 vmlinux-btf 包；daede/honk 的核心起不来，请到 kenzok8/vmlinux-btf 反馈 |
| `Geo 数据补装失败` | daede 的地理规则可能无法工作，可在面板里手动更新 Geo 数据 |
| `/tmp 空间不足` | 脚本下载前会按包体积核对 /tmp 空间；清理后再试 |
| `聚合源里没有可用的架构索引` | 该 SDK + 架构组合源里没有包；核对 SDK 推断是否正确（自定义固件的版本号可能与上游脱钩） |

## 尚待定的行为（v1 现状）

以下几点 v1 先按括号里的行为实现，等用户拍板后再改：

1. honk 在 24.10 默认安装 linux66 实验包并明确提示（备选：默认跳过，需显式开启才装）。
2. BTF 装不上时警告并继续安装（备选：硬失败）。
3. daede 默认装双核（dae + daed）。
4. clashoo 不走 GitHub 回退（feed-only）。
5. usque 暂不接入聚合源，走 Release 资产安装。
6. 旧的各仓库 install.sh / uninstall.sh 暂不动，改 stub 与 README 替换另行安排。
