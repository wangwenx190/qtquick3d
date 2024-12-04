// Copyright (C) 2024 The Qt Company Ltd.*
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

VARYING vec2 texcoord;

void MAIN()
{
    float val = clamp(pow(texcoord.y * 3., 10.), 0., 1.0);
    FRAGCOLOR = vec4(mix(vec3(0.), indicatorColor.xyz, val), val);
}
