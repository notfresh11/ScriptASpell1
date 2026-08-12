shader_type canvas_item;

// Parametri expuși în Inspector - foarte ușor de modificat de utilizator!
group_uniforms RetroParams;
uniform float dither_opacity : hint_range(0.0, 1.0) = 0.05;
uniform float dither_scale : hint_range(1.0, 8.0) = 1.0;
uniform float color_depth : hint_range(2.0, 32.0) = 32.0;

group_uniforms CRTParams;
uniform float scanline_opacity : hint_range(0.0, 1.0) = 0.15;
uniform float scanline_count : hint_range(100.0, 1080.0) = 360.0;
uniform float vignette_intensity : hint_range(0.0, 2.0) = 0.4;

group_uniforms LensParams;
uniform float chromatic_aberration : hint_range(0.0, 0.05) = 0.003;

// Matricea Bayer 4x4 pentru efectul de dithering geometric
const float bayer_matrix[16] = float[](
	0.0/16.0,  8.0/16.0,  2.0/16.0,  10.0/16.0,
	12.0/16.0, 4.0/16.0,  14.0/16.0, 6.0/16.0,
	3.0/16.0,  11.0/16.0, 1.0/16.0,  9.0/16.0,
	15.0/16.0, 7.0/16.0,  13.0/16.0, 5.0/16.0
);

void fragment() {
	vec2 uv = UV;

	// 1. Aberație Cromatică (separarea culorilor pe margini)
	// Efectul crește pe măsură ce ne îndepărtăm de centrul ecranului
	vec2 dist_from_center = uv - vec2(0.5);
	float aberration_amount = chromatic_aberration * length(dist_from_center);

	vec4 color;
	color.r = texture(TEXTURE, uv - vec2(aberration_amount, 0.0)).r;
	color.g = texture(TEXTURE, uv).g;
	color.b = texture(TEXTURE, uv + vec2(aberration_amount, 0.0)).b;
	color.a = 1.0;

	// 2. Limitare Culori (Color Depth / Posterization)
	// Reduce numărul de culori disponibile pentru acel aspect retro de pe 16 biți
	color.rgb = floor(color.rgb * color_depth) / color_depth;

	// 3. Dithering geometric (folosind matricea Bayer)
	// Obținem acele puncte frumoase la trecerea dintre umbră și lumină
	int x = int(FRAGCOORD.x / dither_scale) % 4;
	int y = int(FRAGCOORD.y / dither_scale) % 4;
	float bayer_value = bayer_matrix[y * 4 + x] - 0.5;

	// Aplicăm dither-ul combinat cu opacitatea lui
	vec3 dithered_color = color.rgb + vec3(bayer_value / color_depth) * dither_opacity;
	color.rgb = mix(color.rgb, dithered_color, dither_opacity);

	// Re-limităm culorile după dither
	color.rgb = floor(color.rgb * color_depth) / color_depth;

	// 4. Scanlines CRT (Linii fine orizontale)
	float scanline = sin(uv.y * scanline_count * 2.0 * PI);
	scanline = (scanline + 1.0) / 2.0; // Adus în intervalul [0, 1]
	float scanline_factor = mix(1.0, mix(0.7, 1.0, scanline), scanline_opacity);
	color.rgb *= scanline_factor;

	// 5. Vignette (Întunecarea colțurilor ecranului)
	float vignette = length(dist_from_center);
	vignette = smoothstep(0.8, 0.2, vignette * vignette_intensity);
	color.rgb *= vignette;

	COLOR = color;
}
