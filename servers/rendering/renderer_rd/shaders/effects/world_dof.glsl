#[compute]

#version 450

#VERSION_DEFINES

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D source_color;
#ifndef DIRECT_COMPOSITE
layout(set = 0, binding = 1) uniform sampler2D source_metadata;
layout(set = 0, binding = 2) uniform sampler2D scene_depth;
layout(set = 0, binding = 3, std430) restrict readonly buffer DofResponses {
	float values[];
} dof_responses;
#endif
layout(rgba16f, set = 1, binding = 0) uniform restrict image2D output_color;
#ifdef HORIZONTAL
layout(rgba16f, set = 1, binding = 1) uniform restrict writeonly image2D output_metadata;
#endif
layout(push_constant, std430) uniform Params {
	ivec2 size;
	float z_near;
	float z_far;
	uint response_count;
	uint orthogonal;
	float max_radius;
	uint pad;
} params;

#ifndef DIRECT_COMPOSITE
float endpoint_blur_size(float depth, uint offset) {
	float near_begin = dof_responses.values[offset + 4u];
	float far_begin = dof_responses.values[offset + 1u];
	float radius = dof_responses.values[offset + 6u] * 64.0;
	if (dof_responses.values[offset + 3u] > 0.5 && depth < near_begin) {
		float transition = dof_responses.values[offset + 5u];
		if (transition < 0.0) {
			float d = abs(near_begin - depth);
			return -(d / (near_begin - d)) * radius;
		}
		return -(1.0 - smoothstep(near_begin - transition, near_begin, depth)) * radius;
	}
	if (dof_responses.values[offset] > 0.5 && depth > far_begin) {
		float transition = dof_responses.values[offset + 2u];
		if (transition < 0.0) {
			float d = abs(far_begin - depth);
			return (d / (far_begin + d)) * radius;
		}
		return smoothstep(far_begin, far_begin + transition, depth) * radius;
	}
	return 0.0;
}


float radius_at_depth(float depth) {
	float radius = 0.0;
	for (uint i = 0u; i < params.response_count; i++) {
		radius += endpoint_blur_size(depth, i * 8u) * dof_responses.values[i * 8u + 7u];
	}
	return min(abs(radius), params.max_radius);
}

float world_depth(ivec2 pos) {
	float depth = texelFetch(scene_depth, pos, 0).r * 2.0 - 1.0;
	if (params.orthogonal != 0u) {
		return -(depth * (params.z_far - params.z_near) - (params.z_far + params.z_near)) * 0.5;
	}
	return 2.0 * params.z_near * params.z_far / (params.z_far + params.z_near + depth * (params.z_far - params.z_near));
}

#endif // !DIRECT_COMPOSITE

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(pos, params.size))) {
		return;
	}
#ifdef DIRECT_COMPOSITE
	vec4 color = texelFetch(source_color, pos, 0);
	vec4 background = imageLoad(output_color, pos);
	imageStore(output_color, pos, vec4(color.rgb + background.rgb * (1.0 - color.a), color.a + background.a * (1.0 - color.a)));
#else
	vec4 color = vec4(0.0);
	vec4 metadata = vec4(0.0);
	float opaque_depth = world_depth(pos);
	for (int i = -32; i <= 32; i++) {
#ifdef HORIZONTAL
		ivec2 sample_pos = pos + ivec2(i, 0);
#else
		ivec2 sample_pos = pos + ivec2(0, i);
#endif
		if (any(lessThan(sample_pos, ivec2(0))) || any(greaterThanEqual(sample_pos, params.size))) {
			continue;
		}
		vec4 sample_metadata = texelFetch(source_metadata, sample_pos, 0);
		if (sample_metadata.a <= 0.0) {
			continue;
		}
		float depth = sample_metadata.r / sample_metadata.a;
		float radius = radius_at_depth(depth);
		float extent = radius + 1.0;
		float taps = ceil(radius);
		float normalization = extent * (2.0 * taps + 1.0) - taps * (taps + 1.0);
		float weight = max(0.0, extent - abs(float(i))) / normalization;
		// A layer pixel may only spread onto pixels where it is visible against
		// the real opaque world. Preserve the original explicit no_depth_test.
		float visibility = depth <= opaque_depth + max(0.001, opaque_depth * 0.0001) ? 1.0 : clamp(sample_metadata.g / sample_metadata.a, 0.0, 1.0);
		weight *= visibility;
		color += texelFetch(source_color, sample_pos, 0) * weight;
		metadata += sample_metadata * weight;
	}
#ifdef HORIZONTAL
	imageStore(output_color, pos, color);
	imageStore(output_metadata, pos, metadata);
#else
	// Scene-linear premultiplied over, before exposure/glow/tonemap. The
	// untouched holes contain only the already blurred native background.
	float coverage = clamp(color.a, 0.0, 1.0);
	color.rgb *= color.a > 1.0 ? 1.0 / color.a : 1.0;
	vec4 background = imageLoad(output_color, pos);
	imageStore(output_color, pos, vec4(color.rgb + background.rgb * (1.0 - coverage), coverage + background.a * (1.0 - coverage)));
#endif
#endif // DIRECT_COMPOSITE
}
