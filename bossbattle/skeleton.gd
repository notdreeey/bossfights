extends CharacterBody2D

var speed = 150
var hp = 2
@onready var player = get_tree().get_first_node_in_group("Player")

func _ready():
	# 1. Add to group automatically so Player can find me
	add_to_group("Enemies")
	
	# 2. Walk through Boss (Fix collision block)
	var boss = get_tree().get_first_node_in_group("Boss")
	if boss:
		add_collision_exception_with(boss)

func _physics_process(delta):
	if not player: return
	
	# Simple Chase
	var dir = position.direction_to(player.position)
	velocity = dir * speed
	move_and_slide()
	
	# Damage Player on touch
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var body = collision.get_collider()
		if body.is_in_group("Player"):
			if body.has_method("take_damage"):
				body.take_damage(1)
				die() 

func take_damage(amount):
	hp -= amount
	modulate = Color.RED 
	var t = create_tween()
	t.tween_property(self, "modulate", Color.GREEN, 0.1)
	
	if hp <= 0:
		die()

func die():
	queue_free()
