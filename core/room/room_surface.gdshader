shader_type canvas_item;
render_mode blend_mix;

// Перспективно корректная укладка повторяющейся текстуры на поверхность комнаты.
//
// Полигон, который рисуется, ничего не знает о раскладке: координата
// поверхности считается ИЗ ПОЗИЦИИ ПИКСЕЛЯ обратной гомографией. Поэтому
// плитка у дальнего края пола честно уменьшается, а не ломается по диагонали
// треугольника, как это делает аффинная интерполяция UV в Polygon2D.
//
// Обратная матрица приходит тремя строками, а не одним mat3: перевод Basis в
// mat3 транспонирует, и такая ошибка не видна глазом — она просто слегка
// перекашивает раскладку.

uniform sampler2D tex : repeat_enable, filter_linear_mipmap;
uniform vec3 inv_r0 = vec3(1.0, 0.0, 0.0);
uniform vec3 inv_r1 = vec3(0.0, 1.0, 0.0);
uniform vec3 inv_r2 = vec3(0.0, 0.0, 1.0);
// Сколько раз плитка укладывается по поверхности. Считается на CPU как
// «размер поверхности в единицах комнаты / размер плитки», поэтому замена PNG
// на более крупный ничего в кадре не двигает.
uniform vec2 tiling = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec2 room_pos;

void vertex() {
	room_pos = VERTEX;
}

void fragment() {
	vec3 p = vec3(room_pos, 1.0);
	float w = dot(inv_r2, p);
	// За линией горизонта отображение переворачивается: там поверхности уже нет.
	if (w <= 0.0001) {
		discard;
	}
	vec2 st = vec2(dot(inv_r0, p), dot(inv_r1, p)) / w;
	COLOR = texture(tex, st * tiling + uv_offset) * tint;
}
