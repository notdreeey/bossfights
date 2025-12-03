extends Area2D

var speed = 600
var damage = 1
var team = "" 
var direction = Vector2.RIGHT

func _ready():
	# 1. AUTO-CONNECT HIT DETECTION
	body_entered.connect(_on_body_entered)
	
	# 2. LIFETIME TIMER (The Fix)
	# We ONLY use time to delete bullets now.
	# This ensures bullets spawned off-screen still fly towards the player.
	await get_tree().create_timer(5.0).timeout
	queue_free()

func setup(pos, dir, my_team):
	global_position = pos
	direction = dir.normalized()
	team = my_team
	rotation = direction.angle()

func _physics_process(delta):
	position += direction * speed * delta

func _on_body_entered(body):
	# 1. FRIENDLY FIRE CHECKS
	# Player can't hit Player
	if team == "Player" and body.is_in_group("Player"): return
	
	# "Hostile" or "Boss" bullets should NOT hit "Hostile" or "Boss" units
	if (team == "Boss" or team == "Hostile") and (body.is_in_group("Boss") or body.is_in_group("Hostile")): 
		return

	# 2. HIT LOGIC
	if body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free() 
		return

	# 3. WALL LOGIC
	queue_free()
