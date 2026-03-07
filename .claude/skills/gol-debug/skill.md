---
name: gol-debug
description: AI Debug Bridge for God of Lego - Execute debug commands, capture screenshots, run GDScript, and refresh game assets
---

# gol-debug

AI 调试工具集 - 截图、执行命令、运行脚本、控制游戏状态、刷新资源。

## 功能

| 功能 | 命令 |
|------|------|
| 截图 | `node gol-tools/ai-debug/ai-debug.mjs screenshot` |
| 执行命令 | `node gol-tools/ai-debug/ai-debug.mjs console <cmd>` |
| 表达式求值 | `node gol-tools/ai-debug/ai-debug.mjs eval <expr>` |
| 获取状态 | `node gol-tools/ai-debug/ai-debug.mjs get <property>` |
| 设置状态 | `node gol-tools/ai-debug/ai-debug.mjs set <prop> <val>` |
| 运行脚本 | `node gol-tools/ai-debug/ai-debug.mjs script <file.gd>` |
| 刷新资源 | `node gol-tools/ai-debug/ai-debug.mjs refresh [what]` |
| 重新导入 | `node gol-tools/ai-debug/ai-debug.mjs reimport` |

## 截图

```bash
cd /Users/dluckdu/Documents/Github/gol
node gol-tools/ai-debug/ai-debug.mjs screenshot
```

## Debug 命令

### 执行 Console 命令

```bash
# 治疗玩家
node gol-tools/ai-debug/ai-debug.mjs console heal full

# 传送到指定位置
node gol-tools/ai-debug/ai-debug.mjs console tp 100 200

# 设置时间
node gol-tools/ai-debug/ai-debug.mjs console time 12
node gol-tools/ai-debug/ai-debug.mjs console day
node gol-tools/ai-debug/ai-debug.mjs console night

# 无敌模式
node gol-tools/ai-debug/ai-debug.mjs console god

# 列出实体
node gol-tools/ai-debug/ai-debug.mjs console list enemy

# 杀死实体
node gol-tools/ai-debug/ai-debug.mjs console kill enemy
```

### 获取游戏状态

```bash
# 获取玩家位置
node gol-tools/ai-debug/ai-debug.mjs get player.pos

# 获取玩家血量
node gol-tools/ai-debug/ai-debug.mjs get player.hp

# 获取当前时间
node gol-tools/ai-debug/ai-debug.mjs get time

# 获取实体数量
node gol-tools/ai-debug/ai-debug.mjs get entity_count
```

### 设置游戏状态

```bash
# 设置时间为午夜
node gol-tools/ai-debug/ai-debug.mjs set time 0

# 设置为正午
node gol-tools/ai-debug/ai-debug.mjs set time 12
```

### 表达式求值

```bash
# 简单计算
node gol-tools/ai-debug/ai-debug.mjs eval "1 + 1"

# 注意：变量访问受限
```

## 动态脚本执行

AI 可以编写并执行 GDScript 来测试功能：

### 1. 创建测试脚本

```gdscript
# test_enemy_count.gd
extends Node

func run():
    var count = 0
    for entity in ECS.world.entities:
        if entity.has_component(CGoapAgent):
            var camp = entity.get_component(CCamp)
            if camp and camp.camp == CCamp.CampType.ENEMY:
                count += 1
    return "Enemy count: %d" % count
```

### 2. 执行脚本

```bash
node gol-tools/ai-debug/ai-debug.mjs script test_enemy_count.gd
```

### 脚本要求

- 必须 `extends Node`
- 必须实现 `func run()` 方法
- 返回值会被转为字符串输出

## 资源刷新

### 刷新游戏数据

```bash
# 重新加载实体配方
node gol-tools/ai-debug/ai-debug.mjs refresh recipes

# 刷新配置
node gol-tools/ai-debug/ai-debug.mjs refresh config

# 刷新 UI
node gol-tools/ai-debug/ai-debug.mjs refresh ui

# 刷新所有
node gol-tools/ai-debug/ai-debug.mjs refresh all
```

### 重新导入资源

用于解决 uid 文件更新问题或资源变更后的重新导入：

```bash
node gol-tools/ai-debug/ai-debug.mjs reimport
```

## 工作原理

```
AI/CLI                              Godot Game
  |                                     |
  |-- write 'command' file ----------->|
  |                                     |
  |                                     |-- AIDebugBridge 检测文件
  |                                     |-- 解析并执行命令
  |                                     |-- 写入结果文件
  |                                     |
  |<-- write 'result' file ------------|
  |                                     |
  |-- read result -------------------->|
```

## 文件位置

| 平台 | 信号目录 | 截图文件 |
|------|----------|----------|
| macOS | `~/Library/Application Support/Godot/app_userdata/God of Lego/ai_signals/` | `~/Library/Application Support/Godot/app_userdata/God of Lego/ai_screenshot.png` |
| Linux | `~/.local/share/godot/app_userdata/God of Lego/ai_signals/` | `~/.local/share/godot/app_userdata/God of Lego/ai_screenshot.png` |
| Windows | `%APPDATA%/Godot/app_userdata/God of Lego/ai_signals/` | `%APPDATA%/Godot/app_userdata/God of Lego/ai_screenshot.png` |

## 要求

- Godot 游戏必须运行
- `ScreenshotManager` 和 `AIDebugBridge` 必须在 autoloads 中
- 首次启动需要等待 3 帧初始化

## 故障排除

### "Timeout after 10s. Is the game running?"

```bash
# 启动游戏
/Applications/Godot.app/Contents/MacOS/Godot --path gol-project
```

### 命令无响应

检查 AIDebugBridge 是否已加载：查看 Godot 输出中是否有 "AIDebugBridge ready"

### 脚本执行失败

- 确保脚本 `extends Node`
- 确保有 `func run()` 方法
- 检查 Godot 控制台输出详细错误
