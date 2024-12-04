// Copyright (C) 2024 The Qt Company Ltd.*
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

VARYING vec2 texcoord;

void MAIN()
{
    const float radiusInner = 0.4;
    const float radiusOuter = 0.5;
    const float borderWidth = 0.02;
    float dist = length(texcoord - vec2(0.5, 0.5));
    float inVal = 1.0 - smoothstep(radiusInner - borderWidth, radiusInner + borderWidth, dist);

    float outVal = 1.0 - smoothstep(radiusOuter - borderWidth, radiusOuter + borderWidth, dist);

    float alphaVal = smoothstep(radiusOuter - 0.3, radiusOuter , dist) * outVal * 0.8;

    FRAGCOLOR = vec4(mix(vec3(0.0), outColor.xyz, outVal - inVal) + mix(vec3(0.0), inColor.xyz, inVal), 1.0) * alphaVal;
}
