// Copyright (C) 2024 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import QtQuick
import QtQuick3D

Node {
    id: pointer
    required property var rayPicker //any object that has implemented rayPick(pos, dir)
    required property Node beamHandle
    property real pointerSize: 3.0
    property real beamThickness: 0.3
    property alias beamMaxlength: rayPointerIndicator.maxLength
    property color beamColor: "#eeeeee"
    property color beamHitColor: "#bbddcc"
    property color beamPressedHitColor: "#bbccdd"
    property color beamPressedMissColor: "#ddbbbb"
    property color pointerInnerColor: "white"
    property color pointerOuterColor: "dimgray"
    property bool pressed: false
    property QtObject hitObject
    property bool hit: false
    property real hitDistance: -1
    Node {
        id: rayPointerIndicator
        parent: beamHandle
        property real maxLength: 150
        property real length: 150
        readonly property real thickness: pointer.beamThickness / 100
        z: -length/2
        onSceneRotationChanged: {
            var pickResult = rayPicker.rayPick(beamHandle.scenePosition, beamHandle.forward)

            if (pickResult.distance > 1)
                rayPointerIndicator.length = Math.min(pickResult.distance, rayPointerIndicator.maxLength)
            var newPos = pickResult.scenePosition.minus(pickResult.sceneNormal.normalized().times(-0.1))
            rayPointerTarget.setRotation(Quaternion.lookAt(newPos, pickResult.scenePosition,
                                                           Qt.vector3d(0, 0, -1), Qt.vector3d(0, 1, 0)))
            rayPointerTarget.position = newPos
            if (pickResult.hitType !== PickResult.Null) {
                pointer.hitDistance = pickResult.distance
                pointer.hit = true
                pointer.hitObject = pickResult.objectHit
            }else {
                pointer.hitDistance = -1
                pointer.hit = false
                pointer.hitObject = null
            }
        }
        Model {
            eulerRotation.x: 90
            scale: Qt.vector3d(rayPointerIndicator.thickness, rayPointerIndicator.length/100, rayPointerIndicator.thickness)
            source: "#Cylinder"
            materials: CustomMaterial {
                id: material
                property color indicatorColor: pointer.hit ?
                                                   (pointer.pressed ? pointer.beamPressedHitColor : pointer.beamHitColor) :
                                                   (pointer.pressed ? pointer.beamPressedMissColor : pointer.beamColor)
                shadingMode: CustomMaterial.Unshaded
                cullMode: Material.BackFaceCulling
                vertexShader: "shaders/ray_pointer.vert"
                fragmentShader: "shaders/ray_pointer_indicator.frag"
            }
            opacity: 0.9
        }
    }

    Model {
        id: rayPointerTarget
        source: "#Rectangle"
        readonly property real scaleValue: pointer.pointerSize / 100 * (pointer.pressed ? 0.7 : 1.0)
        scale: Qt.vector3d(scaleValue, scaleValue, scaleValue)
        opacity: 0.9
        materials: CustomMaterial {
            property color inColor: pointer.pointerInnerColor
            property color outColor: pointer.pointerOuterColor
            shadingMode: CustomMaterial.Unshaded
            cullMode: Material.BackFaceCulling
            vertexShader: "shaders/ray_pointer.vert"
            fragmentShader: "shaders/ray_pointer_target.frag"
        }
    }
}
