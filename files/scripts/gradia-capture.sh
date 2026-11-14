#!/usr/bin/env bash
# 安装 Gradia Capture（GNOME 扩展），说明见 AGENTS.md。
set -euxo pipefail

UUID="gradia-integration@alexandervanhee.github.io"
REPO="AlexanderVanhee/gradia-capture"
# 固定提交
REF="0b7e47e1e5c1e68e234e4d2d24b307e1da1d18a9"

DEST="/usr/share/gnome-shell/extensions/${UUID}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> 下载 gradia-capture ${REF:0:12}"
curl -fsSL --retry 3 "https://codeload.github.com/${REPO}/tar.gz/${REF}" -o "$WORK/src.tar.gz"
tar -xzf "$WORK/src.tar.gz" -C "$WORK"
SRC="$(find "$WORK" -maxdepth 1 -mindepth 1 -type d | head -n1)"

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

cp -a "$SRC/src/." "$DEST/"
cp -a "$SRC/icons" "$DEST/icons"

[ -f "$SRC/README.md" ] && cp -a "$SRC/README.md" "$DEST/"

install -d -m 0755 /usr/share/glib-2.0/schemas "$DEST/schemas"
install -m 0644 "$SRC"/schemas/*.gschema.xml /usr/share/glib-2.0/schemas/
cp -a "$SRC/schemas/." "$DEST/schemas/"
glib-compile-schemas /usr/share/glib-2.0/schemas
glib-compile-schemas "$DEST/schemas"

find "$DEST" -type d -exec chmod 0755 {} +
find "$DEST" -type f -exec chmod 0644 {} +

test -f "$DEST/metadata.json"
test -f "$DEST/extension.js"
test -f "$DEST/schemas/gschemas.compiled"
echo "==> gradia-capture 已安装：$(find "$DEST" -type f | wc -l) 个文件"
