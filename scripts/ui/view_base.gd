class_name ViewBase
extends Control


func _ready() -> void:
	setup()
	bind()

func setup() -> void:
	pass

func teardown() -> void:
	pass

func bind() -> void:
	pass


# Quick bind helper functions
func bind_text(label: Label, observable: ObservableProperty) -> void:
	var on_text_updated: Callable = func(new_value):
		label.text = new_value
	observable.subscribe(on_text_updated)
	
func bind_visibility(control: Control, observable: ObservableProperty) -> void:
	var on_visibility_updated: Callable = func(new_value):
		control.visible = new_value
	observable.subscribe(on_visibility_updated)
