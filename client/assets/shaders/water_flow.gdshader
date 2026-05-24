shader_type canvas_item;

// ======================
// 极佳暗黑星空调色板
// ======================

uniform vec4 color_deep : source_color =
vec4(0.039, 0.047, 0.086, 1.0); // #0a0c16

uniform vec4 color_mid : source_color =
vec4(0.063, 0.075, 0.131, 1.0);

uniform vec4 color_light : source_color =
vec4(0.086, 0.102, 0.176, 1.0); // #161a2d

uniform vec4 color_foam : source_color =
vec4(0.92, 0.96, 1.0, 1.0);

// ======================

uniform float speed : hint_range(0.0, 3.0) = 0.8;
uniform float wave_scale : hint_range(0.1, 8.0) = 2.0;

uniform int color_steps : hint_range(2, 16) = 6;

uniform bool use_dither = true;

uniform bool show_grid = false;
uniform float grid_size : hint_range(2.0, 64.0) = 16.0;
uniform float grid_alpha : hint_range(0.0, 1.0) = 0.08;

// 波浪强度 (保留兼容)
uniform float wave_strength : hint_range(0.0, 2.0) = 1.0;

// 高光强度 (保留兼容)
uniform float shimmer_strength : hint_range(0.0, 2.0) = 0.5;

// ======================
// Bayer Dither
// ======================

float dither2x2(vec2 coord) {
    int x = int(mod(coord.x, 2.0));
    int y = int(mod(coord.y, 2.0));

    float m[4] = float[4](
        0.0, 2.0,
        3.0, 1.0
    );

    return m[y * 2 + x] / 4.0;
}

// 伪随机生成器
float rand(vec2 co){
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

// ======================

void fragment() {
    // 1. 垂直线性渐变大背景
    vec4 base_color = mix(color_deep, color_light, UV.y);
    vec4 color = base_color;

    // 2. 健壮的像素大小获取
    vec2 p_size = TEXTURE_PIXEL_SIZE;
    if (p_size.x <= 0.0 || p_size.y <= 0.0) {
        p_size = vec2(1.0 / 1920.0, 1.0 / 1080.0);
    }

    // 3. 产生像素风呼吸闪烁小星星
    // 坐标以 4 像素对齐
    vec2 star_coord = floor(UV / p_size / 4.0);
    
    float star_val = rand(star_coord);
    if (star_val > 0.994) {
        // 这是一颗星星！
        // 1.5s 周期呼吸闪烁，通过 rand 给每一个星星提供不同的异步相位
        float phase = star_val * 62.8;
        float brightness = sin(TIME * (2.0 * 3.14159265 / 1.5) + phase) * 0.35 + 0.65;
        
        // 限制在 4x4 像素块中心的 2x2 范围渲染，达到高级且平滑的像素星光边缘
        vec2 sub_pixel = mod(floor(UV / p_size), 4.0);
        if (sub_pixel.x >= 1.0 && sub_pixel.x <= 2.0 && sub_pixel.y >= 1.0 && sub_pixel.y <= 2.0) {
            color = mix(color, color_foam, brightness * 0.7);
        }
    }

    // 4. 限色（像素风核心）
    color.rgb = floor(color.rgb * float(color_steps)) / float(color_steps);

    // 5. Dither
    if (use_dither) {
        vec2 pixel_coord = UV / p_size;
        float d = dither2x2(pixel_coord) - 0.5;
        color.rgb += d * (0.7 / float(color_steps));
        color.rgb = clamp(color.rgb, 0.0, 1.0);
    }

    // 6. 像素网格
    if (show_grid) {
        vec2 pixel_coord = UV / p_size;
        vec2 grid = abs(mod(pixel_coord, grid_size) - grid_size * 0.5) / (grid_size * 0.5);
        float edge = max(grid.x, grid.y);
        float line = 1.0 - smoothstep(0.92, 1.0, edge);
        color.rgb = mix(color.rgb, color.rgb * 0.75, line * grid_alpha);
    }

    COLOR = color;
}