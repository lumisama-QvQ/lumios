# Clash Verge

## 服务单元

`files/system/etc/systemd/system/clash-verge-service.service` 整份覆盖 app 生成的同名单元，并在配方 L1 的 `systemd.enabled` 里启用。

app 的模板写死 `After=network-online.target`（字符串在 `/usr/bin/clash-verge-service-install` 里）。这个 target 要等 `NetworkManager-wait-online`（实测 16s），而 GUI 随登录会话启动；服务还没起来时 app 判定 IPC 不可用，pkexec 重装服务并改写单元。

- 改不掉的原因：空赋值只能重置普通列表，依赖项（`After=` / `Wants=` / `Requires=`）只能加不能删，systemd 262 实测无效——drop-in 里写了 `After=` 后 `systemctl show -p After` 仍有 `network-online.target`。
- `ExecStart` 指 `/usr/bin/clash-verge-service`：`/var` 不进镜像，`/var/lib/clash-verge-service/bin/` 那份只有 app 装过才有。
- app 重装服务会覆盖本文件；`/etc` 三方合并会保留本机版本，覆盖后要手删才会跟着镜像更新。

## 验证

```bash
systemctl cat clash-verge-service | head -3
systemctl show -p After clash-verge-service | tr ' ' '\n' | grep -c network-online   # 期望 0
```

## 不要做

- 别用 `After=` 空赋值的 drop-in 代替它。
- 别 mask `NetworkManager-wait-online.service`：brew / flatpak / dnf 的 timer 会失去网络就绪门控。
