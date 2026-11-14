# 内核与签名

## `legion-fix.sh`

安装 Legion Pro 7/7i Gen 10 的补丁内核与 aw88399 / mt7927 固件，删除 stock 内核（ostree 要求 `/usr/lib/modules` 只保留一个内核目录），并装 `kernel-devel` 供 NVIDIA kmod 编译。必须在其它模块之前执行。

环境变量：`LEGION_KERNEL_REPO`、`LEGION_KERNEL_BRANCH`、`LEGION_KERNEL_TAG`、`LEGION_DRY_RUN=1`。

当前未在 `recipes/` 中引用，保留备用。

## `sign-check.sh` / `signmodules.sh`

来自 Universal Blue / secureblue（Apache-2.0，保留许可证头）。私钥由 CI 从 `KERNEL_SIGNING_SECRET`（base64 的 `MOK.priv`）写入仓库根；未配置时跳过签名，镜像仍可构建但需关闭 Secure Boot。

当前未在 `recipes/` 中引用，保留备用。
