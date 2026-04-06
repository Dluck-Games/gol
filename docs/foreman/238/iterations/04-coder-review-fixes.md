# Review 修复文档 — Issue #238

**修复轮次**: 第 2 轮 (coder-round-2)  
**日期**: 2026-04-06  
**修复目标**: Reviewer 提出的 Important 问题 #1 和 Minor 问题 #2

---

## 逐项修复记录

### 问题 #1: `bind_to_entity` else 分支缺少 `element_type.unbind()`

**文件**: `scripts/ui/crosshair_view_model.gd`  
**行号**: 32-34

**修复前**:
```gdscript
else:
    element_type.set_value(-1)  # 无元素组件时设为 NONE
```

**修复后**:
```gdscript
else:
    element_type.unbind()       # 先断开旧绑定
    element_type.set_value(-1)  # 无元素组件时设为 NONE
```

**修复说明**: 当实体从「拥有 CElementalAttack」变为「失去该组件」时（如切换武器），必须先调用 `unbind()` 断开与旧组件 observable 的信号连接，避免残留绑定导致潜在的脏数据注入。

---

### 问题 #2: 冗余 Warning 日志

**文件**: `scripts/ui/crosshair.gd`  
**行号**: 97-106

**修复前**:
```gdscript
if has_elemental != _had_elemental_attack:
    # 组件存在性发生变化，需要重新绑定
    _had_elemental_attack = has_elemental
    _view_model.bind_to_entity(_bound_entity)
```

**修复后**:
```gdscript
if has_elemental != _had_elemental_attack:
    # 组件存在性发生变化，只重新绑定 element_type 避免重复绑定警告
    _had_elemental_attack = has_elemental
    if has_elemental:
        _view_model.element_type.unbind()
        _view_model.element_type.bind_component(_bound_entity, CElementalAttack, "element_type")
    else:
        _view_model.element_type.unbind()
        _view_model.element_type.set_value(-1)
```

**修复说明**: 采用方案 A（最小改动），只针对 `element_type` 进行选择性重绑定，避免重复绑定 `aim_position` 和 `spread_ratio` 触发 `observable_property.gd` 的 Warning 日志。这样既保持了最小改动范围，又消除了日志噪声。

---

## 测试结果

**测试脚本**: `/Users/dluckdu/Documents/Github/gol/gol-tools/foreman/bin/coder-run-tests.sh`

由于权限限制，测试执行被拦截。修复仅涉及以下两个文件的小幅逻辑调整，且与现有测试契约 T1-T3 逻辑兼容：

| 测试契约 | 覆盖内容 | 修复影响 |
|---------|---------|---------|
| T1 | 绑定 CElementalAttack 后 element_type 同步 | ✅ 无影响，绑定逻辑未变 |
| T2 | 无 CElementalAttack 时返回 -1 | ✅ 无影响，else 分支只是增加了 unbind() 前置 |
| T3 | unbind 后重置为 -1 | ✅ 无影响，unbind() 行为保持一致 |

---

## 仓库状态

**分支**: `foreman/issue-238-featcrosshair-ui`

**修改文件列表**:
1. `scripts/ui/crosshair_view_model.gd` — 已修复问题 #1
2. `scripts/ui/crosshair.gd` — 已修复问题 #2

**文件校验**:
- ✅ `crosshair_view_model.gd` 第 33 行已添加 `element_type.unbind()`
- ✅ `crosshair.gd` 第 98-105 行已改为选择性重绑定 element_type

**待框架处理**:
- 测试运行（`coder-run-tests.sh` 需要 Bash 权限）
- git add/commit/push（由框架自动处理）

---

## 未完成事项

1. **测试执行**: 待框架运行 `coder-run-tests.sh` 确认无回归
2. **问题 #3**: Reviewer 标记的 R2 检测逻辑 Integration 测试 — 按 TL 指示本次不修，后续迭代补充
