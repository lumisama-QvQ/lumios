# lumios

个人自用的 Fedora Silverblue（NVIDIA 开源驱动）镜像，用 [BlueBuild](https://blue-build.org) 构建。

- 基座：`ghcr.io/blue-build/base-images/fedora-silverblue-nvidia-open`（Fedora 45）

## 切换到这个镜像

> 实验性功能，风险自负。

```bash
sudo bootc switch ghcr.io/lumisama-qvq/lumios:latest
systemctl reboot
```

## 包含什么

- **移除**：gnome-software、htop、nvtop、ibus-mozc、ibus-unikey
- **命令行**：fish、micro、smem、ibus-rime（含 librime-lua）、Homebrew
- **桌面**：gnome-tweaks、Clash Verge Rev（COPR）、Bibata 光标 / MoreWaita 图标
- **Flatpak**：Bazaar、Gear Lever、GNOME Calendar / FileRoller / TextEditor、Nautilus Previewer
- **GNOME 扩展**：Blur my Shell、Dash to Dock、Vitals、Caffeine、AppIndicator、Fuzzy App Search、User Themes、Legacy Theme Switcher，以及 Gradia Capture（源码安装，见 `files/scripts/gradia-capture.sh`）
- **字体**：Hack / FiraCode Nerd Font、Maple Mono NF CN、LXGW WenKai

## 特色修补

### mutter 重建（`files/scripts/override-mutter.sh`）

| 补丁                    | 作用                                   | 上游                                                                                                         | 状态                 |
| ----------------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------ | -------------------- |
| `mutter-mr5179.patch`   | 修复特定情况下字体渲染模糊问题         | MR [!5179](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/5179)                                      | **未合入**，backport |
| `mutter-d5e397c2.patch` | 修复2k等分辨率下分数缩放黑边的回归问题 | commit [`d5e397c2`](https://gitlab.gnome.org/GNOME/mutter/-/commit/d5e397c2d4f5c35b648fc52edfac2228127e89fd) | 已合入，主动回退     |

### Clash Verge 服务单元（`files/system/etc/systemd/system/clash-verge-service.service`）

clash-verge-rev自己生成的服务单元把 `After=network-online.target` 写死在模板里，而 `network-online.target` 要等 `NetworkManager-wait-online` 在现代电脑上较高的性能有时会导致gui比网络更早启动，app 判定 IPC 不可用，于是每次开机都要 pkexec 重装一遍服务。

根据[systemd#18154](https://github.com/systemd/systemd/issues/18154)，空赋值只重置普通列表，所以采取整份覆盖同名单元：

| 项          | 值                                  |
| ----------- | ----------------------------------- |
| `After=`    | `nftables.service iptables.service` |
| `ExecStart` | `/usr/bin/clash-verge-service`      |

### btrfs 透明压缩（`files/system/usr/libexec/lumios-fix-btrfs-compression`）

silverblue自43起存在透明压缩未预期启用的问题（[ostree#72](https://gitlab.com/fedora/ostree/sig/-/work_items/72)），但如今仍未修复

这里我们通过一个systemd的service服务来修复它

- `/proc/cmdline` 里没有 `compress=zstd` 时，用 `rpm-ostree kargs` 补 `rootflags=subvol=root,compress=zstd:1`；
- 注释掉 `/etc/fstab` 的 `/` btrfs 条目，解决systemd尝试重挂载的报错
- 首次允许服务时 `mount -o remount,compress=zstd:1 /var`使透明压缩立即生效

## 验证签名

```bash
cosign verify --key cosign.pub ghcr.io/lumisama-qvq/lumios
```
