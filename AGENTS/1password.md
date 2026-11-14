# 1Password

`1password.sh` 安装 1Password 并修正 `1Password-BrowserSupport` 的属组。

问题在 setgid 失效：该二进制靠 setgid 进入 libc 的 secure mode（`AT_SECURE`）来抵抗环境注入。构建容器里 `groupadd onepassword` 会拿到首个可用 GID（1000），与运行时首个用户的主组撞号，导致 setgid 前后 egid 不变，二进制自检失败并 abort：

```
process detected it was running without libc's security, aborting
```

症状是浏览器扩展永远连不上桌面端，日志在 `~/.config/1Password/logs/BrowserSupport/`。

GID 固定为 1500 / 1600 / 1700（onepassword / onepassword-cli / onepassword-mcp），必须 ≥1000 且不与登录用户主组冲突；组由 `sysusers.d` 在开机时创建。

排查：`stat -c '%a %U:%G' /usr/lib/opt/1Password/1Password-BrowserSupport` 应为 `2755 root onepassword`。
