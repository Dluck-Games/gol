class_name Service_SaveData
extends ServiceBase


var data: Dictionary = {}

func teardown() -> void:
	print("Service_SaveData: Clearing save data")
	data.clear()


func _ready() -> void:
	pass # pass for temporary resolve errors when begin play
#	load_data()
		
func save_data() -> void:
	# Save the data to file
	var file = FileAccess.open("user://savedata.json", FileAccess.WRITE)
	if file:
		var json_data = JSON.stringify(data)
		file.store_string(json_data)
		file.close()
	else:
		push_error("Failed to save savedata.json")
		
		
func load_data() -> void:
	# Load data from savedata.json
	var file = FileAccess.open("user://savedata.json", FileAccess.READ)
	if file:
		var json_data = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(json_data)
		if error == OK:
			data = json.result
		else:
			push_error("JSON parse error: " + str(error))
		file.close()
	else:
		push_error("Failed to load savedata.json")
		data = {}  # Initialize empty data if load fails

func set_data(key: String, value: Variant) -> void:
	# Set data by key
	if key in data:
		data[key] = value
	else:
		push_error("Key not found in savedata: " + key)
		return
	
	save_data()  # Save after setting data
		
		
func get_data(key: String) -> Variant:
	# Get data by key
	if key in data:
		return data[key]
	else:
		push_error("Key not found in savedata: " + key)
		return null
