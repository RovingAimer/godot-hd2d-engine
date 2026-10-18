#[compute]

#version 450

#VERSION_DEFINES

#define BLOCK_SIZE 8

layout(local_size_x = BLOCK_SIZE, local_size_y = BLOCK_SIZE, local_size_z = 1) in;

#ifdef MODE_GEN_BLUR_SIZE
layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(set = 1, binding = 0) uniform sampler2D source_depth;
// Native response endpoints: two vec4-sized groups (eight contiguous floats).
layout(set = 2, binding = 0, std430) restrict readonly buffer DofResponses {
	float values[];
} dof_responses;
#endif

#if defined(MODE_BOKEH_BOX) || defined(MODE_BOKEH_HEXAGONAL) || defined(MODE_BOKEH_CIRCULAR)
layout(set = 1, binding = 0) uniform sampler2D color_texture;
layout(rgba16f, set = 0, binding = 0) uniform restrict writeonly image2D bokeh_image;
#endif

#ifdef MODE_COMPOSITE_BOKEH
layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(set = 1, binding = 0) uniform sampler2D source_bokeh;
layout(set = 2, binding = 0) uniform sampler2D source_depth;
layout(set = 3, binding = 0, std430) restrict readonly buffer DofResponses {
	float values[];
} dof_responses;
#endif

// based on https://www.shadertoy.com/view/Xd3GDl

#include "bokeh_dof_inc.glsl"

#if defined(MODE_GEN_BLUR_SIZE) || defined(MODE_COMPOSITE_BOKEH)

float get_depth_at_pos(vec2 uv) {
	float depth = textureLod(source_depth, uv, 0.0).x * 2.0 - 1.0;
	if (params.orthogonal) {
		depth = -(depth * (params.z_far - params.z_near) - (params.z_far + params.z_near)) / 2.0;
	} else {
		depth = 2.0 * params.z_near * params.z_far / (params.z_far + params.z_near + depth * (params.z_far - params.z_near));
	}
	return depth;
}

float endpoint_blur_size(float depth, uint offset) {
	float near_begin = dof_responses.values[offset + 4u];
	float far_begin = dof_responses.values[offset + 1u];
	float radius = dof_responses.values[offset + 6u] * 64.0;
	if (dof_responses.values[offset + 3u] > 0.5 && depth < near_begin) {
		float transition = dof_responses.values[offset + 5u];
		if (transition < 0.0) {
			float d = abs(near_begin - depth);
			return -(d / (near_begin - d)) * radius - DEPTH_GAP;
		}
		return -(1.0 - smoothstep(near_begin - transition, near_begin, depth)) * radius - DEPTH_GAP;
	}
	if (dof_responses.values[offset] > 0.5 && depth > far_begin) {
		float transition = dof_responses.values[offset + 2u];
		if (transition < 0.0) {
			float d = abs(far_begin - depth);
			return (d / (far_begin + d)) * radius + DEPTH_GAP;
		}
		return smoothstep(far_begin, far_begin + transition, depth) * radius + DEPTH_GAP;
	}
	return 0.0;
}

float get_blur_size(float depth) {
	if (params.response_count > 0u) {
		float radius = 0.0;
		for (uint i = 0u; i < params.response_count; i++) {
			uint offset = i * 8u;
			radius += endpoint_blur_size(depth, offset) * dof_responses.values[offset + 7u];
		}
		return radius;
	}
	if (params.blur_near_active && depth < params.blur_near_begin) {
		if (params.use_physical_near) {
			// Physically-based.
			float d = abs(params.blur_near_begin - depth);
			return -(d / (params.blur_near_begin - d)) * params.blur_size_near - DEPTH_GAP; // Near blur is negative.
		} else {
			// Non-physically-based.
			return -(1.0 - smoothstep(params.blur_near_end, params.blur_near_begin, depth)) * params.blur_size - DEPTH_GAP; // Near blur is negative.
		}
	}

	if (params.blur_far_active && depth > params.blur_far_begin) {
		if (params.use_physical_far) {
			// Physically-based.
			float d = abs(params.blur_far_begin - depth);
			return (d / (params.blur_far_begin + d)) * params.blur_size_far + DEPTH_GAP;
		} else {
			// Non-physically-based.
			return smoothstep(params.blur_far_begin, params.blur_far_end, depth) * params.blur_size + DEPTH_GAP;
		}
	}

	return 0.0;
}

#endif

#if defined(MODE_BOKEH_BOX) || defined(MODE_BOKEH_HEXAGONAL)

vec4 weighted_filter_dir(vec2 dir, vec2 uv, vec2 pixel_size) {
	dir *= pixel_size;
	vec4 color = texture(color_texture, uv);
	vec4 accum = color;
	float total = 1.0;
	bool reconstruct_far = color.a > 0.0;
	vec3 far_rgb = color.rgb;
	float far_weight = 1.0;
	vec3 near_rgb = vec3(0.0);
	float near_weight = 0.0;
	float blur_scale = params.blur_size / float(params.blur_steps);

	if (params.use_jitter) {
		uv += dir * (hash12n(uv + params.jitter_seed) - 0.5);
	}
	for (int i = -params.blur_steps; i <= params.blur_steps; i++) {
		if (i == 0) {
			continue;
		}
		float radius = float(i) * blur_scale;
		vec2 suv = uv + dir * radius;
		radius = abs(radius);
		vec4 sample_color = texture(color_texture, suv);
		float limit = (sample_color.a < color.a ? abs(sample_color.a) : abs(color.a)) - DEPTH_GAP;
		float m = smoothstep(radius - 0.5, radius + 0.5, limit);
		// Preserve the signed CoC propagation and non-far-center behavior.
		accum += mix(color, sample_color, m);
		if (reconstruct_far) {
			if (sample_color.a < 0.0) {
				near_rgb += sample_color.rgb * m;
				near_weight += m;
			} else {
				// Interpolating clear/far RGB before testing CoC admits sharp color.
				// Gather only alpha first; fetch RGB corners only at that boundary.
				vec4 alpha = textureGather(color_texture, suv, 3);
				float minimum = min(min(alpha.x, alpha.y), min(alpha.z, alpha.w));
				float maximum = max(max(alpha.x, alpha.y), max(alpha.z, alpha.w));
				if (minimum == 0.0 && maximum > 0.0) {
					ivec2 source_size = textureSize(color_texture, 0);
					vec2 sample_pos = suv * vec2(source_size) - 0.5;
					ivec2 base = ivec2(floor(sample_pos));
					vec2 fraction = fract(sample_pos);
					for (int j = 0; j < 4; j++) {
						vec4 corner = texelFetch(color_texture, clamp(base + ivec2(j & 1, j >> 1), ivec2(0), source_size - 1), 0);
						float b = ((j & 1) == 0 ? 1.0 - fraction.x : fraction.x) * ((j >> 1) == 0 ? 1.0 - fraction.y : fraction.y);
						float corner_m = smoothstep(radius - 0.5, radius + 0.5, min(color.a, corner.a) - DEPTH_GAP);
						far_rgb += corner.rgb * (b * corner_m);
						far_weight += b * corner_m;
					}
				} else {
					far_rgb += sample_color.rgb * m;
					far_weight += m;
				}
			}
		}
		total += 1.0;
	}
	vec4 result = accum / total;
	if (reconstruct_far) {
		// Normalize far reconstruction, retaining near foreground coverage m/N.
		// The center contributes one, so far_weight is always positive.
		result.rgb = (1.0 - near_weight / total) * (far_rgb / far_weight) + near_rgb / total;
	}
	return result;
}

#endif

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);

	if (any(greaterThan(pos, params.size))) { //too large, do nothing
		return;
	}

	vec2 pixel_size = 1.0 / vec2(params.size);
	vec2 uv = vec2(pos) / vec2(params.size);

#ifdef MODE_GEN_BLUR_SIZE
	uv += pixel_size * 0.5;
	//precompute size in alpha channel
	float depth = get_depth_at_pos(uv);
	float size = get_blur_size(depth);

	vec4 color = imageLoad(color_image, pos);
	color.a = size;
	imageStore(color_image, pos, color);
#endif

#ifdef MODE_BOKEH_BOX

	//pixel_size*=0.5; //resolution is doubled
	if (params.second_pass || !params.half_size) {
		uv += pixel_size * 0.5; //half pixel to read centers
	} else {
		uv += pixel_size * 0.25; //half pixel to read centers from full res
	}

	vec2 dir = (params.second_pass ? vec2(0.0, 1.0) : vec2(1.0, 0.0));

	vec4 color = weighted_filter_dir(dir, uv, pixel_size);

	imageStore(bokeh_image, pos, color);

#endif

#ifdef MODE_BOKEH_HEXAGONAL

	//pixel_size*=0.5; //resolution is doubled
	if (params.second_pass || !params.half_size) {
		uv += pixel_size * 0.5; //half pixel to read centers
	} else {
		uv += pixel_size * 0.25; //half pixel to read centers from full res
	}

	vec2 dir = (params.second_pass ? normalize(vec2(1.0, 0.577350269189626)) : vec2(0.0, 1.0));

	vec4 color = weighted_filter_dir(dir, uv, pixel_size);

	if (params.second_pass) {
		dir = normalize(vec2(-1.0, 0.577350269189626));

		vec4 color2 = weighted_filter_dir(dir, uv, pixel_size);

		color.rgb = min(color.rgb, color2.rgb);
		color.a = (color.a + color2.a) * 0.5;
	}

	imageStore(bokeh_image, pos, color);

#endif

#ifdef MODE_BOKEH_CIRCULAR

	if (params.half_size) {
		pixel_size *= 0.5; //resolution is doubled
	}

	uv += pixel_size * 0.5; //half pixel to read centers

	vec4 color = texture(color_texture, uv);
	float initial_blur = color.a;
	float accum = 1.0;
	float radius = params.blur_scale;

	for (float ang = 0.0; radius < params.blur_size; ang += GOLDEN_ANGLE) {
		vec2 suv = uv + vec2(cos(ang), sin(ang)) * pixel_size * radius;
		vec4 sample_color = texture(color_texture, suv);
		float sample_size = abs(sample_color.a);
		if (sample_color.a > initial_blur) {
			sample_size = clamp(sample_size, 0.0, abs(initial_blur) * 2.0);
		}

		float m = smoothstep(radius - 0.5, radius + 0.5, sample_size);
		color += mix(color / accum, sample_color, m);
		accum += 1.0;
		radius += params.blur_scale / radius;
	}

	color /= accum;

	imageStore(bokeh_image, pos, color);
#endif

#ifdef MODE_COMPOSITE_BOKEH

	uv += pixel_size * 0.5;
	vec4 color = imageLoad(color_image, pos);
	vec4 bokeh = texture(source_bokeh, uv);
	if (color.a > 0.0) {
		ivec2 low_size = textureSize(source_bokeh, 0);
		ivec2 full_size = textureSize(source_depth, 0);
		vec2 low_pos = uv * vec2(low_size) - 0.5;
		ivec2 low_base = ivec2(floor(low_pos));
		vec2 blend = fract(low_pos);
		float center_reverse_depth = texelFetch(source_depth, pos, 0).r;
		vec3 near_rgb = vec3(0.0);
		float near_weight = 0.0;
		vec3 far_rgb = vec3(0.0);
		float far_weight = 0.0;
		bool rejected_clear = false;
		for (int y = 0; y < 2; y++) {
			for (int x = 0; x < 2; x++) {
				ivec2 tap_pos = clamp(low_base + ivec2(x, y), ivec2(0), low_size - 1);
				vec4 tap = texelFetch(source_bokeh, tap_pos, 0);
				float w = (x == 0 ? 1.0 - blend.x : blend.x) * (y == 0 ? 1.0 - blend.y : blend.y);
				// Match pass1's normalized (tap + 0.25) / half_size, including odd sizes.
				ivec2 source_pos = clamp(ivec2(floor((vec2(tap_pos) + 0.25) * vec2(full_size) / vec2(low_size))), ivec2(0), full_size - 1);
				float reverse_depth = texelFetch(source_depth, source_pos, 0).r;
				float depth = reverse_depth * 2.0 - 1.0;
				if (params.orthogonal) {
					depth = -(depth * (params.z_far - params.z_near) - (params.z_far + params.z_near)) / 2.0;
				} else {
					depth = 2.0 * params.z_near * params.z_far / (params.z_far + params.z_near + depth * (params.z_far - params.z_near));
				}
				float raw_coc = get_blur_size(depth);
				if (tap.a < 0.0 || raw_coc < 0.0) {
					// Keep near contributions at their original bilinear coverage.
					near_rgb += w * tap.rgb;
					near_weight += w;
				} else if (!(raw_coc == 0.0 && reverse_depth > center_reverse_depth)) {
					// Reject only a closer, exactly clear-zone source, never a depth gradient.
					far_rgb += w * tap.rgb;
					far_weight += w;
				} else if (w > 0.0) {
					rejected_clear = true;
				}
			}
		}
		if (rejected_clear && far_weight > 0.0) {
			bokeh.rgb = near_rgb + (1.0 - near_weight) * (far_rgb / far_weight);
		}
		// Leave old bilinear alpha and composite mix_amount unchanged.
	}

	float mix_amount;
	if (bokeh.a < color.a) {
		mix_amount = min(1.0, max(0.0, max(abs(color.a), abs(bokeh.a)) - DEPTH_GAP));
	} else {
		mix_amount = min(1.0, max(0.0, abs(color.a) - DEPTH_GAP));
	}

	color.rgb = mix(color.rgb, bokeh.rgb, mix_amount); //blend between hires and lowres

	color.a = 0; //reset alpha
	imageStore(color_image, pos, color);
#endif
}
