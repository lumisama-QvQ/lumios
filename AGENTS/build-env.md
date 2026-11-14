# 构建环境

底座是 bootc（Fedora 45 / GNOME 51），以下约束来自踩坑：

1. 构建期 `rpm-ostree install` 不可用，一律用 `dnf`。
2. 构建容器里对 `/etc/group`、`/etc/passwd` 的改动不会进入镜像；运行时需要的组/用户必须写 `sysusers.d` / `tmpfiles.d`。
3. 运行中的系统 `/usr` 只读，属组/权限修复只能放在构建期。
4. 系统级 GNOME 扩展装完默认禁用，需要用户手动启用。

## 本地验证

- 构建期脚本不能在本机直接跑；纯下载/落盘类可把目标路径换到 `/tmp` 后 dry-run。
- 改完脚本跑 `bash -n`，改完 YAML 确认缩进与列表结构。
