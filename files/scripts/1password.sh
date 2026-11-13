#!/usr/bin/env bash
# 移植自 ublue-os/bling 的 1password installer
# （https://github.com/ublue-os/bling/blob/main/modules/bling/installers/1password.sh）
#
# 唯一改动：把 `rpm-ostree install` 换成 `dnf install`。Fedora 45 的 bootc 底座上
# rpm-ostree install 无法工作（BlueBuild 文档也建议 bootc 镜像改用 dnf 模块）。
#
# 为什么必须修属组 / GID：
#   1Password-BrowserSupport 是 setgid 二进制，靠 setgid 进入 libc 的 secure mode
#   （AT_SECURE）来抵抗环境变量注入。构建容器里 rpm %post 的 `groupadd onepassword`
#   通常拿到第一个可用 GID（1000），而运行时首个用户的主组也可能正好是 1000：此时
#   setgid 前后 egid 不变，内核不进入 secure mode，二进制自检失败直接 abort：
#     "process detected it was running without libc's security, aborting"
#   表现为浏览器扩展永远连不上桌面端（日志在 ~/.config/1Password/logs/BrowserSupport）。
#
#   构建容器里对 /etc/group 的改动不会带进 ostree 镜像，所以组交给 sysusers.d 在
#   开机时创建，而二进制属组固定为这里的数字 GID。
set -euxo pipefail

##### Variables

# stable / beta
RELEASE_CHANNEL="${ONEPASSWORD_RELEASE_CHANNEL:-stable}"

# 是否顺带安装 op（1password-cli）
INSTALL_OP_CLI="${ONEPASSWORD_INSTALL_CLI:-0}"

# 必须 >= 1000，且不能与任何登录用户的主组撞号（Fedora 用户组从 1000 顺序分配，
# 所以跳开一段）
GID_ONEPASSWORD="${GID_ONEPASSWORD:-1500}"
GID_ONEPASSWORDCLI="${GID_ONEPASSWORDCLI:-1600}"
GID_ONEPASSWORDMCP="${GID_ONEPASSWORDMCP:-1700}"

##### 1. 安装

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

# 更新随镜像重建，不保留包管理器仓库
rm -f /etc/yum.repos.d/1password.repo

##### 2. 修正属组与权限

# 安装目录：构建早期在 /opt/1Password，optfix 之后在 /usr/lib/opt/1Password
OP_DIR=/opt/1Password
if [ ! -d "$OP_DIR" ]; then
  OP_DIR=/usr/lib/opt/1Password
fi
if [ ! -d "$OP_DIR" ]; then
  echo "1password.sh: 找不到 1Password 安装目录" >&2
  exit 1
fi
cd "$OP_DIR"

# chrome-sandbox 需要 setuid 位（electron 的 SUID sandbox）
chmod 4755 chrome-sandbox

# 浏览器扩展 ↔ 桌面端的通讯全靠它
chgrp "$GID_ONEPASSWORD" 1Password-BrowserSupport
chmod g+s 1Password-BrowserSupport

# MCP server 用自己的组（客户端靠 SO_PEERCRED 校验）
if [ -f 1password-mcp ]; then
  chgrp "$GID_ONEPASSWORDMCP" 1password-mcp
  chmod g+s 1password-mcp
fi

# op CLI 也有自己的组
if [ -f /usr/bin/op ]; then
  chgrp "$GID_ONEPASSWORDCLI" /usr/bin/op
  chmod g+s /usr/bin/op
fi

##### 3. 运行时组声明

# 注意：这些是写进镜像 /usr 的，不是本机 /etc
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

# rpm-ostree 会给 rpm 脚本创建的组自动生成动态 GID 的声明，和上面的固定 GID 冲突
rm -f /usr/lib/sysusers.d/30-rpmostree-pkg-group-onepassword.conf
rm -f /usr/lib/sysusers.d/30-rpmostree-pkg-group-onepassword-cli.conf
rm -f /usr/lib/sysusers.d/30-rpmostree-pkg-group-onepassword-mcp.conf

##### 4. 构建期校验（失败即中止构建）

stat -c '%a %U:%G %n' 1Password-BrowserSupport
grep -q "^g onepassword ${GID_ONEPASSWORD}$" /usr/lib/sysusers.d/onepassword.conf
