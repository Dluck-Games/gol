# scripts/pcg/pipeline/pcg_pipeline.gd
class_name PCGPipeline
extends RefCounted
## Pipeline coordinator that executes PCG phases sequentially.

var phases: Array[PCGPhase] = []


func add_phase(phase: PCGPhase) -> void:
	phases.append(phase)


func generate(config: PCGConfig) -> PCGResult:
	var effective_config: PCGConfig = config
	if effective_config == null:
		effective_config = PCGConfig.new()

	# Standardize on pcg_seed.
	var pcg_seed: int = effective_config.pcg_seed
	var context := PCGContext.new(pcg_seed)

	for phase: PCGPhase in phases:
		phase.execute(effective_config, context)

	return PCGResult.new(
		effective_config,
		context.road_graph,
		null,
		null,
		context.grid
	)
