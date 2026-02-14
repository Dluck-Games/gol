class_name GoapWorldState
extends RefCounted

var facts: Dictionary[String, bool] = {}

func duplicate_state() -> Dictionary[String, bool]:
	return facts.duplicate(true)

func update_fact(key: String, value: bool) -> void:
	facts[key] = value

func get_fact(key: String, default_value: bool = false) -> bool:
	if not facts.has(key):
		return default_value
	return facts[key]

func has_fact(key: String) -> bool:
	return facts.has(key)
