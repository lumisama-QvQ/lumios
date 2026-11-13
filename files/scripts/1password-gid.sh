#!/usr/bin/env bash
# 1Password 的浏览器支持二进制必须以 onepassword 组 + setgid 运行（GID >= 1000）。
#
# 构建容器里 rpm 的 %post 会执行 groupadd onepassword，拿到的通常是第一个可用
# GID（1000），而运行时装机用户的主组也可能是 1000 —— 此时 setgid 不改变 egid，
# 内核不进入 secure mode，二进制会 abort：
#   "process detected it was running without libc's security, aborting"
#
# 所以这里把 GID 固定在 1500，并用 /usr/lib/sysusers.d/onepassword.conf 保证
# 运行时该组存在（构建容器里 /etc/group 的改动不会带进 ostree 镜像）。
set -euxo pipefail

OP_GID=1500

for dir in /opt/1Password /usr/lib/opt/1Password; do
  [ -d "$dir" ] || continue
  f="$dir/1Password-BrowserSupport"
  [ -f "$f" ] || continue
  chgrp "$OP_GID" "$f"
  chmod 2755 "$f"
done
