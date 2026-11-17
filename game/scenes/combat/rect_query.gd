class_name RectQuery
extends RefCounted
## 可复用的范围查询：shape / query 只在构造时建一次，之后改尺寸和位置就行
## 木桩和 Boss 的「身前一盒」判定用矩形；逆鳞的圆形范围用 circle_bodies

var shape := RectangleShape2D.new()
var query := PhysicsShapeQueryParameters2D.new()

var _circle := CircleShape2D.new()
var _circle_query := PhysicsShapeQueryParameters2D.new()


func _init() -> void:
	query.shape = shape
	query.collide_with_areas = false
	query.collide_with_bodies = true
	_circle_query.shape = _circle
	_circle_query.collide_with_areas = false
	_circle_query.collide_with_bodies = true


## 以 center 为中心、size 为尺寸查一次物理空间，返回命中的节点
func bodies(space: PhysicsDirectSpaceState2D, center: Vector2, size: Vector2,
		mask: int, max_results := 8) -> Array[Node]:
	shape.size = size
	query.transform = Transform2D(0.0, center)
	query.collision_mask = mask
	return _colliders(space.intersect_shape(query, max_results))


## 以 center 为圆心、radius 为半径查一次，返回命中的节点
func circle_bodies(space: PhysicsDirectSpaceState2D, center: Vector2, radius: float,
		mask: int, max_results := 8) -> Array[Node]:
	_circle.radius = radius
	_circle_query.transform = Transform2D(0.0, center)
	_circle_query.collision_mask = mask
	return _colliders(space.intersect_shape(_circle_query, max_results))


func _colliders(hits: Array[Dictionary]) -> Array[Node]:
	var out: Array[Node] = []
	for hit in hits:
		var node := hit.get("collider") as Node
		if node != null:
			out.append(node)
	return out
