---
name: gol-issue
description: (project - Skill) Submit GitHub issues to god-of-lego submodule repo. Use when creating issues, reporting bugs, requesting features, or submitting tasks. Handles Chinese title format, label selection, body structure, and fuzzy-to-structured conversion. Triggers - 'create issue', 'submit issue', 'report bug', '提 issue', '提个需求', '创建 issue'
allowed-tools: Bash, Read, Edit
---

# gol-issue — 提交 GitHub Issue 到 god-of-lego 子模块仓库

将用户模糊的需求描述转化为结构化的 GitHub Issue，提交到 `Dluck-Games/god-of-lego` 仓库。

## 关键前提

gol 是 mono-repo 管理仓库，**Issue 始终提交到子模块仓库**：

```
gol/                      ← 管理仓库（不是 issue 目标）
├── gol-project/          ← 子模块：游戏代码（Issue 提交到这里）
│   └── .github/
└── gol-tools/            ← 子模块：工具链
```

- 目标仓库：`-R Dluck-Games/god-of-lego`
- 如果需要源码分析来确定 issue 内容，在 `gol-project/` 中搜索

## 工作流程

### Step 1: 理解意图

用户可能给出非常模糊的描述，例如：

- "spawn 什么东西" → 需要分析 spawn 系统，确定需要开发什么
- "箱子挡子弹" → 需要分析碰撞系统，确定是 bug 还是设计决策
- "小僵尸太小了" → 需要查看当前配置，确定合理的调整方向

**根据意图决定 issue 类型**：

| 意图 | 类型前缀 | 标签示例 |
|------|---------|---------|
| 新功能/开发 | `开发` | `feature` |
| 修复 Bug | `修复` | `bug` |
| 调整参数/配置 | `调整` | `feature` |
| 性能优化 | `优化` | `feature` |
| 重构 | `重构` | `feature` |
| 测试验证 | `测试` | `need testing`, `topic:*` |
| 设计讨论 | `设计` | `idea` |
| 子任务拆分 | `Sub-task` | `feature`, `topic:*` |

### Step 2: 源码分析（按需）

如果用户的描述模糊，**必须先分析源码再写 issue**。不要凭猜测写 issue body。

需要分析的内容包括：
- 涉及的组件（`scripts/components/c_*.gd`）
- 涉及的系统（`scripts/systems/s_*.gd`）
- 相关配置（`scripts/configs/config.gd`）
- 相关配方（`resources/recipes/*.tres`）
- 已有的实现模式（参考同类功能的实现方式）

分析后，issue body 应包含**具体的文件路径、类名、方法名、行号**，让开发者拿到 issue 就知道改哪里。

### Step 3: 写标题

**格式**：`{类型}：{简短描述}`

```bash
开发：实现 spawn 控制台命令
修复：箱子会阻挡并消耗子弹
调整：快速小僵尸体型进一步缩小
优化：单元测试 CI 耗时过长
```

规则：
- 类型前缀 + 全角冒号 `：` + 空格 + 描述
- 描述控制在 20 字以内，说清楚"做什么"
- 不要写成"为什么"（原因放在 body 里）
- 技术术语保留英文（如 spawn、buff、collision）

### Step 4: 写 Body

Body 使用 Markdown，中文为主，技术标识符用英文内联代码。

#### 通用结构（所有类型）

```markdown
## 背景
{为什么需要这个改动，当前状态是什么，引用具体文件/代码}

## {类型对应章节}
{详见下方类型模板}

## 关联
{关联 issue / PR 编号，如果有的话}
```

#### 按类型填充中间章节

**开发（新功能）**：
```markdown
## 需求
{一句话描述用户侧目标}

## 实现要点
1. **{步骤概述}**，在 `{文件路径}` 中
2. **{API/模式参考}**：`{具体类名.方法名()}`
3. **{数据/配置}**：{列举相关 recipe ID、常量等}
4. **参考**：{同类实现的参考文件}

## 可选增强
- {锦上添花的改进}
```

**修复（Bug）**：
```markdown
## 问题
{现象描述：玩家视角看到什么}

## 根因分析
### {子系统名称}
1. `{系统.方法()}` 做了什么
2. **关键点**：{哪个环节出了问题}
3. 后果：{导致什么现象}

## 修复建议
在 `{文件路径}` 中修改：

**方案 A（推荐）**：{具体做法}
\```gdscript
{代码片段}
\```

**方案 B**：{替代方案}

## 影响范围
- 修改文件：`{文件列表}`
- 不影响：{明确排除的范围}
```

**调整（参数/配置）**：
```markdown
## 背景
{当前值是什么，为什么需要调整}

## 当前配置
| 属性 | 当前值 | 说明 |
|------|--------|------|
| {key} | {value} | {注释} |

## 建议修改
在 `{文件路径}` 中调整：
1. **{参数 A}**：从 `{旧值}` 调整为 `{新值}`
2. **{参数 B}**：{可选，附带原因}

## 注意事项
- {风险点或副作用}
```

**测试验证**：
```markdown
## 验证目标
确认在 PR #{pr} / issue #{issue} 修复后，{一句话确认什么}

### 原始现象
- {现象 1}
- {现象 2}

### 已修复的根本原因
- {根因 1}
- {根因 2}

### 手动验证项
- {具体测试步骤}

### 关联工作
- 已合入 PR #{pr}
- 上级 issue: #{issue}
```

### Step 5: 选标签

**必选一个 type 标签**：

| 标签 | 用途 |
|------|------|
| `bug` | Bug 修复 |
| `feature` | 新功能、调整、优化、重构 |
| `idea` | 设计讨论、脑暴 |

**可选一个 topic 标签**：

| 标签 | 用途 |
|------|------|
| `topic:gameplay` | 玩法、战斗、AI、生成 |
| `topic:framework` | ECS 基础设施、系统架构 |
| `topic:visual` | 渲染、UI、特效、动画 |
| `topic:editor` | 编辑器工具、调试面板 |

**特殊标签**：

| 标签 | 用途 |
|------|------|
| `need testing` | 需要手动验证（如测试验证类 issue） |
| `foreman:plan` | 已有实现计划（通常不手动设置） |

**不要手动设置的标签**：`foreman:assign`, `foreman:build`, `foreman:testing`, `foreman:done`, `foreman:rework`, `foreman:blocked`, `shiori:rework`（这些由 Foreman daemon 管理）。

### Step 6: 提交

```bash
gh issue create -R Dluck-Games/god-of-lego \
  --title "{标题}" \
  --body "$(cat <<'EOF'
{body 内容}
EOF
)" \
  --label "{labels,逗号分隔}"
```

**label 参数规则**：
- 多个 label 用逗号分隔，无空格：`--label "feature,topic:gameplay"`
- 标签名必须与仓库已有标签完全匹配（区分大小写）

### Step 7: 确认

提交成功后，将 issue URL 返回给用户。格式简洁：

```
#{issue_number} {标题} — {type} | {topic}
```

## 多 Issue 批量提交

当用户一次性给出多个需求时，每个需求独立成一个 issue。用 todo 追踪进度：

```bash
# 逐个提交，每个 issue 独立的 gh issue create 调用
# 不要把多个需求塞进同一个 issue
```

## 注意事项

- **先分析后提交**：模糊描述 → 源码分析 → 结构化 issue。不要在没看过代码的情况下写 issue
- **body 要有信息量**：具体文件路径、类名、方法名、行号。开发者拿到 issue 就能动手
- **不要加 emoji**：标题和 body 都不用 emoji
- **不要加 praise**：不写"这个想法很好"之类的评价
- **保持简洁**：body 控制在 100 行以内，过长的技术分析拆成代码注释或单独文档
- **关联已有 issue**：如果和已有 issue 相关，在 body 末尾用 `关联 #{number}` 链接
