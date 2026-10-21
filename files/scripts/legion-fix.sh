#!/usr/bin/env bash
# =============================================================================
# legion-fix.sh —— 构建期安装 Legion Pro 7/7i Gen 10 的补丁内核 + 固件
#
# 执行时机：BlueBuild recipes.yml 顶部（任何其它模块之前）。
# 做的事：
#   1. 安装 aw88399（smart amp）与 mt7927（Wi-Fi/BT）固件，逐个校验上游 sha256；
#   2. 下载上游最新 release 的补丁内核 RPM 包（校验 sha256）；
#   3. 删除镜像中的 stock 内核（bootc/ostree 要求 /usr/lib/modules 下只保留一个内核目录）；
#   4. 安装补丁内核 + kernel-devel（供后续 installnvidia.sh 编译 NVIDIA kmod）。
#
# 可配环境变量：
#   LEGION_KERNEL_TAG   固定上游 release tag（默认自动解析最新，如 kernel-7.2.11-200.legion.fc44）
#   LEGION_KERNEL_REPO  上游仓库（默认 marco-giunta/legion-pro7-gen10-audio）
#   LEGION_DRY_RUN=1    只下载/校验/解包并打印 dnf 计划，不写 /usr、不执行 dnf（本地测试用）
# =============================================================================
set -euo pipefail

LEGION_KERNEL_REPO="${LEGION_KERNEL_REPO:-marco-giunta/legion-pro7-gen10-audio}"
LEGION_KERNEL_BRANCH="${LEGION_KERNEL_BRANCH:-legion_audio}"
LEGION_KERNEL_TAG="${LEGION_KERNEL_TAG:-}"
DRY_RUN="${LEGION_DRY_RUN:-0}"
RAW_BASE="https://raw.githubusercontent.com/${LEGION_KERNEL_REPO}/${LEGION_KERNEL_BRANCH}"

# 固件
FW_AW_DIR_URL="${RAW_BASE}/firmware/aw88399"
FW_AW_DEST="/usr/lib/firmware/aw88399_acf.bin"
FW_MT_BASE_URL="${RAW_BASE}/firmware/mt7927"
FW_MT_DIR="/usr/lib/firmware/mediatek/mt7927"
FW_MT_FILES=(
    "WIFI_MT6639_PATCH_MCU_2_1_hdr.bin"
    "WIFI_RAM_CODE_MT6639_2_1.bin"
    "BT_RAM_CODE_MT6639_2_1_hdr.bin"
)
# Wi-Fi 固件若系统已带 linux-firmware 的官方 .xz，则优先使用官方版本（1=允许官方压缩版）
FW_MT_OFFICIAL_XZ=(1 1 0)

WORKDIR="$(mktemp -d /tmp/legion-fix.XXXXXX)"
trap 'rm -rf "${WORKDIR}"' EXIT

info() { echo "[legion] $*"; }
warn() { echo "[legion][WARN] $*" >&2; }
die()  { echo "[legion][ERR] $*" >&2; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

for cmd in curl tar sha256sum rpm dnf find; do
    require_cmd "${cmd}"
done

download() {
    # download <url> <输出文件>
    curl -fsSL --retry 3 --retry-delay 2 -o "$2" "$1" \
        || die "下载失败：$1"
}

verify_sha256() {
    # verify_sha256 <sha256文件> <待校验文件>
    local sha_file="$1" target="$2" expected actual
    expected="$(awk 'NR==1 {print $1}' "${sha_file}")"
    [[ -n "${expected}" ]] || die "无法解析 sha256 文件：${sha_file}"
    actual="$(sha256sum "${target}" | awk '{print $1}')"
    [[ "${actual}" == "${expected}" ]] \
        || die "sha256 校验失败：$(basename "${target}")"
}

resolve_kernel_tag() {
    if [[ -n "${LEGION_KERNEL_TAG}" ]]; then
        echo "${LEGION_KERNEL_TAG}"
        return 0
    fi
    local tag
    tag="$(curl -fsSI "https://github.com/${LEGION_KERNEL_REPO}/releases/latest" 2>/dev/null \
        | sed -n 's|^[Ll]ocation: .*/tag/||p' \
        | tr -d '\r' \
        | head -n1)"
    [[ -n "${tag}" ]] \
        || die "无法解析上游最新 release tag（可用 LEGION_KERNEL_TAG 手动指定）"
    echo "${tag}"
}

install_firmware() {
    info "安装固件"

    # --- aw88399 smart amp ---
    local tmp_bin="${WORKDIR}/aw88399_acf.bin"
    local tmp_sha="${WORKDIR}/aw88399_acf.bin.sha256"
    info "下载 aw88399 固件"
    download "${FW_AW_DIR_URL}/aw88399_acf.bin" "${tmp_bin}"
    download "${FW_AW_DIR_URL}/aw88399_acf.bin.sha256" "${tmp_sha}"
    verify_sha256 "${tmp_sha}" "${tmp_bin}"
    if [[ "${DRY_RUN}" == "1" ]]; then
        info "[dry-run] 将安装 ${FW_AW_DEST}"
    else
        install -D -m 0644 "${tmp_bin}" "${FW_AW_DEST}"
        info "已安装 ${FW_AW_DEST}"
    fi

    # --- mt7927 Wi-Fi / BT ---
    local i=0 name dest allow_official_xz
    for name in "${FW_MT_FILES[@]}"; do
        dest="${FW_MT_DIR}/${name}"
        allow_official_xz="${FW_MT_OFFICIAL_XZ[$i]}"
        i=$((i + 1))

        if [[ "${allow_official_xz}" == "1" && -f "${dest}.xz" ]]; then
            info "${name}: 系统已有官方 ${name}.xz，优先使用官方压缩固件（跳过）"
            if [[ "${DRY_RUN}" != "1" && -f "${dest}" ]]; then
                rm -f "${dest}"
                info "已移除旧的未压缩副本 ${dest}"
            fi
            continue
        fi

        tmp_bin="${WORKDIR}/${name}"
        tmp_sha="${WORKDIR}/${name}.sha256"
        info "下载 ${name}"
        download "${FW_MT_BASE_URL}/${name}" "${tmp_bin}"
        download "${FW_MT_BASE_URL}/${name}.sha256" "${tmp_sha}"
        verify_sha256 "${tmp_sha}" "${tmp_bin}"
        if [[ "${DRY_RUN}" == "1" ]]; then
            info "[dry-run] 将安装 ${dest}"
        else
            install -D -m 0644 "${tmp_bin}" "${dest}"
            info "已安装 ${dest}"
        fi
    done
}

remove_stock_kernels() {
    local target="$1" pkg ver remove_pkgs=() d

    for pkg in kernel kernel-core kernel-modules kernel-modules-core \
        kernel-modules-extra kernel-modules-extra-matched kernel-modules-internal \
        kernel-devel kernel-devel-matched; do
        # 同一包名可能装了多个版本（installonly），必须逐行读取
        while IFS= read -r ver; do
            [[ -n "${ver}" ]] || continue
            [[ "${ver}" == "${target}" ]] && continue
            remove_pkgs+=("${pkg}-${ver}")
        done < <(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' "${pkg}" 2>/dev/null || true)
    done

    if [[ ${#remove_pkgs[@]} -gt 0 ]]; then
        info "删除 stock 内核：${remove_pkgs[*]}"
        if [[ "${DRY_RUN}" == "1" ]]; then
            info "[dry-run] dnf -y remove --no-autoremove ${remove_pkgs[*]}"
        else
            dnf -y remove --no-autoremove "${remove_pkgs[@]}"
        fi
    else
        info "没有需要删除的 stock 内核包"
    fi

    if [[ "${DRY_RUN}" != "1" ]]; then
        for d in /usr/lib/modules/*/; do
            [[ -d "${d}" ]] || continue
            if [[ "$(basename "${d}")" != "${target}" ]]; then
                warn "移除残留内核目录 ${d}"
                rm -rf "${d}"
            fi
        done
    fi
}

verify_kernel_install() {
    local target="$1" installed dirs=() d

    installed="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core 2>/dev/null || true)"
    [[ "${installed}" == "${target}" ]] \
        || die "kernel-core 版本不符：${installed:-<未安装>} != ${target}"

    shopt -s nullglob
    for d in /usr/lib/modules/*/; do
        dirs+=("${d}")
    done
    shopt -u nullglob

    [[ ${#dirs[@]} -eq 1 ]] \
        || die "/usr/lib/modules 下应只有 1 个内核目录，实际 ${#dirs[@]} 个"
    [[ "$(basename "${dirs[0]}")" == "${target}" ]] \
        || die "内核目录 ${dirs[0]} 与目标内核 ${target} 不一致"
    [[ -f "${dirs[0]}vmlinuz" ]] || die "缺少 ${dirs[0]}vmlinuz"

    if [[ -d "/usr/src/kernels/${target}" ]]; then
        info "kernel-devel 已就位：/usr/src/kernels/${target}"
    else
        warn "/usr/src/kernels/${target} 不存在，后续 NVIDIA 编译可能回退到 Fedora 的 kernel-devel"
    fi

    info "内核安装校验通过：${target}"
}

main() {
    [[ "$(uname -m)" == "x86_64" ]] \
        || die "补丁内核仅支持 x86_64（当前架构：$(uname -m)）"

    local fedora_ver tag asset url core_rpm devel_rpm rpm_dir target

    fedora_ver="$(rpm -E '%fedora')"
    tag="$(resolve_kernel_tag)"
    [[ "${tag}" == *"fc${fedora_ver}"* ]] \
        || die "最新 release ${tag} 不是 Fedora ${fedora_ver} 的构建；请等待上游发布，或用 LEGION_KERNEL_TAG 指定"

    asset="legion-pro7-audio-${tag#kernel-}.tar.gz"
    url="https://github.com/${LEGION_KERNEL_REPO}/releases/download/${tag}/${asset}"

    info "补丁内核 release：${tag}"
    info "下载 ${asset}（约 200 MB）"
    download "${url}" "${WORKDIR}/${asset}"
    download "${url}.sha256" "${WORKDIR}/${asset}.sha256"
    verify_sha256 "${WORKDIR}/${asset}.sha256" "${WORKDIR}/${asset}"

    info "解压内核 RPM"
    mkdir -p "${WORKDIR}/rpms"
    tar xzf "${WORKDIR}/${asset}" -C "${WORKDIR}/rpms"

    core_rpm="$(find "${WORKDIR}/rpms" -name 'kernel-core-*.rpm' -print -quit)"
    [[ -n "${core_rpm}" ]] || die "压缩包中找不到 kernel-core RPM"
    rpm_dir="$(dirname "${core_rpm}")"
    target="$(rpm -qp --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "${core_rpm}")"
    [[ -n "${target}" ]] || die "无法读取补丁内核版本"
    info "目标内核：${target}"

    devel_rpm="$(find "${WORKDIR}/rpms" -name 'kernel-devel-[0-9]*.rpm' -print -quit)"
    [[ -n "${devel_rpm}" ]] || warn "压缩包中没有 kernel-devel RPM"

    install_firmware
    remove_stock_kernels "${target}"

    if [[ "${DRY_RUN}" == "1" ]]; then
        info "[dry-run] 将执行：dnf -y install --nogpgcheck --setopt=install_weak_deps=False \\"
        info "[dry-run]     ${rpm_dir}/kernel-[0-9]*.rpm ${rpm_dir}/kernel-core-*.rpm \\"
        info "[dry-run]     ${rpm_dir}/kernel-modules*.rpm ${rpm_dir}/kernel-devel*.rpm"
        info "[dry-run] 完成：下载/校验/解包均成功，未修改系统"
        exit 0
    fi

    info "安装补丁内核 RPM"
    dnf -y install --nogpgcheck --setopt=install_weak_deps=False \
        "${rpm_dir}"/kernel-[0-9]*.rpm \
        "${rpm_dir}"/kernel-core-*.rpm \
        "${rpm_dir}"/kernel-modules*.rpm \
        "${rpm_dir}"/kernel-devel*.rpm

    verify_kernel_install "${target}"
    info "legion 补丁内核安装完成"
}

main "$@"
