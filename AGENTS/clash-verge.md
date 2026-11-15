# Clash Verge

## 现象

每次开机 app 弹 pkexec 重装服务；TUN 模式表现为“重启后要重新授权”。日志里：

```
[Service] current service IPC is unavailable: IPC path unavailable: 没有那个文件或目录
[Service] running privileged service action ForceReinstall
```

服务没坏，只是起得比 GUI 晚。

## 一次开机的时间线（2026-11-14 23:52）

```
23:52:12      boot
23:52:28.247  enp129s0 carrier up
23:52:28.256  dhcp4 beginning transaction
23:52:37.588  dhcp4 拿到租约            ← 9.3s 全耗在这
23:52:37.803  manager: startup complete
23:52:37.812  network-online.target 达成
23:52:37.813  Started clash-verge-service（比 target 晚 1ms）
23:52:29.373  GUI 已启动 → IPC ENOENT → 23:52:36 ForceReinstall
```

链路上线只用了 3 秒，`startup complete` 被 DHCP 拖后 9.3 秒；`nm-online -s` 等的就是这一行。服务自身的启动耗时 20 余毫秒（`Started` → 首行日志 23ms），完全不慢。

## 试过并已移除的做法

仓库里现在没有任何补丁文件，下面三条都验证过不通：

| 做法 | 结果 |
| --- | --- |
| `/etc/…/clash-verge-service.service.d/10-start-early.conf` 里 `After=` 空值重置 | 无效。空赋值只重置普通列表，依赖项只能加不能删（[systemd#18154](https://github.com/systemd/systemd/issues/18154)）；systemd 262 实测 `After` 里 `network-online.target` 仍在 |
| 镜像里预制整份 `/etc/systemd/system/clash-verge-service.service` | 首启必失败（`/var/lib` 布局要等 app 安装才建立），app 随后安装并覆盖；`/etc` 三方合并还会让被覆盖的版本长期赖着 |
| 镜像里预制整份 `/usr/lib/systemd/system/clash-verge-service.service` | app 装过之后 `/etc` 那份优先（`/etc` > `/run` > `/usr/lib`），这份被遮蔽；不 enable 则没有东西拉它，等于死文件 |

判据始终是 `systemctl show -p FragmentPath clash-verge-service`：不是 `/usr/lib/...` 就说明看到的是 app 那份。

## 改排序为什么这么难

- 单元由 `/usr/bin/clash-verge-service-install` 生成，模板写死 `After=network-online.target nftables.service iptables.service`，写进 `/etc/systemd/system/` 后 `daemon-reload` + `enable` + `start`。
- `After=nftables.service iptables.service` 不能整条删掉，TUN 规则要这个顺序。
- `ExecStart` 必须是 `/var/lib/clash-verge-service/bin/clash-verge-service`：服务目录硬编码在 `/var/lib/clash-verge-service`，指 `/usr/bin` 那份会 `failed to open service directory`。

## 不要做

- mask `NetworkManager-wait-online.service`：会连带 `brew-*`、`flatpak-system-updates`、`dnf-makecache` 这些 `Wants=network-online.target` 的单元失去网络就绪门控。

## 待试

1. **从网络侧消掉那 9.3 秒 DHCP**：交换机/路由端口开 portfast，或这条有线连接改固定 IP。`startup complete` 会回到 1 秒内，`network-online` 不再是瓶颈。
2. **path 单元动态修复**：监听 `/etc/systemd/system/clash-verge-service.service`，app 每次重写就把 `After=` 改回去并 `daemon-reload`（不要 restart，会和 installer 的 `start` 抢 owner lock），只对下一次开机生效。
3. 让 app 等更久或不自动重装：属于改 app，镜像层做不到。

## 排查命令

```bash
systemctl show -p FragmentPath -p DropInPaths clash-verge-service
systemctl show -p After clash-verge-service | tr ' ' '\n' | grep -c network-online
systemctl show -p ActiveEnterTimestamp --value clash-verge-service
journalctl -b -u NetworkManager | grep -E 'dhcp4|startup complete'
journalctl -b -u clash-verge-service | head
```
