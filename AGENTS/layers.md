# 分层与权重

BlueBuild 把每个 module 编译成一条 `RUN`，即 **一个 module = 一层**。配方按稳定性从高到低排列：越靠前越稳定、更新越少、依赖树越不易变，越靠后越容易变。

| 层 | 内容 | 更新频率 | 依赖变化 | 体积 |
| --- | --- | --- | --- | --- |
| L1 基线 | 移除包、signing、`files/system` | 极低 | 无 | 小 |
| L2 核心补丁 | `override-mutter.sh` 重建 mutter | 低（跟随 Fedora） | 小 | 中 |
| L3 系统软件 | libgda、librime-lua、ibus-rime、firefox-langpacks | 中 | 中 | 中 |
| L4 CLI | micro、fish、smem | 低 | 少 | 小 |
| L5 字体 | 固定 URL 的字体 | 低 | 无 | 大 |
| L6 固定版本资源 | bibata（pin tag）、gradia（pin commit） | 低 | 无 | 小 |
| L7 桌面软件 | COPR：gnome-tweaks、morewaita、clash-verge-rev | 中高 | 中 | 大 |
| L8 在线最新 | EGO 扩展、papirus（latest）、bazzar（main）、1Password（latest） | 高 | 少 | 中 |
| L9 Flatpak | 系统 Flatpak | 中高 | 无 | 大 |
| L10 工具链 | Homebrew（auto-upgrade） | 每次构建 | 中 | 最大 |

## 排序约束

- 移除类 dnf 排在所有安装之前，否则会先装再卸。
- `override-mutter.sh` 排在 dnf 安装之前：它装的 mutter release 号更高，后续 dnf 不会覆盖。
- 越靠后变化，升级时只需下载尾部少数层，L1–L5 通常整层复用。

## 没开 `use_cache` 的原因

`use_cache` 按 RUN 文本命中缓存，而 dnf、`gnome-extensions`、`latest`/`main` 类脚本的 RUN 文本不变；开启后这些模块会一直复用旧结果，需要给它们逐个加 `no-cache: true`，等于放弃收益。

想进一步缩小更新体积，可以用 action 的 `build_chunked_oci` / `chunkah`：按内容分块，比按 module 分层更细，代价是构建更慢。
