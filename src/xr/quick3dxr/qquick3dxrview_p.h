// Copyright (C) 2024 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#ifndef QQUICK3DXRVIEW_P_H
#define QQUICK3DXRVIEW_P_H

//
//  W A R N I N G
//  -------------
//
// This file is not part of the Qt API.  It exists purely as an
// implementation detail.  This header file may change from version to
// version without notice, or even be removed.
//
// We mean it.
//


#include <QtCore/QObject>
#include <QtQml/QQmlEngine>
#include <QtQml/qqml.h>

#include <QtQuick3D/private/qquick3dviewport_p.h>
#include <QtQuick3D/private/qquick3dnode_p.h>
#include <QtQuick3D/private/qquick3dsceneenvironment_p.h>
#include <QtQuick3D/private/qquick3dpickresult_p.h>

#include <QtQuick3DXr/private/qquick3dxrmanager_p.h>
#include <QtQuick3DXr/private/qquick3dxrorigin_p.h>
#include <QtQuick3DXr/private/qquick3dxrruntimeinfo_p.h>

QT_BEGIN_NAMESPACE

class QQuick3DSceneEnvironment;
class QQuick3DXrHandInput;
class QQuick3DXrHandTrackerInput;
class QRhiTexture;

class QQuick3DXrItem;

class Q_QUICK3DXR_EXPORT QQuick3DXrView : public QQuick3DNode
{
    Q_OBJECT

    Q_PROPERTY(QQuick3DXrOrigin *xrOrigin READ xrOrigin NOTIFY xrOriginChanged)
    Q_PROPERTY(QQuick3DSceneEnvironment *environment READ environment WRITE setEnvironment NOTIFY environmentChanged)
    Q_PROPERTY(QQuick3DXrHandInput *leftHandInput READ leftHandInput CONSTANT)
    Q_PROPERTY(QQuick3DXrHandInput *rightHandInput READ rightHandInput CONSTANT)
    Q_PROPERTY(QQuick3DXrHandTrackerInput *leftHandTrackerInput READ leftHandTrackerInput CONSTANT)
    Q_PROPERTY(QQuick3DXrHandTrackerInput *rightHandTrackerInput READ rightHandTrackerInput CONSTANT)
    Q_PROPERTY(bool passthroughSupported READ isPassthroughSupported CONSTANT)
    Q_PROPERTY(bool passthroughEnabled READ passthroughEnabled WRITE setPassthroughEnabled NOTIFY passthroughEnabledChanged FINAL)
    Q_PROPERTY(QOpenXRRuntimeInfo *runtimeInfo READ runtimeInfo CONSTANT)
    Q_PROPERTY(bool quitOnSessionEnd READ isQuitOnSessionEndEnabled WRITE setQuitOnSessionEnd NOTIFY quitOnSessionEndChanged FINAL)
    Q_PROPERTY(QQuick3DRenderStats *renderStats READ renderStats CONSTANT)
    Q_PROPERTY(FoveationLevel fixedFoveation READ fixedFoveation WRITE setFixedFoveation NOTIFY fixedFoveationChanged FINAL)
    Q_PROPERTY(ReferenceSpace referenceSpace READ referenceSpace WRITE setReferenceSpace NOTIFY referenceSpaceChanged FINAL)
    Q_PROPERTY(bool depthSubmissionEnabled READ depthSubmissionEnabled WRITE setDepthSubmissionEnabled NOTIFY depthSubmissionEnabledChanged FINAL)
    Q_PROPERTY(bool multiViewRenderingSupported READ isMultiViewRenderingSupported CONSTANT)
    Q_PROPERTY(bool enableMultiViewRendering READ isMultiViewRenderingEnabled WRITE setEnableMultiViewRendering NOTIFY enableMultiViewRenderingChanged FINAL)
    QML_NAMED_ELEMENT(XrView)
    QML_ADDED_IN_VERSION(6, 8)

public:
    enum FoveationLevel {
        NoFoveation = 0,
        LowFoveation = 1,
        MediumFoveation = 2,
        HighFoveation = 3
    };
    Q_ENUM(FoveationLevel)

    enum class ReferenceSpace {
        ReferenceSpaceUnknown,
        ReferenceSpaceLocal,
        ReferenceSpaceStage,
        ReferenceSpaceLocalFloor
    };
    Q_ENUM(ReferenceSpace)

    explicit QQuick3DXrView();
    ~QQuick3DXrView();

    QQuick3DXrOrigin *xrOrigin() const;
    QQuick3DSceneEnvironment *environment() const;
    QQuick3DXrHandInput *leftHandInput() const;
    QQuick3DXrHandInput *rightHandInput() const;
    QQuick3DXrHandTrackerInput *leftHandTrackerInput() const;
    QQuick3DXrHandTrackerInput *rightHandTrackerInput() const;

    bool isPassthroughSupported() const;
    bool passthroughEnabled() const;

    FoveationLevel fixedFoveation() const;
    void setFixedFoveation(FoveationLevel level);

    QOpenXRRuntimeInfo *runtimeInfo() const;

    bool isQuitOnSessionEndEnabled() const;

    QQuick3DRenderStats *renderStats() const;

    Q_INVOKABLE QQuick3DPickResult rayPick(const QVector3D &origin, const QVector3D &direction) const;
    Q_INVOKABLE QList<QQuick3DPickResult> rayPickAll(const QVector3D &origin, const QVector3D &direction) const;

    Q_INVOKABLE void setTouchpoint(QQuickItem *target, const QPointF &position, int pointId, bool active);
    Q_INVOKABLE QVector3D processTouch(const QVector3D &pos, int pointId);
    Q_INVOKABLE QVariantMap touchpointState(int pointId) const;

    ReferenceSpace referenceSpace() const;
    void setReferenceSpace(ReferenceSpace newReferenceSpace);

    bool depthSubmissionEnabled() const;

    void registerXrItem(QQuick3DXrItem *newXrItem);
    void unregisterXrItem(QQuick3DXrItem *xrItem);

    bool isMultiViewRenderingSupported() const;
    bool isMultiViewRenderingEnabled() const;

public Q_SLOTS:
    void setEnvironment(QQuick3DSceneEnvironment * environment);
    void setPassthroughEnabled(bool enable);
    void setQuitOnSessionEnd(bool enable);
    void setDepthSubmissionEnabled(bool enable);
    void setEnableMultiViewRendering(bool enable);

private Q_SLOTS:
    void updateViewportGeometry();
    void handleSessionEnded();
    void handleClearColorChanged();
    void handleAAChanged();
    bool init();

Q_SIGNALS:
    void initializeFailed(const QString &errorString);
    void sessionEnded();
    void xrOriginChanged(QQuick3DXrOrigin* xrOrigin);
    void environmentChanged(QQuick3DSceneEnvironment * environment);
    void passthroughEnabledChanged();
    void quitOnSessionEndChanged();
    void fixedFoveationChanged();
    void frameReady(QRhiTexture *colorBuffer); // tooling
    void referenceSpaceChanged();
    void depthSubmissionEnabledChanged();
    void enableMultiViewRenderingChanged();

private:
    // The XrView does not expose the View3D in its public interface. This is intentional.
    QQuick3DViewport *view3d() const;

    QPointer<QQuick3DSceneEnvironment> m_sceneEnvironment;
    QQuick3DXrManager m_openXRManager;
    mutable QOpenXRRuntimeInfo m_openXRRuntimeInfo;
    bool m_quitOnSessionEnd = true;
    bool m_inDestructor = false;
    bool m_isInitialized = false;

    friend class QQuick3DXrVirtualMouse;
    QList<QQuick3DXrItem *> m_xrItems;
    struct XrTouchState;
    XrTouchState *m_touchState = nullptr;
};

QT_END_NAMESPACE

#endif // QQUICK3DXRVIEW_P_H
