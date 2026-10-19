extends Control

var kind := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_kind(next: String) -> void:
	kind = next
	queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	var origin := (size - Vector2(side, side)) * 0.5
	match kind:
		"pipe":
			_pipe(origin, side)
		"stopwatch":
			_watch(origin, side)
		"flag":
			_flag(origin, side)
		"medal":
			_medal(origin, side)


func _pipe(origin: Vector2, side: float) -> void:
	var body := Rect2(origin.x + side * 0.34, origin.y + side * 0.22, side * 0.32, side * 0.62)
	draw_rect(Rect2(body.position.x - side * 0.04, body.position.y - side * 0.02, body.size.x + side * 0.08, body.size.y + side * 0.04), Color(0.05, 0.16, 0.22))
	draw_rect(body, Color(0.35, 0.78, 0.62))
	draw_rect(Rect2(body.position.x + side * 0.05, body.position.y + side * 0.04, side * 0.07, body.size.y - side * 0.08), Color(0.62, 0.92, 0.78))
	var lip := Rect2(origin.x + side * 0.24, origin.y + side * 0.14, side * 0.52, side * 0.16)
	draw_rect(Rect2(lip.position.x - side * 0.03, lip.position.y - side * 0.02, lip.size.x + side * 0.06, lip.size.y + side * 0.04), Color(0.05, 0.16, 0.22))
	draw_rect(lip, Color(0.45, 0.86, 0.58))
	draw_rect(Rect2(origin.x + side * 0.3, origin.y + side * 0.72, side * 0.4, side * 0.1), Color(0.28, 0.62, 0.48))


func _watch(origin: Vector2, side: float) -> void:
	var center := origin + Vector2(side * 0.5, side * 0.56)
	var radius := side * 0.3
	draw_circle(center, radius + side * 0.045, Color(0.04, 0.16, 0.28))
	draw_circle(center, radius, Color(0.9, 0.97, 1))
	draw_arc(center, radius * 0.78, 0.0, TAU, 24, Color(0.55, 0.78, 0.9), side * 0.025, true)
	draw_line(center, center + Vector2(0, -radius * 0.55), Color(0.08, 0.28, 0.45), side * 0.045, true)
	draw_line(center, center + Vector2(radius * 0.38, radius * 0.12), Color(0.95, 0.45, 0.2), side * 0.04, true)
	draw_circle(center, side * 0.035, Color(0.08, 0.28, 0.45))
	var crown := Rect2(center.x - side * 0.07, origin.y + side * 0.1, side * 0.14, side * 0.1)
	draw_rect(crown, Color(0.95, 0.72, 0.16), true)
	draw_rect(Rect2(crown.position.x + side * 0.03, crown.position.y - side * 0.05, side * 0.08, side * 0.06), Color(0.95, 0.72, 0.16), true)


func _flag(origin: Vector2, side: float) -> void:
	var pole_x := origin.x + side * 0.3
	draw_line(Vector2(pole_x, origin.y + side * 0.14), Vector2(pole_x, origin.y + side * 0.86), Color(0.98, 0.9, 0.62), side * 0.055, true)
	draw_circle(Vector2(pole_x, origin.y + side * 0.86), side * 0.04, Color(0.98, 0.9, 0.62))
	var cloth := PackedVector2Array([
		Vector2(pole_x + side * 0.02, origin.y + side * 0.18),
		Vector2(origin.x + side * 0.82, origin.y + side * 0.34),
		Vector2(pole_x + side * 0.02, origin.y + side * 0.5),
	])
	draw_colored_polygon(cloth, Color(1, 0.38, 0.45))
	draw_polyline(cloth + PackedVector2Array([cloth[0]]), Color(0.55, 0.08, 0.16), side * 0.03, true)


func _medal(origin: Vector2, side: float) -> void:
	var left := PackedVector2Array([
		Vector2(origin.x + side * 0.28, origin.y + side * 0.1),
		Vector2(origin.x + side * 0.42, origin.y + side * 0.1),
		Vector2(origin.x + side * 0.46, origin.y + side * 0.42),
		Vector2(origin.x + side * 0.3, origin.y + side * 0.42),
	])
	var right := PackedVector2Array([
		Vector2(origin.x + side * 0.58, origin.y + side * 0.1),
		Vector2(origin.x + side * 0.72, origin.y + side * 0.1),
		Vector2(origin.x + side * 0.7, origin.y + side * 0.42),
		Vector2(origin.x + side * 0.54, origin.y + side * 0.42),
	])
	draw_colored_polygon(left, Color(0.25, 0.58, 0.95))
	draw_colored_polygon(right, Color(0.95, 0.35, 0.48))
	var center := origin + Vector2(side * 0.5, side * 0.58)
	draw_circle(center, side * 0.28, Color(0.45, 0.24, 0.02))
	draw_circle(center, side * 0.24, Color(1, 0.82, 0.2))
	draw_circle(center, side * 0.16, Color(1, 0.92, 0.45))
	_star(center, side * 0.1, Color(0.85, 0.48, 0.05))


func _star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI * 0.5 + float(i) * PI / 5.0
		var reach := radius if i % 2 == 0 else radius * 0.45
		points.append(center + Vector2(cos(angle), sin(angle)) * reach)
	draw_colored_polygon(points, color)
