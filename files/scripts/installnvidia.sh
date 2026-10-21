#!/usr/bin/env bash

# Copyright 2025 Universal Blue
# Copyright 2025 The Secureblue Authors
# Copyright 2025 The BlueBuild Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and limitations under the License.

set -euo pipefail

mkdir -p /var/tmp
chmod 1777 /var/tmp

##################################
# Repository setup
##################################
# 本镜像使用 upstream 的 nvidia-open 驱动（与 base-images 的 fedora-nvidia-open 行为一致）。
# 旧逻辑靠镜像名里是否含 "open" 判断，本镜像名（lumios）不含，因此默认强制 open 仓库，
# 仍可用 NVIDIA_REPO 覆盖。
nvidia_repo="${NVIDIA_REPO:-fedora-nvidia}"

KERNEL_VERSION="$(rpm -q "kernel-core" --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
RELEASE="$(rpm -E '%fedora.%_arch')"

curl -fLsS --retry 5 -o "/etc/yum.repos.d/${nvidia_repo}.repo" "https://negativo17.org/repos/${nvidia_repo}.repo"

#################################
# Kernel module
#################################
# 补丁内核的 kernel-devel 由 legion-fix.sh 提供（/usr/src/kernels/<kver>）；仅当缺失时才回退安装 Fedora 的 devel
if [[ -d "/usr/src/kernels/${KERNEL_VERSION}" ]]; then
    echo "kernel-devel for ${KERNEL_VERSION} already present"
else
    dnf install -y --setopt=install_weak_deps=False "kernel-devel-matched-$(rpm -q 'kernel-core' --queryformat '%{VERSION}')"
fi

dnf install -y --setopt=install_weak_deps=False akmods gcc-c++

cp /usr/sbin/akmodsbuild /usr/sbin/akmodsbuild.backup

# TODO remove this when fixed upstream
sed -i '/if \[\[ -w \/var \]\] ; then/,/fi/d' /usr/sbin/akmodsbuild

dnf install -y --setopt=install_weak_deps=False \
    --enable-repo="${nvidia_repo}" \
    nvidia-kmod-common nvidia-modprobe

echo "Installing kmod..."
akmods --force --kernels "${KERNEL_VERSION}" --kmod "nvidia"

mv /usr/sbin/akmodsbuild.backup /usr/sbin/akmodsbuild

# Depends on word splitting
# shellcheck disable=SC2086
modinfo /usr/lib/modules/${KERNEL_VERSION}/extra/nvidia/nvidia{,-drm,-modeset,-peermem,-uvm}.ko.xz > /dev/null || \
    (cat "/var/cache/akmods/nvidia/*.failed.log" && exit 1)

# View license information
# Depends on word splitting
# shellcheck disable=SC2086
modinfo -l /usr/lib/modules/${KERNEL_VERSION}/extra/nvidia/nvidia{,-drm,-modeset,-peermem,-uvm}.ko.xz

chmod +x ./signmodules.sh
./signmodules.sh "nvidia"

##################################
# Extra packages
##################################
nvidia_packages_list=(\
    'nvidia-driver' \
    'nvidia-persistenced' \
    'nvidia-settings' \
    'nvidia-driver-cuda' \
    'nvidia-container-toolkit' \
    'libnvidia-fbc' \
    'libva-nvidia-driver' \
)

curl -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
    -o /etc/yum.repos.d/nvidia-container-toolkit.repo
sed -i 's/^gpgcheck=0/gpgcheck=1/' /etc/yum.repos.d/nvidia-container-toolkit.repo

if ! [ -f /etc/pki/tls/certs/ca-bundle.crt ]; then
    ln /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/pki/tls/certs/ca-bundle.crt
fi

dnf -y --setopt=install_weak_deps=False install \
    --enable-repo='nvidia-container-toolkit' \
    --enable-repo="${nvidia_repo}" \
    "${nvidia_packages_list[@]}"

kmod_version=$(rpm -qa | grep akmod-nvidia | awk -F':' '{print $(NF)}' | awk -F'-' '{print $(NF-1)}')
negativo_version=$(rpm -qa | grep nvidia-modprobe | awk -F':' '{print $(NF)}' | awk -F'-' '{print $(NF-1)}')

echo "kmod_version: ${kmod_version}"
echo "negativo_version: ${negativo_version}"
if [[ "$kmod_version" != "$negativo_version" ]]; then
    echo "Version mismatch!"
    exit 1
fi

curl -L https://raw.githubusercontent.com/NVIDIA/dgx-selinux/master/bin/RHEL9/nvidia-container.pp \
    -o nvidia-container.pp
semodule -i nvidia-container.pp

##################################
# Cleanup
##################################
dnf -y remove akmod-nvidia akmods kernel-devel kernel-devel-matched kernel-headers

# 清掉编译用的内核源码（否则镜像会多出约 700 MB）
rm -rf /usr/src/kernels/*

rm -f nvidia-container.pp
rm -f /etc/yum.repos.d/nvidia-container-toolkit.repo
rm -f "/etc/yum.repos.d/${nvidia_repo}.repo"
