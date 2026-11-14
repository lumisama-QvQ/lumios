# 仓库结构

| 路径 | 作用 |
| --- | --- |
| `recipes/recipes.yml` | 唯一配方：dnf 移除 → signing → `files/system` → mutter 重建 → 软件包 / 字体 / Flatpak / brew → GNOME 扩展与构建脚本 |
| `files/scripts/` | 构建期脚本，按配方中 `script` 模块的顺序执行 |
| `files/system/` | 覆盖到镜像根（systemd 单元与 `/etc` 配置、dracut、LUKS 工具、akmods 证书） |
| `files/justfiles/` | `just` 命令 |
| `.github/workflows/build.yml` | 每日 06:00 UTC 构建，push/PR/手动触发 |
