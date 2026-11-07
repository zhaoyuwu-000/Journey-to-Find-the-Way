extends Node2D
## 能力点系统：
## 吃到 → 该能力进 owned、点消失；已有的能力对应的点不能吃（留着）。
## 用掉 → 移出 owned、对应点重生。
## 死亡时的恢复由 Level 按“检查点快照”调用 snapshot()/restore()。

signal ability_acquired(prop: int)   # 拿到一个新能力
signal ability_consumed(prop: int)   # 用掉一个能力
signal state_restored                # 按检查点快照恢复完成（UI 刷新用）

const MAX_ABILITIES := 3

var player: CharacterBody2D

var owned: Array[int] = []          # 当前持有的能力（AbilityPoint.Property，最多 3 个）

var _points: Dictionary = {}        # AbilityPoint.Property -> AbilityPoint

func _ready() -> void:
	add_to_group("ability_manager")
	_bind.call_deferred()   # 等 Level._ready 把 Player 生成出来

func _bind() -> void:
	player = get_parent().get_node_or_null("Player") as CharacterBody2D
	if player == null:
		push_error("AbilityPointManager: 找不到 Player")
		return

	player.connect("EATABILITY", _on_player_eat)
	player.connect("USEABILITY", _on_player_use)

	for p in get_tree().get_nodes_in_group("abilitypoints"):
		if p is AbilityPoint and p.property != AbilityPoint.Property.none:
			_points[p.property] = p

## 当前是否持有某个能力（给 UI 判断显示/灰化）
func has_ability(prop: int) -> bool:
	return prop in owned

## 生成检查点快照：持有集合 + 每个能力点吃没吃
func snapshot() -> Dictionary:
	var taken := {}
	for prop in _points:
		var p: AbilityPoint = _points[prop]
		if is_instance_valid(p):
			taken[prop] = p.taken
	return {"owned": owned.duplicate(), "taken": taken}

## 按快照恢复：持有集合、能力点的显示/隐藏
func restore(state: Dictionary) -> void:
	owned.assign(state.get("owned", []))
	var taken: Dictionary = state.get("taken", {})
	for prop in _points:
		var p: AbilityPoint = _points[prop]
		if not is_instance_valid(p):
			continue
		if taken.get(prop, false):
			p.disappear()
		else:
			p.appear()
	state_restored.emit()

## 给 UI 用：在已持有的能力之间切换形态（不消耗）
func choose_ability(prop: int) -> bool:
	if not has_ability(prop):
		return false
	player.switch_ability(prop)
	return true

## 玩家碰到能力点：只把能力收进 owned，不直接切换形态（要先在选择面板里选）
func _on_player_eat(point: AbilityPoint) -> void:
	if point == null or not is_instance_valid(point) or point.taken:
		return
	if point.property == AbilityPoint.Property.none:
		return
	if has_ability(point.property):
		return                       # 已经有了，不能吃（点留着）
	if owned.size() >= MAX_ABILITIES:
		return
	_points[point.property] = point
	point.disappear()
	owned.append(point.property)
	ability_acquired.emit(point.property)

## 玩家用掉了能力：移出持有、对应点重生
func _on_player_use(prop: int) -> void:
	owned.erase(prop)
	var point: AbilityPoint = _points.get(prop)
	if point != null and is_instance_valid(point) and point.taken:
		point.appear()
	ability_consumed.emit(prop)
