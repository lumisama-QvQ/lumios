#!/usr/bin/env bash
# Override Fedora's mutter with a locally rebuilt RPM that reverts
# upstream commit d5e397c2 ("shaped-texture: Disable blending for opaque regions").
#
# The official commit patch is vendored in patches/mutter-d5e397c2.patch and is
# applied in reverse (patch -R) during the RPM %prep stage. The resulting RPM
# gets a ".override" release suffix so dnf prefers it over the repository build.
#
# Environment:
#   MUTTER_KEEP_WORKDIR=1  keep the temporary build tree for inspection

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="${SCRIPT_DIR}/patches/mutter-d5e397c2.patch"
PATCH_NAME="mutter-d5e397c2.patch"
WORKDIR="$(mktemp -d /var/tmp/mutter-build.XXXXXX)"
KEEP_WORKDIR="${MUTTER_KEEP_WORKDIR:-0}"
BLEND_LINE='cogl_pipeline_set_blend (pipeline, "RGBA = ADD (SRC_COLOR, 0)", NULL);'

info() { echo "[mutter-override] $*"; }
die() { echo "[mutter-override] ERROR: $*" >&2; exit 1; }

cleanup() {
    if [[ "${KEEP_WORKDIR}" == "1" ]]; then
        info "Keeping work directory: ${WORKDIR}"
    else
        rm -rf "${WORKDIR}"
    fi
}
trap cleanup EXIT

[[ "$(id -u)" -eq 0 ]] || die "must run as root"
[[ -f "${PATCH_FILE}" ]] || die "patch not found: ${PATCH_FILE}"

info "Work directory: ${WORKDIR}"

##################################
# Build tooling
##################################
info "Installing build tooling"
dnf install -y --setopt=install_weak_deps=False \
    rpm-build redhat-rpm-config patch gcc gcc-c++ \
    meson ninja-build pkgconf-pkg-config

if ! dnf builddep --help >/dev/null 2>&1; then
    info "Installing dnf builddep plugin"
    dnf install -y dnf5-plugins || dnf install -y dnf-plugins-core
fi

##################################
# Source RPM
##################################
SRC_RPM=""
if rpm -q mutter >/dev/null 2>&1; then
    SOURCERPM="$(rpm -q --qf '%{SOURCERPM}' mutter)"
    SOURCE_SPEC="${SOURCERPM%.src.rpm}"
    info "Installed mutter source package: ${SOURCERPM}"
    if dnf download --srpm --destdir "${WORKDIR}" \
        --enablerepo=fedora-source,updates-source "${SOURCE_SPEC}"; then
        SRC_RPM="$(find "${WORKDIR}" -maxdepth 1 -name 'mutter-*.src.rpm' -print -quit)"
    fi
fi

if [[ -z "${SRC_RPM}" ]]; then
    info "Falling back to the latest mutter source RPM"
    rm -f "${WORKDIR}"/*.src.rpm
    dnf download --srpm --destdir "${WORKDIR}" \
        --enablerepo=fedora-source,updates-source mutter
    SRC_RPM="$(find "${WORKDIR}" -maxdepth 1 -name 'mutter-*.src.rpm' -print -quit)"
fi
[[ -n "${SRC_RPM}" ]] || die "could not download a mutter source RPM"
info "Using source RPM: $(basename "${SRC_RPM}")"

##################################
# Extract source
##################################
RPMBUILD_DIR="${WORKDIR}/rpmbuild"
mkdir -p "${RPMBUILD_DIR}"
rpm -i --define "_topdir ${RPMBUILD_DIR}" "${SRC_RPM}"

SPEC="${RPMBUILD_DIR}/SPECS/mutter.spec"
[[ -f "${SPEC}" ]] || die "mutter.spec not found in source RPM"
TARBALL="$(find "${RPMBUILD_DIR}/SOURCES" -maxdepth 1 -name 'mutter-*.tar.*' -print -quit)"
[[ -n "${TARBALL}" ]] || die "mutter source tarball not found"

# Preflight: the upstream source must still contain the two lines added by d5e397c2.
count="$(tar -xOf "${TARBALL}" --wildcards '*/src/compositor/meta-shaped-texture.c' \
    | grep -cF "${BLEND_LINE}" || true)"
if [[ "${count}" != "2" ]]; then
    die "expected 2 '${BLEND_LINE}' lines in mutter source, found ${count}; cannot reverse d5e397c2"
fi
info "Found 2 blend lines in upstream source (as expected)"

##################################
# Patch spec and reverse-apply
##################################
info "Patching mutter.spec"
cp "${PATCH_FILE}" "${RPMBUILD_DIR}/SOURCES/${PATCH_NAME}"

# Declare the patch as a Source so %%autosetup does not apply it forwards;
# it is applied explicitly with -R right after %%autosetup.
sed -i "/^Source0:/a Source1000:       ${PATCH_NAME}" "${SPEC}"
sed -i '/^%autosetup/a patch -R -p1 --fuzz=0 < %{SOURCE1000}' "${SPEC}"

# Bump the release so dnf treats the local build as newer than the repo package.
read -r SRC_VER SRC_REL < <(rpm -qp --qf '%{VERSION} %{RELEASE}\n' "${SRC_RPM}")
[[ -n "${SRC_VER}" && -n "${SRC_REL}" ]] || die "could not read source RPM version"
NEW_REL="${SRC_REL}.override"
sed -i "s/^Release:.*/Release:       ${NEW_REL}/" "${SPEC}"

grep -q "^Source1000:.*${PATCH_NAME}" "${SPEC}" || die "failed to add Source1000 to spec"
grep -q '^patch -R -p1 --fuzz=0 < %{SOURCE1000}' "${SPEC}" || die "failed to add reverse patch command to spec"
grep -q "^Release:.*${NEW_REL}" "${SPEC}" || die "failed to set release suffix"

info "Building mutter ${SRC_VER}-${NEW_REL}"

##################################
# Build
##################################
info "Installing BuildRequires (dnf builddep)"
dnf builddep -y --spec "${SPEC}"

info "Running rpmbuild"
rpmbuild -bb --noclean --define "_topdir ${RPMBUILD_DIR}" "${SPEC}"

# Post-build: confirm the reverse patch really removed both lines.
BUILD_SRC="$(find "${RPMBUILD_DIR}/BUILD" -path '*/src/compositor/meta-shaped-texture.c' -print -quit)"
[[ -n "${BUILD_SRC}" ]] || die "patched source file not found after build"
remaining="$(grep -cF "${BLEND_LINE}" "${BUILD_SRC}" || true)"
if [[ "${remaining}" != "0" ]]; then
    die "reverse patch did not remove blend lines; ${remaining} remaining in ${BUILD_SRC}"
fi
info "Reverse patch verified: blend lines removed from built source"

##################################
# Install override
##################################
MAIN_RPM="$(find "${RPMBUILD_DIR}/RPMS" -name 'mutter-[0-9]*.rpm' -print -quit)"
COMMON_RPM="$(find "${RPMBUILD_DIR}/RPMS" -name 'mutter-common-*.rpm' -print -quit)"
[[ -n "${MAIN_RPM}" && -n "${COMMON_RPM}" ]] || die "built mutter RPMs not found"

info "Installing $(basename "${MAIN_RPM}") and $(basename "${COMMON_RPM}")"
dnf install -y --nogpgcheck --setopt=install_weak_deps=False "${MAIN_RPM}" "${COMMON_RPM}"

installed="$(rpm -q --qf '%{VERSION}-%{RELEASE}' mutter)"
expected="${SRC_VER}-${NEW_REL}"
if [[ "${installed}" != "${expected}" ]]; then
    die "installed mutter is ${installed}, expected ${expected} (dnf may have chosen a repo package)"
fi
info "Installed mutter ${installed}"

dnf clean all >/dev/null 2>&1 || true
info "Done"
