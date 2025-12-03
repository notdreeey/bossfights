extends CharacterBody2D

# --- CONFIG ---
@export var speed = 250
@export var max_hp = 5
@export var fire_rate = 0.3 

# VISIBILITY MARGIN
@export var aim_margin = 100.0

# --- NODES ---
@onready var hand = $Hand
@onready var muzzle = $Hand/Muzzle
@onready var sprite = $Sprite2D
@onready var camera = $Camera2D
var projectile_scene = preload("res://projectile.tscn")

# --- VARIABLES ---
var hp = max_hp
var boss_ref : Node2D = null
var shake_strength : float = 0.0
var can_shoot : bool = true 
var last_move_direction = Vector2.RIGHT 

func _physics_process(delta):
	move_logic()
	auto_aim_logic() 
	camera_logic(delta)
	
	if Input.is_action_pressed("ui_accept"):
		shoot()

func move_logic():
	var input = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input * speed
	move_and_slide()
	
	if velocity.length() > 0:
		last_move_direction = velocity.normalized()

func auto_aim_logic():
	# 1. GATHER ALL TARGETS (Consolidated into one list)
	var targets = []
	targets.append_array(get_tree().get_nodes_in_group("Boss"))
	targets.append_array(get_tree().get_nodes_in_group("Hostile"))
	# If you still have the melee guys in "Enemies", uncomment the next line:
	# targets.append_array(get_tree().get_nodes_in_group("Enemies"))
	
	# 2. CALCULATE CAMERA BOUNDS + MARGIN
	var screen_size = get_viewport_rect().size / camera.zoom
	var camera_center = camera.get_screen_center_position()
	var top_left = camera_center - (screen_size / 2)
	
	var camera_rect = Rect2(top_left, screen_size)
	var detection_rect = camera_rect.grow(aim_margin)

	# 3. FIND NEAREST ENEMY INSIDE THE BOX
	var nearest_node = null
	var shortest_dist = INF 
	
	for target in targets:
		if is_instance_valid(target):
			# Check against the EXPANDED rect
			if detection_rect.has_point(target.global_position):
				var dist = global_position.distance_to(target.global_position)
				if dist < shortest_dist:
					shortest_dist = dist
					nearest_node = target
	
	# 4. AIMING DECISION
	if nearest_node != null:
		# --- AUTO AIM ---
		hand.look_at(nearest_node.global_position)
		
		if nearest_node.global_position.x < global_position.x:
			sprite.flip_h = true 
		else:
			sprite.flip_h = false 
			
	else:
		# --- MANUAL AIM ---
		hand.rotation = last_move_direction.angle()
			
		if last_move_direction.x < 0: sprite.flip_h = true
		elif last_move_direction.x > 0: sprite.flip_h = false

func shoot():
	if can_shoot == false: return
		
	var p = projectile_scene.instantiate()
	p.setup(muzzle.global_position, Vector2.RIGHT.rotated(hand.rotation), "Player")
	get_parent().add_child(p)
	
	can_shoot = false
	await get_tree().create_timer(fire_rate).timeout
	can_shoot = true

func take_damage(amount):
	hp -= amount
	camera_shake(5.0)
	modulate = Color.RED
	await get_tree().create_timer(0.1).timeout
	modulate = Color.WHITE
	if hp <= 0:
		get_tree().reload_current_scene()

func camera_logic(delta):
	var target_offset = Vector2.ZERO
	
	if is_instance_valid(boss_ref):
		var dist_to_boss = boss_ref.global_position - global_position
		target_offset = dist_to_boss * 0.5
		target_offset = target_offset.limit_length(150.0)
	else:
		var bosses = get_tree().get_nodes_in_group("Boss")
		if bosses.size() > 0: boss_ref = bosses[0]
	
	camera.position = camera.position.lerp(target_offset, 5.0 * delta)
	
	if shake_strength > 0:
		shake_strength = lerp(shake_strength, 0.0, 10.0 * delta)
		camera.position += Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength))

func camera_shake(amount):
	shake_strength = amount
