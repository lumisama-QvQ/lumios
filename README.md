# lumios &nbsp; [![bluebuild build badge](https://github.com/lumisama-qvq/lumios/actions/workflows/build.yml/badge.svg)](https://github.com/lumisama-qvq/lumios/actions/workflows/build.yml)

See the [BlueBuild docs](https://blue-build.org/how-to/setup/) for quick setup instructions for setting up your own repository based on this template.

After setup, it is recommended you update this README to describe your custom image.

## Installation

> [!WARNING]  
> [This is an experimental feature](https://www.fedoraproject.org/wiki/Changes/OstreeNativeContainerStable), try at your own discretion.

To rebase an existing atomic Fedora installation to the latest build:

- First rebase to the unsigned image, to get the proper signing keys and policies installed:
  ```
  rpm-ostree rebase ostree-unverified-registry:ghcr.io/lumisama-qvq/lumios:latest
  ```
- Reboot to complete the rebase:
  ```
  systemctl reboot
  ```
- Then rebase to the signed image, like so:
  ```
  rpm-ostree rebase ostree-image-signed:docker://ghcr.io/lumisama-qvq/lumios:latest
  ```
- Reboot again to complete the installation
  ```
  systemctl reboot
  ```

The `latest` tag will automatically point to the latest build. That build will still always use the Fedora version specified in `recipe.yml`, so you won't get accidentally updated to the next major version.

## ISO

If build on Fedora Atomic, you can generate an offline ISO with the instructions available [here](https://blue-build.org/how-to/generate-iso/#_top). These ISOs cannot unfortunately be distributed on GitHub for free due to large sizes, so for public projects something else has to be used for hosting.

## Verification

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). You can verify the signature by downloading the `cosign.pub` file from this repo and running the following command:

```bash
cosign verify --key cosign.pub ghcr.io/lumisama-qvq/lumios
```

## mutter 补丁

镜像不使用发行版直接提供的 mutter，而是由 [`files/scripts/override-mutter.sh`](files/scripts/override-mutter.sh) 在构建阶段下载 Fedora 的 mutter SRPM，打补丁后重新打包。

当前携带两个补丁：

| 补丁 | 目的 | 上游引用 | 状态 |
| --- | --- | --- | --- |
| [`patches/mutter-mr5179.patch`](files/scripts/patches/mutter-mr5179.patch) | 分数缩放下的 offscreen effect 像素相位，以及 opaque region 的采样安全边界 | MR [!5179](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/5179)（4 个提交） | **未合并**，backport |
| [`patches/mutter-d5e397c2.patch`](files/scripts/patches/mutter-d5e397c2.patch) | **反向**应用 `shaped-texture: Disable blending for opaque regions`，恢复不透明区域的 blending | commit [`d5e397c2d4f5`](https://gitlab.gnome.org/GNOME/mutter/-/commit/d5e397c2d4f5c35b648fc52edfac2228127e89fd) | 上游已合入，我们主动回退 |

两个补丁在 RPM `%prep` 里按固定顺序应用， `!5179` 的补丁是针对未改动的 51.1 源码生成的，而 `-R` 的上下文来自 d5e397c2 合入后的源码。

### `mutter-mr5179.patch` 的来源

- 基线：mutter **51.1**（Fedora 45 / GNOME 51）
- 生成方式：先把完整 MR diff 打到一份未改动的 51.1 上，再与原始源码 `diff -u` 出精确补丁，所以能通过 `--fuzz=0`（原始 MR diff 在 `clutter-offscreen-effect.c` 的 hunk #2 需要 fuzz 2，不能直接用）

重新生成的步骤：

```bash
curl -LO https://download.gnome.org/sources/mutter/51/mutter-51.1.tar.xz
tar -xJf mutter-51.1.tar.xz
curl -o mr.diff https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/5179.diff
# 1. 去掉 src/tests/ 相关的 diff 段
# 2. 把剩余部分打到 mutter-51.1 的副本上
# 3. 用 diff -u 生成精确补丁
```
