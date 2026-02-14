class_name CGoapAgent
extends Component

var world_state: GoapWorldState = GoapWorldState.new()

@export var goals: Array[GoapGoal] = []

var plan: GoapPlan = null
var running_action: GoapAction
var running_context: Dictionary = {}
var blackboard: Dictionary = {}

var plan_invalidated: bool = false
var plan_invalidated_reason: String = ""
