extends CharacterBody2D

# --- CONFIGURATION ---
# CHANGED: Replaced GALAXY_SPIN with DARK_PULSE
enum {IDLE, DARK_PULSE, VOID_RAILGUN, BLINK_STRIKE}
var state = IDLE

# Stats
var max_hp = 70
var hp = max_hp
var is_enraged = false

# Blink Config
var blink_count = 0

# Railgun Config
var railgun_line : Line2D

# Start Delay
@export var start_delay : float = 2.0 

# References
@onready var player = get_tree().get_first_node_in_group("Player")
@onready var visuals = $Visuals
@onready var sprite = $Visuals/Sprite2D
@onready var state_timer = $StateTimer

# UI
@export var health_bar : ProgressBar 

var projectile_scene = preload("res://projectile.tscn")

func _ready():
	# 1. SETUP TIMER
	if not state_timer.timeout.is_connected(_on_state_timer_timeout):
		state_timer.timeout.connect(_on_state_timer_timeout)
	state_timer.one_shot = true

	if player:
		add_collision_exception_with(player)

	# 2. SETUP UI
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = hp
		var style = health_bar.get_theme_stylebox("fill")
		if style: style.bg_color = Color.BLACK 

	# 3. GENERATE RAILGUN LINE
	railgun_line = Line2D.new()
	railgun_line.width = 3
	railgun_line.default_color = Color(0.5, 0, 1, 0) 
	get_parent().call_deferred("add_child", railgun_line)

	# 4. START SEQUENCE
	state = IDLE
	velocity = Vector2.ZERO
	
	sprite.modulate = Color.BLACK
	var t = create_tween()
	t.tween_property(sprite, "modulate", Color.WHITE, 1.0)
	
	await get_tree().create_timer(start_delay).timeout
	
	if is_instance_valid(self):
		pick_state()

func _physics_process(_delta):
	if not player: return

	# FLIP SPRITE
	if player.global_position.x < global_position.x:
		visuals.scale.x = -1
	else:
		visuals.scale.x = 1

# --- STATE MACHINE ---

func enter_state(s):
	state = s
	update_color()
	
	match s:
		IDLE:
			visuals.rotation = 0
			railgun_line.default_color = Color.TRANSPARENT
			state_timer.start(1.0)

		DARK_PULSE:
			# Replaced the Spin with Pulses
			do_dark_pulses()
			# Timer handled in function

		VOID_RAILGUN:
			do_railgun_sequence()
			# Timer handled in sequence

		BLINK_STRIKE:
			blink_count = 0
			do_next_blink()

func pick_state():
	var r = randf()
	if r < 0.4:
		enter_state(DARK_PULSE)
	elif r < 0.7:
		enter_state(BLINK_STRIKE)
	else:
		enter_state(VOID_RAILGUN)

func _on_state_timer_timeout():
	if state == IDLE:
		pick_state()

# --- ATTACKS ---

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

# 1. DARK PULSE (New Balanced Attack)
# Shoots 3 Rings with a delay between them.
func do_dark_pulses():
	sprite.modulate = Color.BLACK
	
	var waves = 3
	if is_enraged: waves = 5
	
	for w in range(waves):
		if not player: break
		
		var count = 12
		# Offset angle every other wave so the gaps move
		var wave_offset = w * (PI / 12) 
		
		for i in range(count):
			var angle = (i * (TAU / count)) + wave_offset
			var dir = Vector2(cos(angle), sin(angle))
			spawn_bullet(global_position, dir, 220)
		
		# Juice: Pulse Effect
		var t = create_tween()
		t.tween_property(visuals, "scale", Vector2(1.2, 1.2), 0.1)
		t.tween_property(visuals, "scale", Vector2(1.0, 1.0), 0.1)
		
		# Wait 0.6 seconds before next wave (Plenty of time to dodge)
		await get_tree().create_timer(0.6).timeout
		
	enter_state(IDLE)

# 2. VOID RAILGUN
func do_railgun_sequence():
	sprite.modulate = Color.CYAN
	
	# Tracking (1.5s)
	var duration = 1.5
	var elapsed = 0.0
	while elapsed < duration:
		if not player: break
		railgun_line.default_color = Color(0.5, 0, 1, 0.5) 
		railgun_line.clear_points()
		railgun_line.add_point(global_position)
		var dir = global_position.direction_to(player.global_position)
		railgun_line.add_point(global_position + (dir * 2000))
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		
	# LOCK (0.5s)
	railgun_line.default_color = Color(1, 0.2, 1, 1) 
	await get_tree().create_timer(0.5).timeout
	
	# FIRE
	if railgun_line.get_point_count() > 1:
		var target_pos = railgun_line.get_point_position(1)
		var fire_dir = global_position.direction_to(target_pos)
		
		var t = create_tween()
		t.tween_property(visuals, "position", fire_dir * -20, 0.1)
		t.tween_property(visuals, "position", Vector2.ZERO, 0.2)
		
		for i in range(10):
			spawn_bullet(global_position, fire_dir, 800)
			await get_tree().create_timer(0.05).timeout
			
	railgun_line.default_color = Color.TRANSPARENT
	enter_state(IDLE)

# 3. BLINK STRIKE
func do_next_blink():
	if state != BLINK_STRIKE: return
	
	if blink_count < 3:
		blink_count += 1
		
		# 1. Vanish
		var t = create_tween()
		t.tween_property(self, "scale", Vector2.ZERO, 0.2)
		await t.finished
		
		# 2. Calculate Position
		var offset = Vector2(randf_range(-200, 200), randf_range(-200, 200))
		var target_pos = player.global_position + offset
		
		# --- SHOW INDICATOR ---
		show_teleport_indicator(target_pos)
		# Wait a tiny bit so player sees the indicator before boss arrives
		await get_tree().create_timer(0.2).timeout
		
		# 3. Teleport & Appear
		global_position = target_pos
		var t2 = create_tween()
		t2.tween_property(self, "scale", Vector2(1, 1), 0.2)
		await t2.finished
		
		# Warning & Fire
		sprite.modulate = Color(5, 0, 5) 
		await get_tree().create_timer(0.4).timeout # Slightly reduced delay since we have indicator now
		
		fire_ring()
		sprite.modulate = Color.WHITE
		
		await get_tree().create_timer(0.2).timeout
		do_next_blink()
	else:
		enter_state(IDLE)

func fire_ring():
	var count = 8
	for i in range(count):
		var angle = i * (TAU / count)
		var dir = Vector2(cos(angle), sin(angle))
		spawn_bullet(global_position, dir, 300)

# --- HELPER ---

func spawn_bullet(pos, dir, speed_val):
	var b = projectile_scene.instantiate()
	b.speed = speed_val
	
	if state == DARK_PULSE: b.modulate = Color.BLACK
	elif state == VOID_RAILGUN: b.modulate = Color.MAGENTA
	elif state == BLINK_STRIKE: b.modulate = Color.PURPLE
	
	b.setup(pos, dir, "Boss")
	get_parent().add_child(b)

func _exit_tree():
	if railgun_line: railgun_line.queue_free()

# --- DAMAGE ---

func take_damage(amount):
	hp -= amount
	if health_bar: health_bar.value = hp
	
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
		sprite.modulate = Color(0.2, 0.2, 0.2) 
		return
	
	match state:
		DARK_PULSE: sprite.modulate = Color.BLACK
		VOID_RAILGUN: sprite.modulate = Color.CYAN
		BLINK_STRIKE: sprite.modulate = Color.PURPLE
		_: sprite.modulate = Color.WHITE

func activate_rage():
	is_enraged = true
	var t = create_tween()
	t.tween_property(self, "scale", Vector2(1.2, 1.2), 0.5)
	update_color()

func die():
	set_physics_process(false)
	state_timer.stop()
	if railgun_line: railgun_line.queue_free()
	if health_bar: health_bar.get_parent().visible = false
	
	var t = create_tween()
	t.tween_property(self, "rotation", 10.0, 1.0)
	t.parallel().tween_property(self, "scale", Vector2.ZERO, 1.0)
	await t.finished
	queue_free()
