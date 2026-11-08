extends CanvasLayer
## 坑里的键位说明：玩家掉进指定区域时淡入显示，离开后淡出。

@export var x_min := 10200.0
@export var x_max := 12900.0
@export var y_below := 700.0        # 玩家 y 超过这个值（比地面低）就算“在坑里”

var _label: Label
var _player: Node2D
var _target := 0.0

func _ready() -> void:
	_label = get_node_or_null("Label") as Label
	if _label != null:
		_label.modulate.a = 0.0
	await get_tree().process_frame
	var level := get_parent()
	if level != null:
		_player = level.get_node_or_null("Player") as Node2D

func _process(delta: float) -> void:
	if _label == null or _player == null:
		return
	var pos := _player.global_position
	var inside := pos.x >= x_min and pos.x <= x_max and pos.y >= y_below
	_target = 1.0 if inside else 0.0
	_label.modulate.a = move_toward(_label.modulate.a, _target, delta / 0.25)
