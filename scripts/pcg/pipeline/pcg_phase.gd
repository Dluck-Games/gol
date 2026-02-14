# scripts/pcg/pipeline/pcg_phase.gd
class_name PCGPhase
extends RefCounted

@warning_ignore("unused_parameter")
func execute(config: PCGConfig, context: PCGContext) -> void:
	# Virtual hook: override in concrete phases (L-System, rasterizer, etc.)
	pass
