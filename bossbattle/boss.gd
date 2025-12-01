extends CharacterBody2D

# --- CONFIGURATION ---
enum {IDLE, LASER_AIM, LASER_LOCK, LASER_FIRE, VANISH, AMBUSH, SPIN_ATTACK}
var state = IDLE

# Stats
var max_hp = 50
var hp = max_hp
var is_enraged = false

# Laser Config
var laser_line : Line2D

# --- REFERENCES ---
@onready var player = get_tree().get_first_node_in_group("Player")
@onready var visuals = $Visuals
@onready var sprite = $Visuals/Sprite2D
@onready var state_timer = $StateTimer

# DRAG HEALTHBAR HERE!
@export var health_bar : ProgressBar 

var projectile_scene = preload("res://projectile.tscn")

func _ready():
	# 1. SETUP TIMER
	if not state_timer.timeout.is_connected(_on_state_timer_timeout):
		state_timer.timeout.connect(_on_state_timer_timeout)
	
	# 2. SETUP UI
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = hp
	
	# 3. CREATE LASER SIGHT
	laser_line = Line2D.new()
	laser_line.width = 2
	laser_line.default_color = Color(1, 0, 0, 0) 
	get_parent().call_deferred("add_child", laser_line) 

	if player:
		add_collision_exception_with(player)
	
	await get_tree().create_timer(2.0).timeout
	
	pick_random_state()

func _physics_process(delta):
	if not player: return 
	
	# FLIP SPRITE (Only when visible)
	if sprite.modulate.a > 0.5:
		if player.global_position.x < global_position.x:
			visuals.scale.x = -1
		else:
			visuals.scale.x = 1

	# STATE LOGIC
	match state:
		IDLE:
			velocity = Vector2.ZERO
			laser_line.default_color = Color(1, 0, 0, 0)
			
		LASER_AIM:
			laser_line.default_color = Color(1, 0, 0, 0.5)
			laser_line.clear_points()
			laser_line.add_point(global_position)
			laser_line.add_point(player.global_position)
			
		LASER_LOCK:
			var locked_target = laser_line.get_point_position(1) 
			laser_line.clear_points()
			laser_line.add_point(global_position)
			laser_line.add_point(locked_target)
			laser_line.default_color = Color(10, 0, 0, 1) 
			
		VANISH:
			velocity = Vector2.ZERO
			laser_line.default_color = Color.TRANSPARENT
			
		SPIN_ATTACK:
			visuals.rotation += 15.0 * delta

func _exit_tree():
	if laser_line: laser_line.queue_free()

# --- TRANSITIONS ---

func pick_random_state():
	visuals.rotation = 0 
	sprite.modulate.a = 1.0 
	
	var roll = randf()
	if roll < 0.4: enter_state(LASER_AIM)
	elif roll < 0.7: enter_state(VANISH)
	else: enter_state(SPIN_ATTACK)

func enter_state(new_state):
	state = new_state
	update_color()
	
	match state:
		IDLE:
			state_timer.start(1.0)
			
		LASER_AIM:
			state_timer.start(1.5)
			
		LASER_LOCK:
			state_timer.start(0.4)
			
		LASER_FIRE:
			fire_railgun()
			state_timer.start(0.5) 
			
		VANISH:
			var t = create_tween()
			t.tween_property(sprite, "modulate:a", 0.0, 0.5)
			state_timer.start(1.0) 
			
		AMBUSH:
			teleport_behind_player()
			# --- NERF APPLIED HERE ---
			state_timer.start(1.2) # Gives player 1.2s to react
			
		SPIN_ATTACK:
			state_timer.start(2.0)
			fire_spiral_chaos()

func _on_state_timer_timeout():
	match state:
		IDLE: pick_random_state()
		LASER_AIM: enter_state(LASER_LOCK)
		LASER_LOCK: enter_state(LASER_FIRE)
		LASER_FIRE: enter_state(IDLE)
		VANISH: enter_state(AMBUSH)
		AMBUSH: 
			fire_shotgun_blast()
			enter_state(IDLE)
		SPIN_ATTACK: 
			visuals.rotation = 0
			enter_state(IDLE)

# --- ATTACKS ---

func fire_railgun():
	var target = laser_line.get_point_position(1)
	var dir = position.direction_to(target)
	spawn_bullet(dir, 1500, 3)
	visuals.position = dir * -15
	var t = create_tween()
	t.tween_property(visuals, "position", Vector2.ZERO, 0.2)
	laser_line.default_color = Color.TRANSPARENT

func teleport_behind_player():
	if not player: return
	
	# --- NERF APPLIED HERE ---
	# Distance increased to 180 (was 100)
	var dir_to_player = position.direction_to(player.position)
	var ambush_pos = player.position + (dir_to_player * 180)
	
	global_position = ambush_pos
	
	# --- NERF VISUALS ---
	sprite.modulate.a = 1.0
	sprite.modulate = Color(10, 10, 0) # Flash Yellow Warning
	
	var t = create_tween()
	t.tween_property(sprite, "modulate", get_state_color(), 1.0)

func fire_shotgun_blast():
	if not player: return
	var dir = position.direction_to(player.position)
	for i in range(5):
		var angle = deg_to_rad(-30 + (i * 15))
		spawn_bullet(dir.rotated(angle), 600, 1)

func fire_spiral_chaos():
	var t = create_tween()
	t.set_loops(20)
	t.tween_callback(shoot_spiral_bullet).set_delay(0.1)

func shoot_spiral_bullet():
	var dir = Vector2.RIGHT.rotated(visuals.rotation)
	spawn_bullet(dir, 400, 1)
	spawn_bullet(-dir, 400, 1) 

func spawn_bullet(dir, speed, dmg):
	var b = projectile_scene.instantiate()
	b.speed = speed
	b.damage = dmg
	b.setup(global_position, dir, "Boss")
	get_parent().add_child(b)

# --- HEALTH ---

func take_damage(amount):
	hp -= amount
	if health_bar: health_bar.value = hp
	
	# Flash White
	var prev_a = sprite.modulate.a
	sprite.modulate = Color(10, 10, 10, prev_a)
	var t = create_tween()
	t.tween_interval(0.05)
	t.tween_callback(update_color)
	
	if hp <= max_hp / 2 and not is_enraged:
		is_enraged = true
		activate_rage()
	if hp <= 0:
		die()

func update_color():
	var a = sprite.modulate.a 
	sprite.modulate = get_state_color()
	sprite.modulate.a = a

func get_state_color():
	if is_enraged: return Color(2, 0.2, 0.2)
	match state:
		LASER_LOCK: return Color(10, 0, 0)
		VANISH: return Color(0.2, 0.2, 0.2)
		AMBUSH: return Color.YELLOW
		SPIN_ATTACK: return Color.CYAN
		_: return Color.WHITE

func activate_rage():
	var t = create_tween()
	t.tween_property(self, "scale", Vector2(1.2, 1.2), 0.5)

func die():
	if laser_line: laser_line.queue_free()
	set_physics_process(false)
	state_timer.stop()
	if health_bar: health_bar.get_parent().visible = false
	var t = create_tween()
	t.tween_property(self, "rotation", 10.0, 1.0)
	t.parallel().tween_property(self, "scale", Vector2.ZERO, 1.0)
	await t.finished
	queue_free()
