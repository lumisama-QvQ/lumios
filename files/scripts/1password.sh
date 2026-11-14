#!/usr/bin/env bash
# 安装 1Password 并修正辅助二进制的属组/GID
set -euxo pipefail

# stable / beta
RELEASE_CHANNEL="${ONEPASSWORD_RELEASE_CHANNEL:-stable}"
# 1 = 同时安装 op CLI
INSTALL_OP_CLI="${ONEPASSWORD_INSTALL_CLI:-0}"
# 必须 >=1000，且不与任何登录用户的主组冲突
GID_ONEPASSWORD="${GID_ONEPASSWORD:-1500}"
GID_ONEPASSWORDCLI="${GID_ONEPASSWORDCLI:-1600}"
GID_ONEPASSWORDMCP="${GID_ONEPASSWORDMCP:-1700}"

cat > /etc/yum.repos.d/1password.repo <<EOF
[1password]
name=1Password ${RELEASE_CHANNEL^} Channel
baseurl=https://downloads.1password.com/linux/rpm/${RELEASE_CHANNEL}/\$basearch
enabled=1
gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF

rpm --import https://downloads.1password.com/linux/keys/1password.asc

PKGS=(1password)
if [ "$INSTALL_OP_CLI" = "1" ]; then
  PKGS+=(1password-cli)
fi

dnf install -y "${PKGS[@]}"

# 更新随镜像重建
rm -f /etc/yum.repos.d/1password.repo

# optfix 前在 /opt/1Password，之后在 /usr/lib/opt/1Password
OP_DIR=/opt/1Password
if [ ! -d "$OP_DIR" ]; then
  OP_DIR=/usr/lib/opt/1Password
fi
if [ ! -d "$OP_DIR" ]; then
  echo "1password.sh: 找不到 1Password 安装目录" >&2
  exit 1
fi
cd "$OP_DIR"

# electron SUID sandbox
chmod 4755 chrome-sandbox

chgrp "$GID_ONEPASSWORD" 1Password-BrowserSupport
chmod g+s 1Password-BrowserSupport

if [ -f 1password-mcp ]; then
  chgrp "$GID_ONEPASSWORDMCP" 1password-mcp
  chmod g+s 1password-mcp
fi

if [ -f /usr/bin/op ]; then
  chgrp "$GID_ONEPASSWORDCLI" /usr/bin/op
  chmod g+s /usr/bin/op
fi

mkdir -p /usr/lib/sysusers.d
cat > /usr/lib/sysusers.d/onepassword.conf <<EOF
g onepassword ${GID_ONEPASSWORD}
EOF
cat > /usr/lib/sysusers.d/onepassword-cli.conf <<EOF
g onepassword-cli ${GID_ONEPASSWORDCLI}
EOF
cat > /usr/lib/sysusers.d/onepassword-mcp.conf <<EOF
g onepassword-mcp ${GID_ONEPASSWORDMCP}
EOF

rm -f /usr/lib/sysusers.d/30-rpmostree-pkg-group-onepassword.conf
rm -f /usr/lib/sysusers.d/30-rpmostree-pkg-group-onepassword-cli.conf
rm -f /usr/lib/sysusers.d/30-rpmostree-pkg-group-onepassword-mcp.conf

stat -c '%a %U:%G %n' 1Password-BrowserSupport
grep -q "^g onepassword ${GID_ONEPASSWORD}$" /usr/lib/sysusers.d/onepassword.conf
