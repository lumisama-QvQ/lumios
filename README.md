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
- **桌面**：gnome-tweaks、Clash Verge Rev（COPR）、Bibata 光标 / Papirus 图标主题
- **Flatpak**：Bazaar、Gear Lever、GNOME Calendar / FileRoller / TextEditor、Nautilus Previewer
- **GNOME 扩展**：Blur my Shell、Dash to Dock、Vitals、Caffeine、AppIndicator、Fuzzy App Search、User Themes、Legacy Theme Switcher，以及 Gradia Capture（源码安装，见 `files/scripts/gradia-capture.sh`）
- **字体**：Hack / FiraCode Nerd Font、Maple Mono NF CN、LXGW WenKai

## 特色

### mutter 重建（`files/scripts/override-mutter.sh`）

| 补丁                    | 作用                                   | 上游                                                                                                         | 状态                 |
| ----------------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------ | -------------------- |
| `mutter-mr5179.patch`   | 修复特定情况下字体渲染模糊问题         | MR [!5179](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/5179)                                      | **未合入**，backport |
| `mutter-d5e397c2.patch` | 修复2k等分辨率下分数缩放黑边的回归问题 | commit [`d5e397c2`](https://gitlab.gnome.org/GNOME/mutter/-/commit/d5e397c2d4f5c35b648fc52edfac2228127e89fd) | 已合入，主动回退     |

## 验证签名

```bash
cosign verify --key cosign.pub ghcr.io/lumisama-qvq/lumios
```
