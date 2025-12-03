extends CharacterBody2D

# --- STATS ---
var hp = 6
var speed = 110
var attack_range = 300.0   # Distance to stop and shoot
var flee_range = 120.0     # Distance to run away

# --- REFS ---
@onready var player = get_tree().get_first_node_in_group("Player")
@onready var sprite = $Sprite2D
@onready var shoot_timer = $ShootTimer

var projectile_scene = preload("res://projectile.tscn")
var can_shoot = true

func _ready():
	# Ensure the timer is connected
	if not shoot_timer.timeout.is_connected(_on_shoot_timer_timeout):
		shoot_timer.timeout.connect(_on_shoot_timer_timeout)

func _physics_process(delta):
	if not player: return
	
	var dist = global_position.distance_to(player.global_position)
	var dir = global_position.direction_to(player.global_position)
	
	# --- AI BEHAVIOR (Kiting) ---
	if dist > attack_range:
		# Too far? Chase.
		velocity = dir * speed
	elif dist < flee_range:
		# Too close? Run away!
		velocity = -dir * speed 
	else:
		# In good range? Stand still.
		velocity = Vector2.ZERO
		
	move_and_slide()
	
	# --- VISUALS ---
	# Face the player
	if player.global_position.x < global_position.x:
		sprite.flip_h = true  # Left
	else:
		sprite.flip_h = false # Right
		
	# --- ATTACK ---
	# Shoot if within range AND cooldown is ready
	if dist < attack_range + 50 and can_shoot:
		shoot()

func shoot():
	if not player: return
	
	can_shoot = false
	shoot_timer.start() # Reset cooldown
	
	var b = projectile_scene.instantiate()
	var dir = global_position.direction_to(player.global_position)
	
	# Slight inaccuracy
	var spread = randf_range(-0.1, 0.1)
	
	# Setup Bullet
	# team is "Hostile" so it hurts Player but ignores other Hostiles
	b.speed = 350 
	b.setup(global_position, dir.rotated(spread), "Hostile")
	get_parent().add_child(b)

func _on_shoot_timer_timeout():
	can_shoot = true

# --- DAMAGE ---
func take_damage(amount):
	hp -= amount
	
	# Flash Red
	modulate = Color.RED
	var t = create_tween()
	t.tween_property(self, "modulate", Color.WHITE, 0.1)
	
	if hp <= 0:
		die()

func die():
	queue_free()
