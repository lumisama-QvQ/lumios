#!/usr/bin/env bash
# Gradia Capture —— GNOME Shell 的截图标注扩展
#   https://github.com/AlexanderVanhee/gradia-capture
#
# 它没有发布到 extensions.gnome.org，也没有 release 产物，所以 BlueBuild 的
# gnome-extensions 模块用不上（那个模块只从 extensions.gnome.org 拉）。
# 好在扩展是纯 JS，不需要构建，直接按 `gnome-extensions pack` 的布局落盘即可。
set -euxo pipefail

UUID="gradia-integration@alexandervanhee.github.io"
REPO="AlexanderVanhee/gradia-capture"
# 固定到具体提交，保证构建可复现；升级扩展时改这一行。
# 对应上游 2026-10-16 的 "Merge pull request #33 ... gnome-51"。
REF="0b7e47e1e5c1e68e234e4d2d24b307e1da1d18a9"

DEST="/usr/share/gnome-shell/extensions/${UUID}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> 下载 gradia-capture ${REF:0:12}"
curl -fsSL --retry 3 "https://codeload.github.com/${REPO}/tar.gz/${REF}" -o "$WORK/src.tar.gz"
tar -xzf "$WORK/src.tar.gz" -C "$WORK"
SRC="$(find "$WORK" -maxdepth 1 -mindepth 1 -type d | head -n1)"

# metadata.json 里的 shell-version 必须包含镜像中的 GNOME 版本，否则装上也加载不了
if command -v gnome-shell >/dev/null 2>&1; then
  GS_VER="$(gnome-shell --version | grep -o -E '[0-9]+' | head -n1)"
  if ! grep -q "\"${GS_VER}\"" "$SRC/src/metadata.json"; then
    echo "gradia-capture: 不支持 GNOME ${GS_VER}（metadata shell-version: $(grep -o '"shell-version":[^]]*]' "$SRC/src/metadata.json")）" >&2
    exit 1
  fi
  echo "==> GNOME ${GS_VER} 在支持列表内"
fi

echo "==> 安装到 ${DEST}"
install -d -m 0755 "$DEST"

# 扩展本体（里面已含 metadata.json / extension.js / stylesheet.css / LICENSE）
cp -a "$SRC/src/." "$DEST/"

# 图标：扩展里按 "icons/xxx.svg" 的相对路径引用，必须在扩展目录内
cp -a "$SRC/icons" "$DEST/icons"

[ -f "$SRC/README.md" ] && cp -a "$SRC/README.md" "$DEST/"

# gschema：全局目录（GNOME 默认查找位置）+ 扩展内目录（部分扩展硬编码这个路径）
install -d -m 0755 /usr/share/glib-2.0/schemas "$DEST/schemas"
install -m 0644 "$SRC"/schemas/*.gschema.xml /usr/share/glib-2.0/schemas/
cp -a "$SRC/schemas/." "$DEST/schemas/"
glib-compile-schemas /usr/share/glib-2.0/schemas
glib-compile-schemas "$DEST/schemas"

# 权限规范化（和 gnome-extensions 模块保持一致）
find "$DEST" -type d -exec chmod 0755 {} +
find "$DEST" -type f -exec chmod 0644 {} +

# 构建期自检：避免悄悄产出一个加载不了的镜像
test -f "$DEST/metadata.json"
test -f "$DEST/extension.js"
test -f "$DEST/schemas/gschemas.compiled"
echo "==> gradia-capture 已安装：$(find "$DEST" -type f | wc -l) 个文件"
