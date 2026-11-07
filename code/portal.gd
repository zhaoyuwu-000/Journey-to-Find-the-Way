@tool
extends Area2D
## 传送门：玩家进入范围 → 进入下一关（交给上层 GameRoot.next_level()）。

const TEX := preload("res://sprite/场景图，neva/可碰撞/传送门.png")

## 缩放（图是 600×600 = 1 格）
@export var size_tiles := 1.0:
	set(v):
		size_tiles = v
		_apply_size()

var _used := false

func _ready() -> void:
	_apply_size()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)

## 贴图铺在碰撞体脚下：Sprite 底边 = 节点原点
func _apply_size() -> void:
	var sp := get_node_or_null("Sprite2D") as Sprite2D
	if sp == null:
		return
	sp.texture = TEX
	sp.scale = Vector2(size_tiles, size_tiles)
	sp.position = Vector2(0, -300.0 * size_tiles)

func _on_body_entered(body: Node2D) -> void:
	if _used or not (body is CharacterBody2D):
		return
	_used = true
	var n: Node = self
	while n != null:
		if n.has_method("next_level"):
			n.call_deferred("next_level")   # 物理回调里不能直接换关，延迟到帧末
			return
		n = n.get_parent()
	push_error("Portal: 上层没有 next_level()（GameRoot）")
