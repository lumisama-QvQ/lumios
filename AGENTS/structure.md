# 仓库结构

| 路径 | 作用 |
| --- | --- |
| `recipes/recipes.yml` | 入口：dnf 移除包 → `override-mutter.sh` → `custom.yml` → signing |
| `recipes/custom.yml` | 软件包、Flatpak、GNOME 扩展、字体、构建脚本 |
| `files/scripts/` | 构建期脚本，按 recipe 中 `script` 模块的顺序执行 |
| `files/system/` | 覆盖到镜像根（systemd、dracut、LUKS 工具、akmods 证书） |
| `files/justfiles/` | `just` 命令 |
| `.github/workflows/build.yml` | 每日 06:00 UTC 构建，push/PR/手动触发 |
