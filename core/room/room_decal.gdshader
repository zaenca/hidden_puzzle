shader_type canvas_item;
render_mode blend_mix;

// Одна картинка, натянутая на четырёхугольник поверхности: окно, дверь,
// трещина, плинтус, тень в углу.
//
// Тот же приём, что и у поверхности, но без повтора: координата считается
// обратной гомографией из позиции пикселя, поэтому дверь у края комнаты
// сужается вместе со стеной, а не выглядит наклейкой поверх неё.

uniform sampler2D tex : repeat_disable, filter_linear_mipmap;
uniform vec3 inv_r0 = vec3(1.0, 0.0, 0.0);
uniform vec3 inv_r1 = vec3(0.0, 1.0, 0.0);
uniform vec3 inv_r2 = vec3(0.0, 0.0, 1.0);
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 1.0 по оси — отразить. Отражение идёт в координатах ПОВЕРХНОСТИ, а не
// экрана: зеркальная дверь обязана остаться дверью в той же перспективе.
uniform vec2 flip = vec2(0.0, 0.0);

varying vec2 room_pos;

void vertex() {
	room_pos = VERTEX;
}

void fragment() {
	vec3 p = vec3(room_pos, 1.0);
	float w = dot(inv_r2, p);
	if (w <= 0.0001) {
		discard;
	}
	vec2 st = vec2(dot(inv_r0, p), dot(inv_r1, p)) / w;
	// Полигон совпадает с четырёхугольником отображения, поэтому выход за
	// границы — это только погрешность на самом краю. Отбрасываем, чтобы
	// clamp не размазывал крайний пиксель наружу.
	if (st.x < -0.002 || st.x > 1.002 || st.y < -0.002 || st.y > 1.002) {
		discard;
	}
	st = mix(st, vec2(1.0) - st, flip);
	COLOR = texture(tex, clamp(st, vec2(0.0), vec2(1.0))) * tint;
}
