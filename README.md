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

## mutter 补丁（本地 override 构建）

镜像不使用发行版直接提供的 mutter，而是由 [`files/scripts/override-mutter.sh`](files/scripts/override-mutter.sh) 在构建阶段下载 Fedora 的 mutter SRPM，打补丁后重新打包，装一个 `Release` 带 `.override.N` 后缀的本地包（`dnf` 会优先选它）。脚本由 [`recipes/recipes.yml`](recipes/recipes.yml) 的 `script` 模块调用。

当前携带两个补丁：

| 补丁 | 目的 | 上游引用 | 状态 |
| --- | --- | --- | --- |
| [`patches/mutter-mr5179.patch`](files/scripts/patches/mutter-mr5179.patch) | 分数缩放下的 offscreen effect 像素相位，以及 opaque region 的采样安全边界 | MR [!5179](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/5179)（4 个提交） | **未合并**，backport |
| [`patches/mutter-d5e397c2.patch`](files/scripts/patches/mutter-d5e397c2.patch) | **反向**应用 `shaped-texture: Disable blending for opaque regions`，恢复不透明区域的 blending | commit [`d5e397c2d4f5`](https://gitlab.gnome.org/GNOME/mutter/-/commit/d5e397c2d4f5c35b648fc52edfac2228127e89fd) | 上游已合入，我们主动回退 |

两个补丁在 RPM `%prep` 里按固定顺序应用：先 `!5179`，再 `-R d5e397c2`。顺序不能反——`!5179` 的补丁是针对未改动的 51.1 源码生成的，而 `-R` 的上下文来自 d5e397c2 合入后的源码。

### `mutter-mr5179.patch` 的来源

- 基线：mutter **51.1**（Fedora 45 / GNOME 51）
- 只取运行时代码：7 个文件、935 行，**丢弃** MR 的第 4 个提交（`tests/stage-view: Compare fractional offscreen rendering`），因为 Fedora 构建里的测试设施不保证和 MR 分支一致
- 生成方式：先把完整 MR diff 打到一份未改动的 51.1 上，再与原始源码 `diff -u` 出精确补丁，所以能通过 `--fuzz=0`（原始 MR diff 在 `clutter-offscreen-effect.c` 的 hunk #2 需要 fuzz 2，不能直接用）

重新生成的步骤：

```bash
curl -LO https://download.gnome.org/sources/mutter/51/mutter-51.1.tar.xz
tar -xJf mutter-51.1.tar.xz
curl -o mr.diff https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/5179.diff
# 1. 去掉 src/tests/ 相关的 diff 段
# 2. 把剩余部分打到 mutter-51.1 的副本上
# 3. 用 diff -u 生成精确补丁，并验证 patch -p1 --fuzz=0 能干净应用
```

### 失效与移除条件

- `!5179` 一旦合入 mutter 并随镜像使用的 mutter 版本发布，就删除该补丁、把 release 后缀改回 `.override`，同时确认发行版源码里已有 `sampling_opaque_region`。
- `d5e397c2` 的回退同理：等 `!5179` 合入后重新评估这个回退是否还需要保留。
- mutter 升版（51.2 / 52）时两个补丁都要 rebase。脚本在 `%prep` 里统一用 `--fuzz=0`，且构建后会断言「blend 行数为 0」和「`sampling_opaque_region` 必须出现」，所以补丁失配会让构建失败，而不是静默产出坏镜像。

### 排查

- 确认本地构建生效：`rpm -q mutter` 应显示 `51.1-1.fc45.override.2`（或更高的 `.override.N`）
- 如果 `dnf` 没选中本地包，检查 `Release` 后缀是否比已安装的版本大（同版本同后缀会被当成"已安装"而跳过）
- 需要临时改后缀时用 `MUTTER_OVERRIDE_REL=override.3 sudo bash files/scripts/override-mutter.sh`
