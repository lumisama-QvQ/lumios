#!/usr/bin/env bash
# =============================================================================
# bibata-cursors.sh - 在镜像构建时安装 Bibata 光标主题到系统图标目录
#
# 数据来源: https://github.com/ful1e5/Bibata_Cursor
# 安装位置: /usr/share/icons/<主题名>
#
# 默认安装 Bibata-Modern-Ice（白色、圆角）。可用环境变量覆盖：
#   BIBATA_VERSION  - 发布版本 tag（默认 v2.0.7）
#   BIBATA_VARIANTS - 空格分隔的主题名列表，例如：
#                     "Bibata-Modern-Ice Bibata-Original-Ice"
#                     右手版本在名称后加 -Right，例如 Bibata-Modern-Ice-Right
#   CURSOR_DEST_DIR - 安装目录（默认 /usr/share/icons）
# =============================================================================
set -euo pipefail

REPO="ful1e5/Bibata_Cursor"
VERSION="${BIBATA_VERSION:-v2.0.7}"
VARIANTS="${BIBATA_VARIANTS:-Bibata-Modern-Ice}"
DEST_DIR="${CURSOR_DEST_DIR:-/usr/share/icons}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo ">>> [Bibata] 版本 ${VERSION}，安装到 ${DEST_DIR}"
install -d -m 0755 "${DEST_DIR}"

for variant in ${VARIANTS}; do
    url="https://github.com/${REPO}/releases/download/${VERSION}/${variant}.tar.xz"
    archive="${TMP_DIR}/${variant}.tar.xz"

    echo ">>> [Bibata] 下载 ${variant}（${VERSION}）"
    curl -fsSL --retry 3 --retry-delay 2 -o "${archive}" "${url}"

    echo ">>> [Bibata] 解压 ${variant} -> ${DEST_DIR}/${variant}"
    rm -rf "${DEST_DIR:?}/${variant}"
    tar -xJf "${archive}" -C "${DEST_DIR}"

    if [[ ! -f "${DEST_DIR}/${variant}/index.theme" ]]; then
        echo "ERROR: ${variant} 安装后缺少 index.theme" >&2
        exit 1
    fi

    # 光标文件必须对所有用户可读，否则登录屏/其他用户无法使用
    chmod -R a+rX "${DEST_DIR}/${variant}"

    rm -f "${archive}"
done

echo ">>> [Bibata] 安装完成：${VARIANTS}"
