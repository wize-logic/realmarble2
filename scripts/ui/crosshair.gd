extends TextureRect


func _ready() -> void:
	pivot_offset = size / 2.0
	resized.connect(_on_resized)

func _on_resized() -> void:
	pivot_offset = size / 2.0
