# mutter 补丁

`override-mutter.sh` 从 Fedora 的 mutter SRPM 重建 RPM，打入两个补丁，`Release` 加 `.override.N` 以覆盖仓库版本。

| 补丁 | 作用 | 上游 | 状态 |
| --- | --- | --- | --- |
| `mutter-mr5179.patch` | 分数缩放下的 offscreen effect 像素相位、opaque region 采样安全 | MR !5179 | **未合并**，backport |
| `mutter-d5e397c2.patch` | 反向应用，恢复不透明区域的 blending | commit `d5e397c2` | 已合入，主动回退 |

- 顺序不能反：先 `!5179` 再 `-R d5e397c2`；前者基于未改动的 51.1 生成，后者的上下文来自 d5e397c2 合入后的源码。
- 后缀默认 `override.2`：不改后缀 dnf 会认为与已安装版本相同而跳过。
- `!5179` 只取运行时代码，丢弃了上游的测试提交；原始 diff 在 `clutter-offscreen-effect.c` 的 hunk #2 需要 fuzz 2，因此重新生成过精确补丁。
- 移除条件：`!5179` 合入并随 mutter 发布后删掉该补丁、后缀退回 `.override`；mutter 升版时两个补丁都要 rebase。
- `MUTTER_KEEP_WORKDIR=1` 保留构建目录，`MUTTER_OVERRIDE_REL` 改后缀。
