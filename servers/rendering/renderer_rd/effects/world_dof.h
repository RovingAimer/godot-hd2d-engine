/**************************************************************************/
/*  world_dof.h                                                                 */
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

#pragma once

#include "servers/rendering/renderer_rd/pipeline_deferred_rd.h"
#include "servers/rendering/renderer_rd/shaders/effects/world_dof.glsl.gen.h"
#include "servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.h"

namespace RendererRD {

// A single opt-in alpha layer. Metadata follows premultiplied coverage too.
// ponytail: overlap uses a coverage-weighted depth; exact multilayer DOF needs
// depth peeling/OIT and is outside this text/sprite layer's contract.
class WorldDOF {
	WorldDofShaderRD shader;
	RID version;
	PipelineDeferredRD pipelines[3];
	RID response_buffer;
	uint32_t response_bytes = 0;
	struct PushConstant {
		int32_t size[2];
		float z_near;
		float z_far;
		uint32_t response_count;
		uint32_t orthogonal;
		float max_radius;
		uint32_t pad;
	};

public:
	WorldDOF();
	~WorldDOF();
	void ensure_buffers(const Ref<RenderSceneBuffersRD> &p_buffers);
	void process(const Ref<RenderSceneBuffersRD> &p_buffers, RID p_camera_attributes, float p_z_near, float p_z_far, bool p_orthogonal, bool p_use_dof);
};

} // namespace RendererRD
