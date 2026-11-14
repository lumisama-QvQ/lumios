#!/usr/bin/env bash
# 安装 Bibata 光标主题到 /usr/share/icons
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

    chmod -R a+rX "${DEST_DIR}/${variant}"

    rm -f "${archive}"
done

echo ">>> [Bibata] 安装完成：${VARIANTS}"
