// Copyright (C) 2024 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import QtQuick
import QtQuick3D
import QtQuick3D.Xr

pragma ComponentBehavior: Bound

XrController {
    id: theController
    poseSpace: XrController.AimPose

    readonly property vector3d pickDirection: Qt.vector3d(0, 0, -1)

    //! [signals]
    signal objectPressed(obj: Model, pos: vector3d, direction: vector3d)
    signal objectHovered(obj: Model)
    signal moved(pos: vector3d, direction: vector3d)
    signal released()
    //! [signals]

    property bool grabMoveEnabled: true

    QtObject {
        id: priv
        property QtObject hitObject: null
        property bool isGrabbing: false
        property bool isInteracting: false

        property vector3d offset
        property quaternion rotation
        property Node grabbedObject


        function grab() {
            if (!grabMoveEnabled)
                return
            grabbedObject = hitObject as Node
            hitObject = null

            if (grabbedObject) {
                const scenePos = grabbedObject.scenePosition
                const sceneRot = grabbedObject.sceneRotation

                offset = theController.mapPositionFromScene(scenePos)
                rotation = theController.rotation.inverted().times(sceneRot)
                isGrabbing = true
            }
        }

        function ungrab() {
            hitObject = grabbedObject
            grabbedObject = null
            isGrabbing = false
        }

        function handlePress() {
            theController.objectPressed(hitObject, theController.scenePosition, theController.forward)
            isInteracting = true
        }

        function handleRelease() {
            isInteracting = false
            theController.released()
        }

        function moveObject() {
            if (grabbedObject) {
                let newPos = theController.scenePosition.plus(theController.rotation.times(offset))
                let newRot = theController.sceneRotation.times(rotation)

                if (grabbedObject.parent) {
                    newPos = grabbedObject.parent.mapPositionFromScene(newPos)
                    newRot = grabbedObject.parent.sceneRotation.inverted().times(newRot)
                }

                grabbedObject.setPosition(newPos)
                grabbedObject.setRotation(newRot)
            }
        }

        function yeet(delta: real) {
            const localForward = Qt.vector3d(0, 0, -1)
            const rayPos = localForward.times(pickRay.length)
            const yeetOffset = offset.minus(rayPos)
            pickRay.length = Math.max(10, Math.min(pickRay.length * (1 + delta/10), 1000))
            offset = yeetOffset.plus(localForward.times(pickRay.length))
        }

        function findObject() {
            const dir = theController.mapDirectionToScene(pickDirection)
            const pickResult = xrView.rayPick(scenePosition, dir)

            const didHit = pickResult.hitType !== PickResult.Null

            if (didHit) {
                pickRay.hit = true
                pickRay.length = pickResult.distance
                hitObject = pickResult.objectHit
            } else {
                pickRay.hit = false
                pickRay.length = 500
                hitObject = null
            }
            theController.objectHovered(hitObject)
        }

        function handleMove() {
            if (isInteracting)
                theController.moved(theController.scenePosition, theController.forward) //### sceneFwd
            else if (isGrabbing)
                moveObject()
            else
                findObject()
        }
    }

    Node {
        id: pickRay
        property real length: 50
        property real width: hit ? 2 : 1
        property bool hit: false

        visible: !priv.isGrabbing

        eulerRotation: Qt.vector3d(-90, 0, 0)
        Model {
            scale: Qt.vector3d(pickRay.width/100, pickRay.length/100, pickRay.width/100)
            y: pickRay.length/2
            source: "#Cylinder"
            materials: PrincipledMaterial { baseColor: pickRay.hit ? "green" : "red" }
            opacity: 0.5
        }
    }

    onRotationChanged: {
        priv.handleMove()
    }

    XrInputAction {
        id: grabAction
        hand: theController.controller
        actionId: [XrInputAction.SqueezeValue, XrInputAction.SqueezePressed]
        onPressedChanged: {
            if (pressed) {
                priv.grab()
            } else {
                priv.ungrab()
            }
        }
    }

    XrInputAction {
        id: triggerAction
        hand: theController.controller
        actionId: [XrInputAction.TriggerValue, XrInputAction.TriggerPressed, XrInputAction.IndexFingerPinch]
        onPressedChanged:  {
            if (pressed)
                priv.handlePress()
            else
                priv.handleRelease()
        }
    }

    XrInputAction {
        enabled: priv.isGrabbing
        hand: theController.controller
        actionId: XrInputAction.ThumbstickY

        onValueChanged: {
                priv.yeet(value)
        }
    }
}
