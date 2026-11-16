class_name RectQuery
extends RefCounted
## 可复用的矩形范围查询：shape / query 只在构造时建一次，之后改尺寸和位置就行
## 木桩和 Boss 的「身前一盒」判定共用这一份，避免在物理帧里反复 new

var shape := RectangleShape2D.new()
var query := PhysicsShapeQueryParameters2D.new()


func _init() -> void:
	query.shape = shape
	query.collide_with_areas = false
	query.collide_with_bodies = true


## 以 center 为中心、size 为尺寸查一次物理空间，返回命中的节点
func bodies(space: PhysicsDirectSpaceState2D, center: Vector2, size: Vector2,
		mask: int, max_results := 8) -> Array[Node]:
	shape.size = size
	query.transform = Transform2D(0.0, center)
	query.collision_mask = mask
	var out: Array[Node] = []
	for hit in space.intersect_shape(query, max_results):
		var node := hit.get("collider") as Node
		if node != null:
			out.append(node)
	return out
