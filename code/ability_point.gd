@tool
extends Node2D
class_name AbilityPoint
## 能力点：玩家碰到 → 被吃掉（消失）；玩家用掉对应能力 → 重生。
## @tool：编辑器里也能看到对应状态的美术（鸟笼 / 洞穴 / 鱼缸）。
## 进入圆形范围 → 触发该能力点的对话（第一次整段，之后随机一句）。

enum Property { bird, bear, fish, none }

const SIZE := 600.0        # 世界里统一 1 格高
const TALK_RADIUS := 900.0 # 对话触发圆半径

## 每个能力状态对应的美术（ui 文件夹里的鸟笼 / 洞穴 / 鱼缸）
const TEX := {
	Property.bird: preload("res://sprite/ui/鸟笼.png"),
	Property.bear: preload("res://sprite/ui/洞穴1.png"),
	Property.fish: preload("res://sprite/ui/鱼缸.png"),
}

@export var property: Property = Property.none:
	set(v):
		property = v
		_apply_texture()   # 编辑器里改属性就能立刻换图

## 这个能力点的对话 id，形如 "level1.bird"；留空则按"关卡名.能力名"自动取
@export var dialogue_id := ""
## 对话触发半径（圆形范围）
@export var talk_radius := TALK_RADIUS
## 第一次从左侧经过时静默（不对话、不能吃），从右侧回来才激活
@export var require_approach_from_right := false

var dialogue

@onready var collision_shape_2d: CollisionShape2D = $Area2D/CollisionShape2D
@onready var sprite_2d: Sprite2D = $Sprite2D

var taken := false
var _inside := false
var _talk_cooldown := 0.0
var _activated := true   # 关闭时：对话和吃取都不生效

func _ready() -> void:
	_activated = not require_approach_from_right
	_apply_texture()
	_setup_talk_area()
	_apply_collision()

## 未激活时关掉"吃取"碰撞；激活后按 taken 状态恢复
func _apply_collision() -> void:
	collision_shape_2d.set_deferred("disabled", (not _activated) or taken)

## 按 property 换贴图并缩放到统一大小（编辑器预览和运行时都用它）
func _apply_texture() -> void:
	var sp := get_node_or_null("Sprite2D") as Sprite2D
	if sp == null:
		return
	var tex: Texture2D = TEX.get(property)
	if tex == null:
		return
	sp.texture = tex
	var s := SIZE / maxf(float(tex.get_height()), 1.0)
	sp.scale = Vector2(s, s)

## 对话范围：一个圆形 Area2D，玩家（layer 2）进圈就说话
func _setup_talk_area() -> void:
	if Engine.is_editor_hint():
		return
	var area := Area2D.new()
	area.name = "TalkArea"
	area.collision_layer = 0
	area.collision_mask = 2        # 玩家本体所在层
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = talk_radius
	shape.shape = circle
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_talk_entered)
	area.body_exited.connect(func(_body: Node2D) -> void: _inside = false)

func _process(delta: float) -> void:
	if _talk_cooldown > 0.0:
		_talk_cooldown = maxf(_talk_cooldown - delta, 0.0)

func _on_talk_entered(body: Node2D) -> void:
	if _inside:
		return
	_inside = true
	var dlg_node := get_node_or_null("/root/Dialogue")
	if body.get("can_be_controlled") == false or (dlg_node != null and dlg_node.is_playing()):
		return
	if not _activated:
		if body.global_position.x < global_position.x:
			return   # 第一次从左边经过：安静地放他过去
		_activated = true
		_apply_collision()
	var key := dialogue_id if dialogue_id != "" else _auto_dialogue_id()
	if key == "":
		return
	if dlg_node == null:
		return
	if _talk_cooldown > 0.0:
		return
	if dlg_node.play(key, body):
		_talk_cooldown = 1.5    # 播完前后别再被边界抖动反复触发

## 没填 dialogue_id 时自动拼：优先用节点名（bird / bear2 / fish3 …），
## 以名字为准、不看 property 类型；名字不像能力名的才退回按类型
func _auto_dialogue_id() -> String:
	var level_name := ""
	if owner != null and owner.scene_file_path != "":
		level_name = owner.scene_file_path.get_file().get_basename()
	var node_name := String(name).to_lower()
	for base_name in ["bird", "bear", "fish"]:
		var base := String(base_name)
		if node_name.begins_with(base):
			var rest := node_name.substr(base.length())
			var key_name: String = base
			if rest.is_valid_int() and rest.to_int() >= 2:
				key_name = "%s_%s" % [base, rest]
			return "%s.%s" % [level_name, key_name]
	var prop_name: String = String(Property.keys()[property]).to_lower()
	return "%s.%s" % [level_name, prop_name]

## 被吃掉：隐藏 + 关碰撞（物理回调里必须用 set_deferred）
func disappear() -> void:
	if taken:
		return
	taken = true
	_apply_collision()
	sprite_2d.visible = false

## 重生：显示 + 开碰撞
func appear() -> void:
	taken = false
	_apply_collision()
	sprite_2d.visible = true
