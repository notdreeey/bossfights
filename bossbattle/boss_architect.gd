extends CharacterBody2D


# --- CONFIGURATION ---
enum {IDLE, MINEFIELD, X_BLAST, SQUARE_PATROL}
var state = IDLE

# Stats
var max_hp = 60
var hp = max_hp
var is_enraged = false

# Movement Config
var square_step = 0 

# References
@onready var player = get_tree().get_first_node_in_group("Player")
@onready var visuals = $Visuals
@onready var sprite = $Visuals/Sprite2D
@onready var state_timer = $StateTimer


# UI
@export var health_bar : ProgressBar 

# Resources
var projectile_scene = preload("res://projectile.tscn")

# Store mines
var active_mines = []

func _ready():
	if not state_timer.timeout.is_connected(_on_state_timer_timeout):
		state_timer.timeout.connect(_on_state_timer_timeout)
	
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = hp
		var style = health_bar.get_theme_stylebox("fill")
		if style: style.bg_color = Color.YELLOW
		
		await get_tree().create_timer(2.0).timeout
	
	if player:
		add_collision_exception_with(player)
		
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
		MINEFIELD:
			velocity = Vector2.ZERO
		X_BLAST:
			velocity = Vector2.ZERO
		SQUARE_PATROL:
			move_and_slide()

# --- TRANSITIONS ---

func pick_random_state():
	visuals.rotation = 0
	
	var roll = randf()
	if roll < 0.5: enter_state(MINEFIELD)
	elif roll < 0.8: enter_state(X_BLAST)
	else: enter_state(SQUARE_PATROL)

func enter_state(new_state):
	state = new_state
	update_color() 
	
	match state:
		IDLE:
			state_timer.start(0.8) 
		MINEFIELD:
			sprite.modulate = Color.YELLOW
			spawn_diamond_mines()
			state_timer.start(2.0) 
		X_BLAST:
			sprite.modulate = Color.CYAN
			fire_x_pattern()
			state_timer.start(2.0)
		SQUARE_PATROL:
			sprite.modulate = Color.ORANGE
			square_step = 0
			do_square_move()
			state_timer.start(3.0) 

func _on_state_timer_timeout():
	match state:
		IDLE: pick_random_state()
		MINEFIELD: 
			detonate_mines()
			enter_state(IDLE)
		X_BLAST: enter_state(IDLE)
		SQUARE_PATROL: enter_state(IDLE)

# --- ATTACKS ---

func spawn_diamond_mines():
	active_mines.clear()
	# Spawn 5 mines
	for i in range(5):
		create_diamond_visual()
		await get_tree().create_timer(0.1).timeout

func create_diamond_visual():
	var mine = Polygon2D.new()
	var points = PackedVector2Array()
	points.append(Vector2(0, -25))
	points.append(Vector2(25, 0))
	points.append(Vector2(0, 25))
	points.append(Vector2(-25, 0))
	mine.polygon = points
	mine.color = Color(1, 1, 0, 0.5)
	
	var offset = Vector2(randf_range(-250, 250), randf_range(-250, 250))
	mine.global_position = player.global_position + offset
	
	get_parent().add_child(mine)
	active_mines.append(mine)
	
	var t = create_tween()
	t.set_loops()
	t.tween_property(mine, "scale", Vector2(1.2, 1.2), 0.2)
	t.tween_property(mine, "scale", Vector2(1.0, 1.0), 0.2)

func detonate_mines():
	for mine in active_mines:
		if not is_instance_valid(mine): continue
		
		# --- CHANGED LOGIC HERE ---
		if not is_enraged:
			# NORMAL MODE: 4 Directions (Cross)
			# Safe spots are diagonal
			var cardinal_dirs = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
			for dir in cardinal_dirs:
				spawn_bullet(mine.global_position, dir, 220)
				
		else:
			# RAGE MODE: 8 Directions (Circle)
			# Shoots "Everywhere"
			var count = 8
			for i in range(count):
				var angle = i * (TAU / count)
				var dir = Vector2(cos(angle), sin(angle))
				spawn_bullet(mine.global_position, dir, 220)
		
		mine.queue_free()
	active_mines.clear()

func fire_x_pattern():
	var diagonals = [Vector2(1,1), Vector2(-1,1), Vector2(-1,-1), Vector2(1,-1)]
	
	for i in range(15): 
		if state != X_BLAST: break
		for dir in diagonals:
			spawn_bullet(global_position, dir, 400)
		await get_tree().create_timer(0.1).timeout

func do_square_move():
	if state != SQUARE_PATROL: return
	
	var move_dir = Vector2.ZERO
	if square_step == 0: move_dir = Vector2.RIGHT
	elif square_step == 1: move_dir = Vector2.DOWN
	elif square_step == 2: move_dir = Vector2.LEFT
	elif square_step == 3: move_dir = Vector2.UP
	
	velocity = move_dir * 350
	
	var aim_dir = position.direction_to(player.position)
	spawn_bullet(global_position, aim_dir, 400)
	spawn_bullet(global_position, aim_dir.rotated(0.2), 400) 
	spawn_bullet(global_position, aim_dir.rotated(-0.2), 400) 
	
	square_step += 1
	if square_step > 3: square_step = 0
	
	var t = get_tree().create_timer(0.5)
	t.timeout.connect(do_square_move)

func spawn_bullet(start_pos, dir, speed):
	var b = projectile_scene.instantiate()
	b.speed = speed
	b.modulate = Color.YELLOW
	b.setup(start_pos, dir, "Boss")
	get_parent().add_child(b)

# --- DAMAGE ---

func take_damage(amount):
	hp -= amount
	if health_bar: health_bar.value = hp
	
	# Flash White
	var prev_mod = sprite.modulate
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
		sprite.modulate = Color.RED
		return
		
	match state:
		MINEFIELD: sprite.modulate = Color.YELLOW
		X_BLAST: sprite.modulate = Color.CYAN
		SQUARE_PATROL: sprite.modulate = Color.ORANGE
		_: sprite.modulate = Color.WHITE

func activate_rage():
	is_enraged = true
	var t = create_tween()
	t.tween_property(self, "scale", Vector2(1.2, 1.2), 0.5)
	update_color()

func die():
	set_physics_process(false)
	state_timer.stop()
	for m in active_mines: if is_instance_valid(m): m.queue_free()
	if health_bar: health_bar.get_parent().visible = false
	
	var t = create_tween()
	t.tween_property(self, "rotation", 10.0, 1.0)
	t.parallel().tween_property(self, "scale", Vector2.ZERO, 1.0)
	await t.finished
	queue_free()
