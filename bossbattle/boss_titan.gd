extends CharacterBody2D

# --- CONFIGURATION ---
enum {IDLE, JUMP_PREP, JUMP_AIR, JUMP_CRASH, SHOCKWAVE, CHARGE}
var state = IDLE

# Stats
var max_hp = 80 
var hp = max_hp
var is_enraged = false

# References
@onready var player = get_tree().get_first_node_in_group("Player")
@onready var visuals = $Visuals
@onready var sprite = $Visuals/Sprite2D
@onready var state_timer = $StateTimer

# UI
@export var health_bar : ProgressBar 

# Generated Node for the Landing Indicator
var landing_indicator : Polygon2D 

var projectile_scene = preload("res://projectile.tscn")

func _ready():
	if not state_timer.timeout.is_connected(_on_state_timer_timeout):
		state_timer.timeout.connect(_on_state_timer_timeout)
	
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = hp
		
		await get_tree().create_timer(2.0).timeout

	if player:
		add_collision_exception_with(player)

	create_landing_indicator()
	pick_random_state()

func create_landing_indicator():
	landing_indicator = Polygon2D.new()
	var points = PackedVector2Array()
	
	# Base Radius is 150
	for i in range(32):
		var angle = i * (TAU / 32)
		points.append(Vector2(cos(angle), sin(angle)) * 150) 
		
	landing_indicator.polygon = points
	landing_indicator.color = Color(1, 0, 0, 0.4) 
	landing_indicator.visible = false
	get_parent().call_deferred("add_child", landing_indicator) 

func _physics_process(delta):
	if not player: return 

	# FLIP SPRITE (Only when on ground)
	if state != JUMP_AIR and state != JUMP_CRASH:
		if player.global_position.x < global_position.x:
			visuals.scale.x = -1
		else:
			visuals.scale.x = 1

	match state:
		IDLE:
			velocity = Vector2.ZERO
			
		JUMP_PREP:
			velocity = Vector2.ZERO
			
		JUMP_AIR:
			# Visual "Height" Effect only
			visuals.position.y = lerp(visuals.position.y, -200.0, 3.0 * delta)
			visuals.scale = visuals.scale.lerp(Vector2(1.5, 1.5), 3.0 * delta)
			
		JUMP_CRASH:
			visuals.position.y = lerp(visuals.position.y, 0.0, 15.0 * delta)
			visuals.scale = visuals.scale.lerp(Vector2(1, 1), 15.0 * delta)
			
		CHARGE:
			move_and_slide()

func _exit_tree():
	if landing_indicator: landing_indicator.queue_free()

# --- TRANSITIONS ---

func pick_random_state():
	visuals.position.y = 0
	landing_indicator.visible = false
	
	var roll = randf()
	if roll < 0.5: enter_state(JUMP_PREP) 
	elif roll < 0.8: enter_state(CHARGE)
	else: enter_state(SHOCKWAVE)

func enter_state(new_state):
	state = new_state
	update_color()
	
	match state:
		IDLE:
			state_timer.start(1.0)
			
		JUMP_PREP:
			# Squash animation
			var t = create_tween()
			t.tween_property(visuals, "scale", Vector2(1.4, 0.6), 0.5)
			state_timer.start(0.5)
			
		JUMP_AIR:
			# 1. Place Indicator at Player's CURRENT position
			landing_indicator.global_position = player.global_position
			landing_indicator.visible = true
			
			# --- NEW: RAGE SCALE ---
			if is_enraged:
				# Make it almost double size (1.8x)
				landing_indicator.scale = Vector2(1.8, 1.8) 
				landing_indicator.color = Color(0.8, 0, 0, 0.6) # Darker Red
			else:
				# Normal size
				landing_indicator.scale = Vector2(1.0, 1.0)
				landing_indicator.color = Color(1, 0, 0, 0.4)
			
			# 2. Make Boss Invincible
			$CollisionShape2D.disabled = true
			
			# 3. Wait 1.5 seconds
			state_timer.start(1.5) 
			
		JUMP_CRASH:
			# Teleport boss to the circle
			global_position = landing_indicator.global_position
			state_timer.start(0.3) # Slam speed
			
		SHOCKWAVE:
			fire_shockwave()
			state_timer.start(1.5)
			
		CHARGE:
			var dir = position.direction_to(player.position)
			velocity = dir * 350
			state_timer.start(1.5)

func _on_state_timer_timeout():
	match state:
		IDLE: pick_random_state()
		JUMP_PREP: enter_state(JUMP_AIR)
		JUMP_AIR: enter_state(JUMP_CRASH)
		JUMP_CRASH: 
			land_impact() 
			enter_state(IDLE)
		SHOCKWAVE: enter_state(IDLE)
		CHARGE: 
			velocity = Vector2.ZERO
			enter_state(IDLE)

# --- ATTACKS ---

func land_impact():
	$CollisionShape2D.disabled = false
	landing_indicator.visible = false
	
	# Explosion of bullets
	var count = 12
	for i in range(count):
		var angle = i * (TAU / count)
		var dir = Vector2(cos(angle), sin(angle))
		spawn_bullet(dir, 300)
	
	# --- NEW DAMAGE LOGIC ---
	var hit_radius = 160 # Base radius + small buffer
	if is_enraged:
		hit_radius = 160 * 1.8 # Scale the hitbox to match the huge circle
	
	var dist = global_position.distance_to(player.global_position)
	
	if dist < hit_radius: 
		if player.has_method("take_damage"):
			player.take_damage(2)

func fire_shockwave():
	# Stomp
	var t = create_tween()
	t.tween_property(visuals, "position:y", -30.0, 0.2)
	t.tween_property(visuals, "position:y", 0.0, 0.1) 
	
	await get_tree().create_timer(0.3).timeout
	
	# Wall of bullets
	var count = 20
	for i in range(count):
		var angle = i * (TAU / count)
		var dir = Vector2(cos(angle), sin(angle))
		spawn_bullet(dir, 180) 

func spawn_bullet(dir, speed):
	var b = projectile_scene.instantiate()
	b.speed = speed
	b.setup(global_position, dir, "Boss")
	get_parent().add_child(b)

# --- DAMAGE ---

func take_damage(amount):
	if state == JUMP_AIR: return # Invincible in air
	
	hp -= amount
	if health_bar: health_bar.value = hp
	
	# Flash
	sprite.modulate = Color(10, 10, 10)
	var t = create_tween()
	t.tween_interval(0.05)
	t.tween_callback(update_color)
	
	if hp <= max_hp / 2 and not is_enraged:
		activate_rage()
	if hp <= 0:
		die()

func update_color():
	if is_enraged:
		sprite.modulate = Color(2, 0.2, 0.2)
		return
	match state:
		JUMP_PREP: sprite.modulate = Color.ORANGE
		CHARGE: sprite.modulate = Color.RED
		_: sprite.modulate = Color.WHITE

func activate_rage():
	is_enraged = true
	var t = create_tween()
	t.tween_property(self, "scale", Vector2(1.3, 1.3), 0.5)
	update_color()

func die():
	set_physics_process(false)
	state_timer.stop()
	if landing_indicator: landing_indicator.queue_free()
	if health_bar: health_bar.get_parent().visible = false
	
	var t = create_tween()
	t.tween_property(self, "rotation", 10.0, 1.0)
	t.parallel().tween_property(self, "scale", Vector2.ZERO, 1.0)
	await t.finished
	queue_free()
