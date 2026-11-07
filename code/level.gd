extends Node2D
class_name Level
## 关卡：生成玩家、出生点/复活点、相机跟随。关卡内的能力点由 AbilityPointManager 管。

const PLAYER_SCENE := preload("res://scene/player.tscn")
const BEAR_SCENE = preload("res://scene/bear.tscn")

@onready var camera_2d: Camera2D = $Camera2D
@onready var start_point: Node2D = $StartPoint

var controlled_member : CharacterBody2D
var revive_position := Vector2.ZERO
var cameraowner : Node2D = null
var player: CharacterBody2D
var bear: CharacterBody2D

var ability_manager: Node = null
var _checkpoint: Dictionary = {}   # 到达重生点时记下的关卡状态（死亡时恢复）

func _ready() -> void:
	if start_point != null:
		revive_position = start_point.global_position

	player = get_node_or_null("Player") as CharacterBody2D
	if player == null:
		player = PLAYER_SCENE.instantiate() as CharacterBody2D
		add_child(player)
	player.global_position = revive_position
	cameraowner = player

	player.connect("DIE", _player_die)
	player.connect("REVIVEPOINTSET", _revive_position_set)
	player.connect("USEBEAR", _switch_to_bear)
	player.connect("EXITBEAR", _switch_to_player)
	
	bear = BEAR_SCENE.instantiate() as CharacterBody2D
	add_child(bear)
	bear.visible = false
	bear.global_position = revive_position
	bear.connect("DIE", _on_bear_die)   # 熊碰水也算玩家死（回检查点）
	
	ability_manager = get_node_or_null("AbilityPointManager")
	controlled_member = player
	_take_checkpoint()   # 开局状态也算第一个检查点

func _process(_delta: float) -> void:
	if camera_2d and player:
		camera_2d.global_position = Vector2(cameraowner.global_position.x, cameraowner.global_position.y - 1000)

func _revive_position_set(pos: Vector2) -> void:
	revive_position = pos
	_take_checkpoint()   # 到达重生点：把当前关卡状态记成检查点
	_save_progress()     # 存档：下次进游戏直接回到这里

## 把"当前复活点状态"写进存档（关卡序号 + 复活坐标 + 能力快照）
func _save_progress() -> void:
	var save_node := get_node_or_null("/root/Save")
	if save_node == null:
		return
	var idx := -1
	var n: Node = get_parent()
	while n != null:
		if "current_level" in n:
			idx = n.current_level
			break
		n = n.get_parent()
	save_node.write({
		"level": idx,
		"revive_position": [revive_position.x, revive_position.y],
		"abilities": ability_manager.snapshot() if ability_manager != null else {},
		"dialogues": _dialogue_snapshot(),
	})

## 读档：GameRoot 进游戏时调用，把关卡恢复到存档里的复活点状态
func apply_save(data: Dictionary) -> void:
	var pos: Array = data.get("revive_position", [])
	if pos.size() == 2:
		revive_position = Vector2(float(pos[0]), float(pos[1]))
	if player != null:
		player.global_position = revive_position
		player.velocity = Vector2.ZERO
	if bear != null:
		bear.global_position = revive_position
	var abilities: Dictionary = data.get("abilities", {})
	if ability_manager != null and not abilities.is_empty():
		var owned: Array = abilities.get("owned", [])
		abilities["owned"] = owned.map(func(v: Variant) -> int: return int(v))
		var taken: Dictionary = abilities.get("taken", {})
		var fixed := {}
		for k in taken:                 # JSON 的 key 是字符串，转回 int
			fixed[int(k)] = taken[k]
		abilities["taken"] = fixed
		ability_manager.restore(abilities)
	_dialogue_restore(data.get("dialogues", {}))
	_take_checkpoint()

## 对话记录（哪些对话已经播过 first）
func _dialogue_snapshot() -> Dictionary:
	var dlg := get_node_or_null("/root/Dialogue")
	return dlg.snapshot() if dlg != null else {}

func _dialogue_restore(state: Dictionary) -> void:
	var dlg := get_node_or_null("/root/Dialogue")
	if dlg != null:
		dlg.restore(state)

## 记录当前关卡状态（到达重生点时调用）
func _take_checkpoint() -> void:
	_checkpoint = {
		"revive_position": revive_position,
		"ability_manager": ability_manager.snapshot() if ability_manager != null else {},
		"bodies": _snapshot_bodies(),
		"dialogues": _dialogue_snapshot(),
	}

## 关于动态刚体（barrier 等）：记下位置和旋转，死亡时复位
func _snapshot_bodies() -> Array:
	var out: Array = []
	for node in find_children("*", "RigidBody2D", true, false):
		var body := node as Node2D
		out.append({"node": body, "position": body.global_position, "rotation": body.rotation})
	return out

## 恢复检查点状态（玩家死亡时先恢复关卡，再让玩家复活）
func _restore_checkpoint() -> void:
	if _checkpoint.is_empty():
		return
	if ability_manager != null:
		ability_manager.restore(_checkpoint.get("ability_manager", {}))
	_dialogue_restore(_checkpoint.get("dialogues", {}))
	for entry in _checkpoint.get("bodies", []):
		var body: Node2D = entry["node"]
		if not is_instance_valid(body):
			continue
		body.global_position = entry["position"]
		body.rotation = entry["rotation"]
		if body is RigidBody2D:
			body.linear_velocity = Vector2.ZERO
			body.angular_velocity = 0.0
			body.sleeping = false
	# 如果死在熊形态：退回玩家控制
	if bear != null:
		bear.visible = false
		bear.can_be_controlled = false
	player.can_be_controlled = true
	cameraowner = player
	controlled_member = player

## 熊碰水：按玩家死亡处理（走 player 自己的 DIE 流程）
func _on_bear_die() -> void:
	if player == null:
		return
	player.die()
	player.emit_signal("DIE")

## 玩家死亡：恢复检查点状态并复活
func _player_die() -> void:
	_restore_checkpoint()
	player.revive(revive_position)

func _switch_to_player() -> void:
	if player:
		bear.visible = false
		bear.can_be_controlled = false
		player.can_be_controlled = true
		cameraowner = player
		controlled_member = player

func _switch_to_bear() -> void:
	if bear:
		bear.global_position = player.global_position
		bear.visible = true
		bear.can_be_controlled = true     # 熊开始接受 left/right 输入
		player.can_be_controlled = false
		cameraowner = bear
		controlled_member = bear
