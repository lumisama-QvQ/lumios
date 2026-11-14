#!/usr/bin/env bash
# 安装 Papirus 图标主题，并生成 papirus-mixed 混合主题（环境变量见 AGENTS.md）。
set -euo pipefail

PAPIRUS_VERSION="${PAPIRUS_VERSION:-latest}"
# 网络失败时的兜底版本
PAPIRUS_FALLBACK_VERSION="20260801"
PAPIRUS_VARIANTS="${PAPIRUS_VARIANTS:-Papirus Papirus-Dark Papirus-Light}"
PAPIRUS_ICONS_DIR="${PAPIRUS_ICONS_DIR:-/usr/share/icons}"
MIXED_THEME_NAME="${MIXED_THEME_NAME:-papirus-mixed}"
MIXED_CATEGORIES="${MIXED_CATEGORIES:-apps mimetypes places}"
MIXED_THEME_TITLE="${MIXED_THEME_TITLE:-Papirus Mixed}"
MIXED_THEME_INHERITS="${MIXED_THEME_INHERITS:-Adwaita,hicolor}"

log() { printf '>>> [Papirus] %s\n' "$*"; }

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

resolve_latest_version() {
    local atom_file="${WORK_DIR}/tags.atom"
    local tag=""
    if curl -fsSL --retry 2 --retry-delay 2 -o "${atom_file}" \
        https://github.com/PapirusDevelopmentTeam/papirus-icon-theme/tags.atom; then
        tag="$(grep -m1 -oE '/releases/tag/[^"]+' "${atom_file}" | sed 's|.*/||' || true)"
    fi
    if [ -z "${tag}" ]; then
        printf '警告：无法解析 Papirus 最新 tag，回退到 %s\n' "${PAPIRUS_FALLBACK_VERSION}" >&2
        tag="${PAPIRUS_FALLBACK_VERSION}"
    fi
    printf '%s' "${tag}"
}

if [ "${PAPIRUS_VERSION}" = "latest" ]; then
    PAPIRUS_VERSION="$(resolve_latest_version)"
fi

TARBALL_URL="https://github.com/PapirusDevelopmentTeam/papirus-icon-theme/archive/refs/tags/${PAPIRUS_VERSION}.tar.gz"
SRC_DIR="papirus-icon-theme-${PAPIRUS_VERSION}"

log "下载 ${PAPIRUS_VERSION}"
curl -fsSL --retry 3 --retry-delay 2 -o "${WORK_DIR}/papirus.tar.gz" "${TARBALL_URL}"
mkdir -p "${WORK_DIR}/src"
tar -xzf "${WORK_DIR}/papirus.tar.gz" -C "${WORK_DIR}/src"
cd "${WORK_DIR}/src/${SRC_DIR}"

mkdir -p "${PAPIRUS_ICONS_DIR}"
for theme in ${PAPIRUS_VARIANTS}; do
    if [ ! -d "${theme}" ]; then
        printf '错误：上游源码包中没有主题 %s\n' "${theme}" >&2
        exit 1
    fi
    rm -rf "${PAPIRUS_ICONS_DIR:?}/${theme}"
    cp -a "${theme}" "${PAPIRUS_ICONS_DIR}/"
    log "已安装 ${theme}"
done

PAPIRUS_DIR="${PAPIRUS_ICONS_DIR}/Papirus"
THEME_DIR="${PAPIRUS_ICONS_DIR}/${MIXED_THEME_NAME}"
if [ ! -d "${PAPIRUS_DIR}" ]; then
    printf '错误：%s 不存在，PAPIRUS_VARIANTS 里必须包含 Papirus\n' "${PAPIRUS_DIR}" >&2
    exit 1
fi
if [ ! -f "${PAPIRUS_DIR}/index.theme" ]; then
    printf '错误：%s 缺少 index.theme，无法生成混合主题\n' "${PAPIRUS_DIR}" >&2
    exit 1
fi

rm -rf "${THEME_DIR:?}"
mkdir -p "${THEME_DIR}"

cd "${PAPIRUS_DIR}"
for size in */; do
    size="${size%/}"
    [ -d "${PAPIRUS_DIR}/${size}" ] || continue
    mkdir -p "${THEME_DIR}/${size}"
    for category in ${MIXED_CATEGORIES}; do
        if [ -d "${PAPIRUS_DIR}/${size}/${category}" ]; then
            ln -s "../../Papirus/${size}/${category}" "${THEME_DIR}/${size}/${category}"
        fi
    done
done

# index.theme 以 Papirus 的为底：Directories 等字段照抄，只改显示名和回退主题
cp "${PAPIRUS_DIR}/index.theme" "${THEME_DIR}/index.theme"
sed -i \
    -e "s|^Name=.*|Name=${MIXED_THEME_TITLE}|" \
    -e "s|^Inherits=.*|Inherits=${MIXED_THEME_INHERITS}|" \
    "${THEME_DIR}/index.theme"

# 保证GDM可读
chmod -R a+rX "${THEME_DIR}"
for theme in ${PAPIRUS_VARIANTS}; do
    chmod -R a+rX "${PAPIRUS_ICONS_DIR}/${theme}"
done

log "完成：已安装 ${PAPIRUS_VARIANTS}，混合主题 ${MIXED_THEME_NAME}（${MIXED_THEME_TITLE}，类别：${MIXED_CATEGORIES}，回退：${MIXED_THEME_INHERITS}）"
