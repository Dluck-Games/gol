# Issue #226 coder 连续失败根因分析报告

## 调查概述

对 GOL 项目 Foreman 系统中 Issue #226（元素子弹添加 VFX 特效）的 coder 连续 3 次失败进行系统性调试分析。

## 失败时间线

| 决策 | 时间 | 结果 | 关键现象 |
|------|------|------|----------|
| Decision 002 | 00:25:29 | orphan | coder 进程启动后无输出，完全 orphan |
| Decision 003 | 00:27:07 | orphan | coder 进程启动后无输出，完全 orphan |
| Decision 004 | 00:33:06 | 错误文件修改 | coder 只修改了根目录 AGENTS.md/CLAUDE.md，未创建分支 |

## 根因分析

### 主要根因：工作目录路径混淆

**问题链：**
1. **路径配置错误**：coder 接收到的工作目录路径是管理仓库路径（`~/Documents/Github/gol/.worktrees/foreman/ws_20260401235350._1c7f90ec`），但实际需要修改的是 `gol-project/` 子模块中的游戏代码
2. **git 状态异常**：工作目录可能处于 detached HEAD 状态或已被 daemon 清理
3. **分支创建失败**：在异常 git 状态下无法创建 `foreman/issue-226-vfx` 分支
4. **文件修改错误**：coder 修改了管理仓库的文档文件而非游戏代码文件

### 技术细节

**工作目录生命周期问题：**
- Foreman daemon 在 coder 失败后清理了工作目录
- 但 coder 可能依赖工作目录中的 git 状态信息
- 清理导致后续 coder 无法正确识别 git 状态

**git 操作失败证据：**
```
error: src refspec foreman/issue-226-vfx does not match any
error: failed to push some refs to 'https://github.com/Dluck-Games/god-of-lego.git'
```

**文件修改错误证据：**
- commit `14c1a38` 仅包含根目录的 `AGENTS.md` 和 `CLAUDE.md` 变更
- 没有修改任何游戏代码文件（`c_bullet.gd`, `s_bullet_vfx.gd`, `s_damage.gd`, `s_fire_bullet.gd`）

## 系统性问题

### 1. 工作目录管理缺陷
- Foreman daemon 的工作目录清理策略过于激进
- coder 需要稳定的工作环境来维护 git 状态

### 2. 路径传递逻辑错误
- coder 应该操作 `gol-project/` 子模块，而不是管理仓库根目录
- 当前路径配置导致 coder 在错误的位置进行代码修改

### 3. 错误恢复机制不足
- 当 coder 失败时，系统没有有效的状态恢复机制
- 连续失败导致问题累积，最终达到放弃阈值

## 修复建议

### 短期修复（高优先级）
1. **修正工作目录路径**：确保 coder 在 `gol-project/` 子模块中工作
2. **改进 git 状态检查**：在派发 coder 前验证工作目录的 git 状态
3. **增强错误恢复**：在工作目录异常时自动重建有效的工作环境

### 长期改进
1. **工作目录生命周期优化**：减少不必要的清理，维护稳定的工作环境
2. **路径配置验证**：在派发 agent 前验证目标路径的有效性
3. **更好的错误诊断**：增加更详细的日志记录和状态监控

## 结论

Issue #226 的 coder 连续失败主要是由于**工作目录路径混淆**导致的系统性问题。coder 在错误的位置（管理仓库根目录）进行操作，而不是在正确的子模块（`gol-project/`）中修改游戏代码。这导致了 git 状态异常、分支创建失败和文件修改错误。

Planner 的方案质量已确认可行（`01-planner-bullet-vfx-analysis.md`），问题在于执行层面的工作环境配置。修复工作目录路径配置后，该方案应该可以正常实现。