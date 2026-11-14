#!/usr/bin/env bash
# Override Fedora's mutter with a locally rebuilt RPM that carries two patches:
#
#   1. patches/mutter-mr5179.patch   — backport of upstream merge request !5179
#      ("clutter/offscreen-effect: Preserve framebuffer pixel phase at
#      fractional scales"). Still UNMERGED upstream; runtime part only, the
#      series' test commit is dropped.
#   2. patches/mutter-d5e397c2.patch — upstream commit d5e397c2
#      ("shaped-texture: Disable blending for opaque regions"), applied in
#      reverse, i.e. restoring blending for opaque regions.
#
# Both are applied in the RPM %prep stage, in that order: !5179 first (its diff
# was generated against the unmodified 51.1 sources), then d5e397c2 reversed.
# The resulting RPM gets an ".override.N" release suffix so dnf prefers it over
# both the repository build and any earlier local override build.
#
# Environment:
#   MUTTER_KEEP_WORKDIR=1  keep the temporary build tree for inspection
#   MUTTER_OVERRIDE_REL=…  override the release suffix (default: override.2)

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REVERT_PATCH_FILE="${SCRIPT_DIR}/patches/mutter-d5e397c2.patch"
REVERT_PATCH_NAME="mutter-d5e397c2.patch"
BACKPORT_PATCH_FILE="${SCRIPT_DIR}/patches/mutter-mr5179.patch"
BACKPORT_PATCH_NAME="mutter-mr5179.patch"
WORKDIR="$(mktemp -d /var/tmp/mutter-build.XXXXXX)"
KEEP_WORKDIR="${MUTTER_KEEP_WORKDIR:-0}"
OVERRIDE_REL="${MUTTER_OVERRIDE_REL:-override.2}"
BLEND_LINE='cogl_pipeline_set_blend (pipeline, "RGBA = ADD (SRC_COLOR, 0)", NULL);'
# Symbol introduced by merge request !5179; used as a "did the backport land" marker.
BACKPORT_MARKER='sampling_opaque_region'

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
[[ -f "${REVERT_PATCH_FILE}" ]] || die "patch not found: ${REVERT_PATCH_FILE}"
[[ -f "${BACKPORT_PATCH_FILE}" ]] || die "patch not found: ${BACKPORT_PATCH_FILE}"
grep -q "${BACKPORT_MARKER}" "${BACKPORT_PATCH_FILE}" \
    || die "backport patch does not mention ${BACKPORT_MARKER}; wrong file?"

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
# Patch spec: apply the !5179 backport, then reverse-apply d5e397c2
##################################
info "Patching mutter.spec"
cp "${REVERT_PATCH_FILE}" "${RPMBUILD_DIR}/SOURCES/${REVERT_PATCH_NAME}"
cp "${BACKPORT_PATCH_FILE}" "${RPMBUILD_DIR}/SOURCES/${BACKPORT_PATCH_NAME}"

# Declare both patches as Sources so %autosetup does not apply them forwards;
# they are applied explicitly right after %autosetup, in this order:
#   SOURCE1001  !5179 backport   (exact diff against unmodified 51.1 sources)
#   SOURCE1000  d5e397c2 reversed (must come second: its context predates !5179)
sed -i "/^Source0:/a Source1000:       ${REVERT_PATCH_NAME}\nSource1001:       ${BACKPORT_PATCH_NAME}" "${SPEC}"
sed -i "/^%autosetup/a patch -p1 --fuzz=0 < %{SOURCE1001}\npatch -R -p1 --fuzz=0 < %{SOURCE1000}" "${SPEC}"

# Bump the release so dnf treats this build as newer than both the repo package
# and any previous ".override" build. Without a bump, dnf would consider the
# already-installed RPM identical and skip the install.
read -r SRC_VER SRC_REL < <(rpm -qp --qf '%{VERSION} %{RELEASE}\n' "${SRC_RPM}")
[[ -n "${SRC_VER}" && -n "${SRC_REL}" ]] || die "could not read source RPM version"
NEW_REL="${SRC_REL}.${OVERRIDE_REL}"
sed -i "s/^Release:.*/Release:       ${NEW_REL}/" "${SPEC}"

grep -q "^Source1000:.*${REVERT_PATCH_NAME}" "${SPEC}" || die "failed to add Source1000 to spec"
grep -q "^Source1001:.*${BACKPORT_PATCH_NAME}" "${SPEC}" || die "failed to add Source1001 to spec"
grep -q '^patch -p1 --fuzz=0 < %{SOURCE1001}' "${SPEC}" || die "failed to add backport patch command to spec"
grep -q '^patch -R -p1 --fuzz=0 < %{SOURCE1000}' "${SPEC}" || die "failed to add reverse patch command to spec"
grep -q "^Release:.*${NEW_REL}" "${SPEC}" || die "failed to set release suffix"

# The backport has to be applied before the reverse patch, otherwise the
# reverse patch's context no longer matches.
line_backport="$(grep -n '^patch -p1 --fuzz=0 < %{SOURCE1001}' "${SPEC}" | cut -d: -f1)"
line_revert="$(grep -n '^patch -R -p1 --fuzz=0 < %{SOURCE1000}' "${SPEC}" | cut -d: -f1)"
[[ -n "${line_backport}" && -n "${line_revert}" && "${line_backport}" -lt "${line_revert}" ]] \
    || die "spec applies the patches in the wrong order (!5179 must come first)"

info "Building mutter ${SRC_VER}-${NEW_REL}"

##################################
# Build
##################################
info "Installing BuildRequires (dnf builddep)"
dnf builddep -y --spec "${SPEC}"

info "Running rpmbuild"
rpmbuild -bb --noclean --define "_topdir ${RPMBUILD_DIR}" "${SPEC}"

# Post-build: verify both patches really landed in the built sources.
BUILD_SRC="$(find "${RPMBUILD_DIR}/BUILD" -path '*/src/compositor/meta-shaped-texture.c' -print -quit)"
[[ -n "${BUILD_SRC}" ]] || die "patched source file not found after build"
remaining="$(grep -cF "${BLEND_LINE}" "${BUILD_SRC}" || true)"
if [[ "${remaining}" != "0" ]]; then
    die "reverse patch did not remove blend lines; ${remaining} remaining in ${BUILD_SRC}"
fi
backported="$(grep -c "${BACKPORT_MARKER}" "${BUILD_SRC}" || true)"
if [[ "${backported}" -eq 0 ]]; then
    die "backport !5179 missing: no '${BACKPORT_MARKER}' in ${BUILD_SRC}"
fi
info "Both patches verified: blend lines removed, ${backported} '${BACKPORT_MARKER}' occurrences present"

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
