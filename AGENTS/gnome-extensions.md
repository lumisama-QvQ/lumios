# GNOME 扩展

`gradia-capture.sh`、`bazzar-companion` 都是源码安装：两者不在 extensions.gnome.org、也没有 release 产物，BlueBuild 的 `gnome-extensions` 模块用不上，因此按 `gnome-extensions pack` 的布局直接落盘。

- 两者都跟随上游分支：`gradia-capture.sh` 用 `master`（`GRADIA_REF` 可改），`bazzar-companion` 用 `main`（`BAZAAR_COMPANION_REF` 可改）。
- gradia 会校验 `metadata.json` 的 `shell-version` 是否包含镜像的 GNOME 版本；跟随 master 后如果上游停掉 51，构建会直接失败，届时改 `GRADIA_REF` 回退到具体提交。
- schema 放两份：全局 `glib-2.0/schemas` 与扩展内 `schemas/`，后者是部分扩展硬编码的路径。
- Gradia Capture 依赖 Gradia 应用（Flatpak `be.alexandervanhee.gradia`）。
