#!/usr/bin/env bash
# =============================================================================
# catppuccin-cursors.sh - 在镜像构建时安装 Catppuccin 光标主题到系统图标目录
#
# 数据来源: https://github.com/catppuccin/cursors
# 安装位置: /usr/share/icons/catppuccin-<flavor>-<accent>-cursors
#
# 默认安装 catppuccin-mocha-mauve-cursors。可用环境变量覆盖：
#   CATPPUCCIN_VERSION - 发布版本 tag（默认 v2.0.0）
#   CATPPUCCIN_FLAVORS - flavor 列表（空格或逗号分隔，或 all）：
#                        latte frappe macchiato mocha
#   CATPPUCCIN_ACCENTS - accent 列表（空格或逗号分隔，或 all）：
#                        blue dark flamingo green lavender light maroon mauve
#                        peach pink red rosewater sapphire sky teal yellow
#   CURSOR_DEST_DIR    - 安装目录（默认 /usr/share/icons）
#
# 示例：安装 mocha 的 dark / light / mauve 三套主题
#   CATPPUCCIN_FLAVORS="mocha" CATPPUCCIN_ACCENTS="dark light mauve" \
#       ./catppuccin-cursors.sh
# =============================================================================
set -euo pipefail

REPO="catppuccin/cursors"
VERSION="${CATPPUCCIN_VERSION:-v2.0.0}"
FLAVORS="${CATPPUCCIN_FLAVORS:-mocha}"
ACCENTS="${CATPPUCCIN_ACCENTS:-mauve}"
DEST_DIR="${CURSOR_DEST_DIR:-/usr/share/icons}"

ALL_FLAVORS="latte frappe macchiato mocha"
ALL_ACCENTS="blue dark flamingo green lavender light maroon mauve peach pink red rosewater sapphire sky teal yellow"

# 把逗号分隔统一成空格，并把 all 展开成完整列表
normalize_list() { # <列表> <全量列表>
    local list="${1//,/ }"
    local all="$2"
    if [[ " ${list} " == *" all "* ]]; then
        list="${all}"
    fi
    echo "${list}"
}

FLAVORS="$(normalize_list "${FLAVORS}" "${ALL_FLAVORS}")"
ACCENTS="$(normalize_list "${ACCENTS}" "${ALL_ACCENTS}")"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# 发行版自带解压工具不一定齐全，按可用性依次尝试
extract_zip() { # <zip 文件> <目标目录>
    local zip="$1" dest="$2"
    if command -v bsdtar > /dev/null 2>&1; then
        bsdtar -xf "${zip}" -C "${dest}"
    elif command -v unzip > /dev/null 2>&1; then
        unzip -q -o "${zip}" -d "${dest}"
    elif command -v python3 > /dev/null 2>&1; then
        python3 -m zipfile -e "${zip}" "${dest}"
    else
        echo "ERROR: 找不到解压工具（需要 bsdtar、unzip 或 python3 之一）" >&2
        exit 1
    fi
}

echo ">>> [Catppuccin] 版本 ${VERSION}，安装到 ${DEST_DIR}"
install -d -m 0755 "${DEST_DIR}"

for flavor in ${FLAVORS}; do
    for accent in ${ACCENTS}; do
        theme="catppuccin-${flavor}-${accent}-cursors"
        url="https://github.com/${REPO}/releases/download/${VERSION}/${theme}.zip"
        archive="${TMP_DIR}/${theme}.zip"

        echo ">>> [Catppuccin] 下载 ${theme}（${VERSION}）"
        curl -fsSL --retry 3 --retry-delay 2 -o "${archive}" "${url}"

        echo ">>> [Catppuccin] 解压 ${theme} -> ${DEST_DIR}/${theme}"
        rm -rf "${DEST_DIR:?}/${theme}"
        extract_zip "${archive}" "${DEST_DIR}"

        if [[ ! -f "${DEST_DIR}/${theme}/index.theme" ]]; then
            echo "ERROR: ${theme} 安装后缺少 index.theme" >&2
            exit 1
        fi

        chmod -R a+rX "${DEST_DIR}/${theme}"

        rm -f "${archive}"
    done
done

echo ">>> [Catppuccin] 安装完成：flavor=${FLAVORS} accent=${ACCENTS}"
