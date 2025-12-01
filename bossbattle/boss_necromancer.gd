extends CharacterBody2D

# --- CONFIGURATION ---
enum {IDLE, SKULL_BARRAGE, CURSED_EARTH, SUMMON_WALL, TELEPORT_AWAY}
var state = IDLE

# Stats
var max_hp = 50 
var hp = max_hp
var is_enraged = false

# References
@onready var player = get_tree().get_first_node_in_group("Player")
@onready var visuals = $Visuals
@onready var sprite = $Visuals/Sprite2D
@onready var state_timer = $StateTimer

# UI (Drag your HealthBar here!)
@export var health_bar : ProgressBar 

# Resources
var projectile_scene = preload("res://projectile.tscn")
var minion_scene = preload("res://skeleton.tscn")

# Store blast zones to delete them later
var active_blast_zones = []

func _ready():
	# 1. Connect Timer
	if not state_timer.timeout.is_connected(_on_state_timer_timeout):
		state_timer.timeout.connect(_on_state_timer_timeout)
	
	# 2. Setup UI
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = hp
		var style = health_bar.get_theme_stylebox("fill")
		if style: style.bg_color = Color.PURPLE
		
	# 3. Start Delay & Collisions
	if player:
		add_collision_exception_with(player)
	
	# Wait 2 seconds before starting
	await get_tree().create_timer(2.0).timeout
	
	pick_random_state()

func _physics_process(delta):
	if not player: return 

	# FLIP SPRITE
	if player.global_position.x < global_position.x:
		visuals.scale.x = -1
	else:
		visuals.scale.x = 1

	match state:
		IDLE:
			velocity = Vector2.ZERO
		SKULL_BARRAGE:
			velocity = Vector2.ZERO
		CURSED_EARTH:
			velocity = Vector2.ZERO
		SUMMON_WALL:
			velocity = Vector2.ZERO
		TELEPORT_AWAY:
			velocity = Vector2.ZERO

# --- TRANSITIONS ---

func pick_random_state():
	visuals.rotation = 0
	
	# AI Logic: If player is too close, Teleport away
	if global_position.distance_to(player.global_position) < 120:
		enter_state(TELEPORT_AWAY)
		return

	var roll = randf()
	if roll < 0.4: enter_state(SKULL_BARRAGE) # Common attack
	elif roll < 0.7: enter_state(CURSED_EARTH)
	else: enter_state(SUMMON_WALL)

func enter_state(new_state):
	state = new_state
	update_color()
	
	match state:
		IDLE:
			state_timer.start(1.0)
			
		SKULL_BARRAGE:
			sprite.modulate = Color.GREEN
			fire_skull_barrage()
			state_timer.start(1.5) 
			
		CURSED_EARTH:
			sprite.modulate = Color.RED
			spawn_blast_zones()
			state_timer.start(1.5) 
			
		SUMMON_WALL:
			sprite.modulate = Color.PURPLE
			summon_wall_of_flesh()
			state_timer.start(1.0)
			
		TELEPORT_AWAY:
			do_teleport()
			state_timer.start(0.5)

func _on_state_timer_timeout():
	match state:
		IDLE: pick_random_state()
		SKULL_BARRAGE: pick_random_state()
		CURSED_EARTH: 
			detonate_blast_zones()
			enter_state(IDLE)
		SUMMON_WALL: pick_random_state()
		TELEPORT_AWAY: pick_random_state()

# --- ATTACKS ---

func fire_skull_barrage():
	# NEW ATTACK: Shoots 5 bullets directly at player in a rhythm
	var count = 5
	if is_enraged: count = 8
	
	for i in range(count):
		if not player: break
		
		var dir = position.direction_to(player.position)
		
		# Add a tiny bit of inaccuracy so it's not a perfect laser beam
		var spread = randf_range(-0.1, 0.1)
		spawn_bullet(dir.rotated(spread), 350)
		
		# Wait 0.1s between shots (Machine gun style)
		await get_tree().create_timer(0.15).timeout

func spawn_blast_zones():
	active_blast_zones.clear()
	# Create 5 random circles
	for i in range(5):
		var zone = Polygon2D.new()
		var points = PackedVector2Array()
		for j in range(16):
			var angle = j * (TAU / 16)
			points.append(Vector2(cos(angle), sin(angle)) * 40) # 40px radius
		zone.polygon = points
		zone.color = Color(1, 0, 0, 0.4) 
		
		var offset = Vector2(randf_range(-200, 200), randf_range(-200, 200))
		zone.global_position = player.global_position + offset
		
		get_parent().add_child(zone)
		active_blast_zones.append(zone)

func detonate_blast_zones():
	for zone in active_blast_zones:
		if not is_instance_valid(zone): continue
		
		# Visual Flare
		var t = create_tween()
		t.tween_property(zone, "color", Color(1, 1, 1, 1), 0.1)
		t.tween_callback(zone.queue_free)
		
		# Damage Check
		var dist = zone.global_position.distance_to(player.global_position)
		if dist < 50: 
			if player.has_method("take_damage"):
				player.take_damage(1)
	
	active_blast_zones.clear()

func summon_wall_of_flesh():
	# Spawn 4 minions in a line
	var start_pos = global_position - Vector2(100, 0)
	# If enraged, summon more
	var count = 4 if not is_enraged else 6
	
	for i in range(count):
		var minion = minion_scene.instantiate()
		# Line them up horizontally
		minion.global_position = start_pos + Vector2(i * 50, 50)
		get_parent().add_child(minion)

func do_teleport():
	# 1. Vanish
	var t = create_tween()
	t.tween_property(self, "scale", Vector2.ZERO, 0.2)
	await t.finished
	
	# 2. Calculate Pos
	var offset = Vector2(randf_range(-200, 200), randf_range(-200, 200))
	var target_pos = player.global_position + offset
	
	# --- SHOW INDICATOR ---
	show_teleport_indicator(target_pos)
	await get_tree().create_timer(0.2).timeout
	
	# 3. Move & Appear
	global_position = target_pos
	var t2 = create_tween()
	t2.tween_property(self, "scale", Vector2(1, 1), 0.2)

# --- MISSING FUNCTION ADDED HERE ---
func spawn_bullet(dir, speed):
	var b = projectile_scene.instantiate()
	b.speed = speed
	b.modulate = Color.GREEN 
	b.setup(global_position, dir, "Boss")
	get_parent().add_child(b)

# --- DAMAGE & HEALTH ---

func take_damage(amount):
	hp -= amount
	if health_bar: health_bar.value = hp
	
	# Flash White
	var prev_mod = sprite.modulate
	sprite.modulate = Color(10, 10, 10)
	var t = create_tween()
	t.tween_interval(0.05)
	t.tween_callback(func(): update_color())
	
	if hp <= max_hp / 2 and not is_enraged:
		activate_rage()
	if hp <= 0:
		die()

func update_color():
	if is_enraged:
		sprite.modulate = Color(0.5, 0, 0.5) # Rage Purple
		return
	
	match state:
		SKULL_BARRAGE: sprite.modulate = Color.GREEN
		CURSED_EARTH: sprite.modulate = Color.RED
		SUMMON_WALL: sprite.modulate = Color.PURPLE
		_: sprite.modulate = Color.WHITE

func activate_rage():
	is_enraged = true
	var t = create_tween()
	t.tween_property(self, "scale", Vector2(1.2, 1.2), 0.5)
	update_color()

func die():
	set_physics_process(false)
	state_timer.stop()
	# Clean up blast zones
	for z in active_blast_zones: if is_instance_valid(z): z.queue_free()
	
	if health_bar: health_bar.get_parent().visible = false
	
	var t = create_tween()
	t.tween_property(self, "rotation", -10.0, 1.0)
	t.parallel().tween_property(self, "scale", Vector2.ZERO, 1.0)
	await t.finished
	queue_free()

func show_teleport_indicator(target_pos):
	var indicator = Polygon2D.new()
	var points = PackedVector2Array()
	# Draw a circle
	for i in range(16):
		var angle = i * (TAU / 16)
		points.append(Vector2(cos(angle), sin(angle)) * 40) # 40px radius
	indicator.polygon = points
	indicator.color = Color(1, 1, 1, 0.5) # Semi-transparent White
	indicator.global_position = target_pos
	
	get_parent().add_child(indicator)
	
	# Animate: Shrink and Fade out
	var t = create_tween()
	t.tween_property(indicator, "scale", Vector2.ZERO, 0.5)
	t.parallel().tween_property(indicator, "color", Color(1, 1, 1, 0), 0.5)
	t.tween_callback(indicator.queue_free)
