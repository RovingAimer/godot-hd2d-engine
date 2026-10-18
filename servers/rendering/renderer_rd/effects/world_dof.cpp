/**************************************************************************/
/*  world_dof.cpp                                                                 */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "world_dof.h"

#include "servers/rendering/renderer_rd/storage_rd/material_storage.h"
#include "servers/rendering/renderer_rd/uniform_set_cache_rd.h"
#include "servers/rendering/rendering_server_globals.h"
#include "servers/rendering/storage/camera_attributes_storage.h"

using namespace RendererRD;

WorldDOF::WorldDOF() {
	Vector<String> modes = { "\n#define HORIZONTAL\n", "\n#define COMPOSITE\n", "\n#define DIRECT_COMPOSITE\n" };
	shader.initialize(modes);
	version = shader.version_create();
	for (int i = 0; i < 3; i++) {
		pipelines[i].create_compute_pipeline(shader.version_get_shader(version, i));
	}
}

WorldDOF::~WorldDOF() {
	for (int i = 0; i < 3; i++) {
		pipelines[i].free();
	}
	shader.version_free(version);
	if (response_buffer.is_valid()) {
		RD::get_singleton()->free(response_buffer);
	}
}

void WorldDOF::ensure_buffers(const Ref<RenderSceneBuffersRD> &p_buffers) {
	if (p_buffers->has_texture(SNAME("WorldDOF"), SNAME("color"))) {
		return;
	}
	uint32_t usage = RD::TEXTURE_USAGE_SAMPLING_BIT | RD::TEXTURE_USAGE_STORAGE_BIT | RD::TEXTURE_USAGE_COLOR_ATTACHMENT_BIT;
	for (const StringName &name : { SNAME("color"), SNAME("metadata"), SNAME("blur_color"), SNAME("blur_metadata") }) {
		p_buffers->create_texture(SNAME("WorldDOF"), name, RD::DATA_FORMAT_R16G16B16A16_SFLOAT, usage, RD::TEXTURE_SAMPLES_1, p_buffers->get_internal_size(), 1);
	}
}

void WorldDOF::process(const Ref<RenderSceneBuffersRD> &p_buffers, RID p_camera_attributes, float p_z_near, float p_z_far, bool p_orthogonal, bool p_use_dof) {
	if (!p_use_dof) {
		// Native DOF is disabled: preserve exact coverage with a single center
		// composite. No response upload, horizontal pass or blur sampling.
		Size2i size = p_buffers->get_internal_size();
		PushConstant pc = {};
		pc.size[0] = size.x;
		pc.size[1] = size.y;
		RID shader_rid = shader.version_get_shader(version, 2);
		RID sampler = MaterialStorage::get_singleton()->sampler_rd_get_default(RSE::CANVAS_ITEM_TEXTURE_FILTER_NEAREST, RSE::CANVAS_ITEM_TEXTURE_REPEAT_DISABLED);
		RD::Uniform source(RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, { sampler, p_buffers->get_texture(SNAME("WorldDOF"), SNAME("color")) });
		RD::Uniform output(RD::UNIFORM_TYPE_IMAGE, 0, { p_buffers->get_internal_texture() });
		RD::ComputeListID list = RD::get_singleton()->compute_list_begin();
		RD::get_singleton()->compute_list_bind_compute_pipeline(list, pipelines[2].get_rid());
		RD::get_singleton()->compute_list_bind_uniform_set(list, UniformSetCacheRD::get_singleton()->get_cache(shader_rid, 0, source), 0);
		RD::get_singleton()->compute_list_bind_uniform_set(list, UniformSetCacheRD::get_singleton()->get_cache(shader_rid, 1, output), 1);
		RD::get_singleton()->compute_list_set_push_constant(list, &pc, sizeof(pc));
		RD::get_singleton()->compute_list_dispatch_threads(list, size.x, size.y, 1);
		RD::get_singleton()->compute_list_end();
		return;
	}
	Vector<float> responses;
	if (p_camera_attributes.is_valid()) {
		responses = RSG::camera_attributes->camera_attributes_get_dof_responses(p_camera_attributes);
		if (responses.is_empty()) {
			responses.resize(8);
			responses.set(0, RSG::camera_attributes->camera_attributes_get_dof_far_enabled(p_camera_attributes));
			responses.set(1, RSG::camera_attributes->camera_attributes_get_dof_far_distance(p_camera_attributes));
			responses.set(2, RSG::camera_attributes->camera_attributes_get_dof_far_transition(p_camera_attributes));
			responses.set(3, RSG::camera_attributes->camera_attributes_get_dof_near_enabled(p_camera_attributes));
			responses.set(4, RSG::camera_attributes->camera_attributes_get_dof_near_distance(p_camera_attributes));
			responses.set(5, RSG::camera_attributes->camera_attributes_get_dof_near_transition(p_camera_attributes));
			responses.set(6, RSG::camera_attributes->camera_attributes_get_dof_blur_amount(p_camera_attributes));
			responses.set(7, 1.0f);
		}
	}
	uint32_t bytes = MAX(uint32_t(responses.size()) * uint32_t(sizeof(float)), uint32_t(8 * sizeof(float)));
	if (bytes != response_bytes) {
		if (response_buffer.is_valid()) {
			RD::get_singleton()->free(response_buffer);
		}
		response_buffer = RD::get_singleton()->storage_buffer_create(bytes);
		response_bytes = bytes;
	}
	if (!responses.is_empty()) {
		RD::get_singleton()->buffer_update(response_buffer, 0, responses.size() * sizeof(float), responses.ptr());
	}
	Size2i size = p_buffers->get_internal_size();
	PushConstant pc = {};
	pc.size[0] = size.x;
	pc.size[1] = size.y;
	pc.z_near = p_z_near;
	pc.z_far = p_z_far;
	pc.response_count = responses.size() / 8;
	pc.orthogonal = p_orthogonal;
	// Matches native signed response units (full-resolution pixels), with a
	// bounded soft-alpha filter. The kernel is separable tent, not native bokeh.
	pc.max_radius = 32.0f;

	MaterialStorage *materials = MaterialStorage::get_singleton();
	RID sampler = materials->sampler_rd_get_default(RSE::CANVAS_ITEM_TEXTURE_FILTER_NEAREST, RSE::CANVAS_ITEM_TEXTURE_REPEAT_DISABLED);
	UniformSetCacheRD *cache = UniformSetCacheRD::get_singleton();
	RID color = p_buffers->get_texture(SNAME("WorldDOF"), SNAME("color"));
	RID metadata = p_buffers->get_texture(SNAME("WorldDOF"), SNAME("metadata"));
	RID blur_color = p_buffers->get_texture(SNAME("WorldDOF"), SNAME("blur_color"));
	RID blur_metadata = p_buffers->get_texture(SNAME("WorldDOF"), SNAME("blur_metadata"));
	RD::ComputeListID list = RD::get_singleton()->compute_list_begin();
	for (int pass = 0; pass < 2; pass++) {
		RID shader_rid = shader.version_get_shader(version, pass);
		RD::Uniform u_color(RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, { sampler, pass == 0 ? color : blur_color });
		RD::Uniform u_metadata(RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, { sampler, pass == 0 ? metadata : blur_metadata });
		RD::Uniform u_depth(RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, { sampler, p_buffers->get_depth_texture() });
		RD::Uniform u_responses(RD::UNIFORM_TYPE_STORAGE_BUFFER, 3, { response_buffer });
		RD::Uniform u_output(RD::UNIFORM_TYPE_IMAGE, 0, { pass == 0 ? blur_color : p_buffers->get_internal_texture() });
		RD::get_singleton()->compute_list_bind_compute_pipeline(list, pipelines[pass].get_rid());
		RD::get_singleton()->compute_list_bind_uniform_set(list, cache->get_cache(shader_rid, 0, u_color, u_metadata, u_depth, u_responses), 0);
		if (pass == 0) {
			RD::Uniform u_output_metadata(RD::UNIFORM_TYPE_IMAGE, 1, { blur_metadata });
			RD::get_singleton()->compute_list_bind_uniform_set(list, cache->get_cache(shader_rid, 1, u_output, u_output_metadata), 1);
		} else {
			RD::get_singleton()->compute_list_bind_uniform_set(list, cache->get_cache(shader_rid, 1, u_output), 1);
		}
		RD::get_singleton()->compute_list_set_push_constant(list, &pc, sizeof(pc));
		RD::get_singleton()->compute_list_dispatch_threads(list, size.x, size.y, 1);
		if (pass == 0) {
			RD::get_singleton()->compute_list_add_barrier(list);
		}
	}
	RD::get_singleton()->compute_list_end();
}
