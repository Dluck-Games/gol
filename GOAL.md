# GOAL: Night Raid Automated Playtest

## Spec

[docs/superpowers/specs/2026-05-23-night-raid-playtest-design.md](docs/superpowers/specs/2026-05-23-night-raid-playtest-design.md)

## Task

实现 spec 中描述的自动化玩法测试系统，包括所有源码变更、文档更新、skill 更新。

## Acceptance Criteria

以下条件全部满足即为通过：

1. `gol test playtest --suite night_raid` 命令可执行，Godot 窗口启动并运行夜袭测试
2. 12 个检查点全部 PASS，退出码为 0
3. `gol test playtest --suite night_raid --record` 生成 `logs/playtest/night_raid/recording.mp4`
4. `gol test integration --suite night_raid` 仍然通过（verify + breach_entry 两个用例）
5. `gol test unit --suite ai,system` 仍然通过
6. `--scenario`、`--scenario-param`、`--config` 参数已从代码中移除
7. `tests/integration/night_raid/test_night_raid_full_flow_scene.gd` 已删除
8. `night_raid_full_flow_verify_config.gd` 已删除
9. Spec "Affected Files Inventory" 中列出的所有 25 个文件均已按描述更新
10. CI workflow (`tests.yml`) 使用 `--integration=` 参数且 integration job 通过
