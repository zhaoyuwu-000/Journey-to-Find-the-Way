extends CanvasLayer
## 触屏按键：只在移动端显示。

const MARGIN := 170.0  # 距屏幕左右边缘
const BOTTOM := 150.0  # 距屏幕底部

func _ready() -> void:
	visible = OS.has_feature("mobile")
	get_viewport().size_changed.connect(_layout)
	_layout()

## 按当前视口尺寸重新摆位
func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	$Left.position = Vector2(MARGIN, vs.y - BOTTOM)
	$Right.position = Vector2(MARGIN + 220.0, vs.y - BOTTOM)
	$Jump.position = Vector2(vs.x - MARGIN, vs.y - BOTTOM)
