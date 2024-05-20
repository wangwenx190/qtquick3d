// Copyright (C) 2024 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#version 440
#extension GL_GOOGLE_include_directive : enable

#include "../effectlib/tonemapping.glsllib"
#include "../effectlib/oitcommon.glsllib"

layout(location = 0) out vec4 fragOutput;

layout(location = 0) in vec2 uv_coord;

#if QSSG_OIT_METHOD == QSSG_OIT_WEIGHTED_BLENDED

layout(binding = 1) uniform sampler2D accumTexture;
layout(binding = 2) uniform sampler2D revealageTexture;

void main()
{
#if QSHADER_HLSL || QSHADER_MSL
    vec2 uv = vec2(uv_coord.x, 1.0 - uv_coord.y);

#else
    vec2 uv = uv_coord;
#endif
    vec4 accum = texture(accumTexture, uv);
    float a = 1.0 - texture(revealageTexture, uv).r;
    vec4 color = vec4(accum.rgb / clamp(accum.a, 1e-4, 5e6), a);
    fragOutput = vec4(color);
}

#endif // QSSG_OIT_WEIGHTED_BLENDED
