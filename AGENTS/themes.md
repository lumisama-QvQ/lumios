# 光标 / 图标主题

`bibata-cursors.sh`、`papirus-icons.sh`。

- `papirus-icons.sh` 会额外生成 `papirus-mixed`：只软链 apps/mimetypes/places，`index.theme` 以 Papirus 为底改显示名与 Inherits。
- 文件权限要对所有用户可读，GDM / 登录屏也要用。

环境变量（脚本里都有 `:-` 默认值）：

- Bibata：`BIBATA_VERSION`、`BIBATA_VARIANTS`、`CURSOR_DEST_DIR`
- Papirus：`PAPIRUS_VERSION`、`PAPIRUS_FALLBACK_VERSION`、`PAPIRUS_VARIANTS`、`PAPIRUS_ICONS_DIR`、`MIXED_THEME_NAME`、`MIXED_CATEGORIES`、`MIXED_THEME_TITLE`、`MIXED_THEME_INHERITS`
