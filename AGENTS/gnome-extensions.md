# GNOME 扩展

`gradia-capture.sh`、`bazzar-companion` 都是源码安装：两者不在 extensions.gnome.org、也没有 release 产物，BlueBuild 的 `gnome-extensions` 模块用不上，因此按 `gnome-extensions pack` 的布局直接落盘。

- 两者都固定了上游 ref（脚本内的 `REF` / `BAZAAR_COMPANION_REF`），升级时改。
- schema 放两份：全局 `glib-2.0/schemas` 与扩展内 `schemas/`，后者是部分扩展硬编码的路径。
- Gradia Capture 依赖 Gradia 应用（Flatpak `be.alexandervanhee.gradia`）。
