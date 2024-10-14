// Copyright (C) 2024 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#include "qquick3dxrmanager_visionos_p.h"
#include "qquick3dxrorigin_p.h"
#include "qquick3dxrmanager_p.h"
#include "qquick3dxrinputmanager_visionos_p.h"
#include "qquick3dxranchormanager_visionos_p.h"

#include "../qquick3dxrinputmanager_p.h"
#include "../qquick3dxranimationdriver_p.h"

#include <QtQuick3D/private/qquick3dviewport_p.h>
#include <QtQuick3D/private/qquick3dnode_p_p.h>

#include <QtQuick3DUtils/private/qssgassert_p.h>

#include <QQuickGraphicsDevice>
#include <rhi/qrhi.h>

#include <CompositorServices/CompositorServices.h>
#include <QtGui/qguiapplication_platform.h>

#include <QtCore/qoperatingsystemversion.h>
#include <QtCore/qloggingcategory.h>

QT_BEGIN_NAMESPACE

Q_DECLARE_LOGGING_CATEGORY(lcQuick3DXr);

static const char s_renderThreadName[] = "QQuick3DXrRenderThread";

class CompositorLayer : public QObject, public QNativeInterface::QVisionOSApplication::ImmersiveSpaceCompositorLayer
{
    Q_OBJECT
public:
    using EventT = std::underlying_type_t<QEvent::Type>;
    enum Event : EventT
    {
        Render = QEvent::User + 1,
        Pause,
        Stop,
        Pulse
    };

    void configure(cp_layer_renderer_capabilities_t capabilities, cp_layer_renderer_configuration_t configuration) const override
    {
        // NOTE: foveation is disabled for now
        const bool supportsFoveation = false && cp_layer_renderer_capabilities_supports_foveation(capabilities);
        const bool disableMultiview = QQuick3DXrManager::isMultiviewRenderingDisabled();

        cp_layer_renderer_layout textureLayout = disableMultiview ? cp_layer_renderer_layout_dedicated
                                                                  : cp_layer_renderer_layout_layered;

        cp_layer_renderer_configuration_set_layout(configuration, textureLayout);
        cp_layer_renderer_configuration_set_foveation_enabled(configuration, supportsFoveation);
        cp_layer_renderer_configuration_set_color_format(configuration, MTLPixelFormatRGBA16Float);
        simd_float2 depthRange = cp_layer_renderer_configuration_get_default_depth_range(configuration);
        // NOTE: The depth range is inverted for VisionOS (x = far, y = near)
        m_depthRange[0] = depthRange.y;
        m_depthRange[1] = depthRange.x;
    }

    void render(cp_layer_renderer_t renderer) override
    {
        if (m_layerRenderer != renderer) {
            m_layerRenderer = renderer;
            emit layerRendererChanged();
        }

        if (m_layerRenderer) {
            emit layerRendererReady();
            checkRenderState();
        }
    }

    void handleSpatialEvents(const QJsonObject &events) override
    {
        emit handleSpatialEventsRequested(events);
    }

    bool isInitialized() const { return m_initialized; }

    cp_layer_renderer_t layerRenderer() const
    {
        return m_layerRenderer;
    }

    void getDefaultDepthRange(float &near, float &far) const
    {
        near = m_depthRange[0];
        far = m_depthRange[1];
    }

    // Must be called from the GUI thread
    void init(QQuick3DXrManagerPrivate *xrManager)
    {
        Q_ASSERT(qApp->thread() == QThread::currentThread());
        QSSG_ASSERT(!m_initialized, return);

        m_xrManager = xrManager;
        runWorldTrackingARSession();
        m_initialized = true;
    }

    void stopArSession()
    {
        Q_ASSERT(qApp->thread() == QThread::currentThread());

        if (m_arSession) {
            qCDebug(lcQuick3DXr, "Stopping AR session");
            ar_session_stop(m_arSession);
            ar_session_set_data_provider_state_change_handler_f(m_arSession, nullptr, nullptr, nullptr);
        }
    }

    QMutex &arSessionLock() { return m_arSessionMtx; }
    bool arSessionRunning() const {
        return m_arTrackingState == QQuick3DXrManagerPrivate::ArTrackingState::Running;
    }

    QMutex &renderLock() { return m_mutex; }
    bool waitForSyncToComplete()
    {
        return m_waitCondition.wait(&m_mutex);
    }

    Q_INVOKABLE static void destroy(QQuickWindow *window, CompositorLayer *compositorLayer)
    {
        QSSG_ASSERT(window != nullptr, return);

        if (auto *visionOSApplicaton = qGuiApp->nativeInterface<QNativeInterface::QVisionOSApplication>())
            visionOSApplicaton->setImmersiveSpaceCompositorLayer(nullptr);

        // NOTE: This is a bit of a hack, but we need to cleanup the nodes
        // on the render thread while the GUI thread is blocked (as documented.)
        // Since we cannot destruct the window on the render thread, and we cannot
        // cleanup all nodes on the GUI thread due to dependencies on the render
        // thread and resources created on it. Instead we just invalidate the render
        // control and cleanup the nodes on the render thread. This is not ideal,
        // but it's what we have for now...
        auto *d = QQuickWindowPrivate::get(window);
        d->cleanupNodesOnShutdown();
        if (auto *rc = d->renderControl)
            rc->invalidate();

        delete compositorLayer;
    }

Q_SIGNALS:
    void layerRendererReady();
    void layerRendererChanged();
    void handleSpatialEventsRequested(const QJsonObject &jsonString);
    void renderStateChanged(QQuick3DXrManagerPrivate::RenderState);
    void arStateChanged(QQuick3DXrManagerPrivate::ArTrackingState);

protected:
    bool event(QEvent *event) override
    {
        {
            // NOTE: Intentionally scoped to avoid locking the mutex for events we're not handling
            // and that has side-effects (e.g. cleanup due to a deferred delete).
            QMutexLocker locker(&m_mutex);

            switch (static_cast<Event>(event->type())) {
            case Event::Render:
            {
                const bool success = renderFrame(locker);
                // Check if we successfully rendered the frame, if not the GUI thread
                // is likely waiting for the render thread to complete rendering, so we
                // need to wake it up.
                if (!success) {
                    m_xrManager->m_syncDone = false;
                    m_waitCondition.wakeAll();
                }
            }
                return true;
            case Event::Stop:
                cleanup();
                return true;
            case Event::Pause:
                pause();
                return true;
            case Event::Pulse:
                checkRenderState();
                return true;
            }
        }

        return QObject::event(event);
    }

private:
    friend bool QQuick3DXrManagerPrivate::renderFrameImpl(QMutexLocker<QMutex> &locker, QWaitCondition &waitCondition);

    static void onArStateChanged(void *context,
                                 ar_data_providers_t data_providers,
                                 ar_data_provider_state_t new_state,
                                 ar_error_t error,
                                 ar_data_provider_t failed_data_provider)
    {
        Q_UNUSED(context);
        Q_UNUSED(data_providers);
        Q_UNUSED(error);
        Q_UNUSED(failed_data_provider);

        auto *that = reinterpret_cast<CompositorLayer *>(context);

        QMutexLocker lock(&that->m_arSessionMtx);

        const auto oldState = that->m_arTrackingState;
        switch (new_state) {
        case ar_data_provider_state_initialized:
            that->m_arTrackingState = QQuick3DXrManagerPrivate::ArTrackingState::Initialized;
            break;
        case ar_data_provider_state_running:
            that->m_arTrackingState = QQuick3DXrManagerPrivate::ArTrackingState::Running;
            break;
        case ar_data_provider_state_paused:
            that->m_arTrackingState = QQuick3DXrManagerPrivate::ArTrackingState::Paused;
            break;
        case ar_data_provider_state_stopped:
            that->m_arTrackingState = QQuick3DXrManagerPrivate::ArTrackingState::Stopped;
            break;
        }

        if (oldState != that->m_arTrackingState)
            emit that->arStateChanged(that->m_arTrackingState);
    }

    void checkRenderState()
    {
        QSSG_ASSERT(m_layerRenderer != nullptr, return);

        const auto oldState = m_renderState;
        switch (cp_layer_renderer_get_state(m_layerRenderer)) {
        case cp_layer_renderer_state_paused:
            m_renderState = QQuick3DXrManagerPrivate::RenderState::Paused;
            break;
        case cp_layer_renderer_state_running:
            m_renderState = QQuick3DXrManagerPrivate::RenderState::Running;
            break;
        case cp_layer_renderer_state_invalidated:
            m_renderState = QQuick3DXrManagerPrivate::RenderState::Invalidated;
            break;
        }

        if (oldState != m_renderState)
            emit renderStateChanged(m_renderState);
    }

    ar_device_anchor_t createPoseForTiming(cp_frame_timing_t timing)
    {
        QSSG_ASSERT(m_worldTrackingProvider != nullptr, return nullptr);

        ar_device_anchor_t outAnchor = ar_device_anchor_create();
        cp_time_t presentationTime = cp_frame_timing_get_presentation_time(timing);
        CFTimeInterval queryTime = cp_time_to_cf_time_interval(presentationTime);
        ar_device_anchor_query_status_t status = ar_world_tracking_provider_query_device_anchor_at_timestamp(m_worldTrackingProvider, queryTime, outAnchor);
        if (status != ar_device_anchor_query_status_success) {
            NSLog(@"Failed to get estimated pose from world tracking provider for presentation timestamp %0.3f", queryTime);
        }
        return outAnchor;
    }

    void runWorldTrackingARSession()
    {
        ar_world_tracking_configuration_t worldTrackingConfiguration = ar_world_tracking_configuration_create();
        m_worldTrackingProvider = ar_world_tracking_provider_create(worldTrackingConfiguration);

        ar_data_providers_t dataProviders = ar_data_providers_create();
        ar_data_providers_add_data_provider(dataProviders, m_worldTrackingProvider);

        QQuick3DXrInputManager *inputManager = QQuick3DXrInputManager::instance();
        QQuick3DXrAnchorManager *anchorManager = QQuick3DXrAnchorManager::instance();

        // 1. prepare
        QQuick3DXrInputManagerPrivate *pim = nullptr;
        if (QSSG_GUARD_X(inputManager != nullptr, "No InputManager available!")) {
            pim = QQuick3DXrInputManagerPrivate::get(inputManager);
            if (QSSG_GUARD(pim != nullptr))
                pim->prepareHandtracking(dataProviders);
        }

        if (QSSG_GUARD_X(anchorManager != nullptr, "No AnchorManager available!"))
            QQuick3DXrManagerPrivate::prepareAnchorManager(anchorManager, dataProviders);

        m_arSession = ar_session_create();
        ar_session_set_data_provider_state_change_handler_f(m_arSession, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), this, &onArStateChanged);
        ar_session_run(m_arSession, dataProviders);

        // 2. initialize
        QQuick3DXrManagerPrivate::initInputManager(inputManager);
        QQuick3DXrManagerPrivate::initAnchorManager(anchorManager);
    }

    void pause()
    {
        qCDebug(lcQuick3DXr, "Pausing rendering");
    }

    void cleanup()
    {
        qCDebug(lcQuick3DXr, "Cleaning up");
    }

    [[nodiscard]] bool renderFrame(QMutexLocker<QMutex> &locker)
    {
        QMutexLocker arLocker(&m_arSessionMtx);
        if (m_arTrackingState != QQuick3DXrManagerPrivate::ArTrackingState::Running) {
            qCDebug(lcQuick3DXr, "AR tracking is not running, skipping frame rendering");
            return false;
        }

        checkRenderState();

        if (m_renderState == QQuick3DXrManagerPrivate::RenderState::Invalidated) {
            qCDebug(lcQuick3DXr, "Rendering is invalidated, releasing resources and stopping rendering");
            arLocker.unlock();
            return false;
        }

        if (m_renderState == QQuick3DXrManagerPrivate::RenderState::Paused) {
            qCDebug(lcQuick3DXr, "Rendering is paused, waiting...");
            arLocker.unlock();
            cp_layer_renderer_wait_until_running(m_layerRenderer);
            // If the state has changed we need to check again. And if the state
            // is changed to running a new update will be scheduled, so just return.
            checkRenderState();
            return false;
        }

        if (m_renderState != QQuick3DXrManagerPrivate::RenderState::Running) {
            qCDebug(lcQuick3DXr, "Rendering is not running, skipping frame rendering");
            return false;
        }

        return m_xrManager->renderFrameImpl(locker, m_waitCondition);
    }

    ar_world_tracking_provider_t worldTrackingProvider() const
    {
        return m_worldTrackingProvider;
    }

    // Rendering
    mutable QMutex m_mutex;
    QWaitCondition m_waitCondition;

    // AR Session
    mutable QMutex m_arSessionMtx;

    QQuick3DXrManagerPrivate *m_xrManager = nullptr;

    cp_layer_renderer_t m_layerRenderer = nullptr;
    ar_world_tracking_provider_t m_worldTrackingProvider = nullptr;
    ar_session_t m_arSession;
    mutable float m_depthRange[2] {1.0f, 10000.0f}; // NOTE: Near, Far
    QQuick3DXrManagerPrivate::RenderState m_renderState = QQuick3DXrManagerPrivate::RenderState::Paused;
    QQuick3DXrManagerPrivate::ArTrackingState m_arTrackingState = QQuick3DXrManagerPrivate::ArTrackingState::Stopped;
    bool m_initialized = false;
};

static constexpr QEvent::Type asQEvent(CompositorLayer::Event event) { return static_cast<QEvent::Type>(event); }

struct QSSGCompositionLayerInstance
{
    QPointer<CompositorLayer> instance;
};

Q_GLOBAL_STATIC(QSSGCompositionLayerInstance, s_compositorLayer)

// FIXME: Maybe unify with the openxr implementation?!
void QQuick3DXrManagerPrivate::updateCameraImp(simd_float4x4 headTransform, cp_drawable_t drawable, QQuick3DXrOrigin *xrOrigin, int i)
{
    cp_view_t view = cp_drawable_get_view(drawable, i);
    simd_float2 depth_range = cp_drawable_get_depth_range(drawable);
    const float clipNear = depth_range[1];
    const float clipFar = depth_range[0];

    xrOrigin->eyeCamera(i)->setClipNear(clipNear);
    xrOrigin->eyeCamera(i)->setClipFar(clipFar);

    simd_float4x4 projection = cp_drawable_compute_projection(drawable, cp_axis_direction_convention_right_up_forward, i);
    QMatrix4x4 proj{projection.columns[0].x, projection.columns[1].x, projection.columns[2].x, projection.columns[3].x,
                     projection.columns[0].y, projection.columns[1].y, projection.columns[2].y, projection.columns[3].y,
                     projection.columns[0].z, projection.columns[1].z, projection.columns[2].z, projection.columns[3].z,
                     projection.columns[0].w, projection.columns[1].w, projection.columns[2].w, projection.columns[3].w};
    xrOrigin->eyeCamera(i)->setProjection(proj);

    simd_float4x4 localEyeTransform = cp_view_get_transform(view);
    simd_float4x4 eyeCameraTransform = simd_mul(headTransform, localEyeTransform);
    // NOTE: We need to convert from meters to centimeters here
    QMatrix4x4 transform{eyeCameraTransform.columns[0].x, eyeCameraTransform.columns[1].x, eyeCameraTransform.columns[2].x, eyeCameraTransform.columns[3].x * 100,
                           eyeCameraTransform.columns[0].y, eyeCameraTransform.columns[1].y, eyeCameraTransform.columns[2].y, eyeCameraTransform.columns[3].y * 100,
                           eyeCameraTransform.columns[0].z, eyeCameraTransform.columns[1].z, eyeCameraTransform.columns[2].z, eyeCameraTransform.columns[3].z * 100,
                           0.0f, 0.0f, 0.0f, 1.0f};
    QQuick3DNodePrivate::get(xrOrigin->eyeCamera(i))->setLocalTransform(transform);
}

void QQuick3DXrManagerPrivate::updateCamera(QQuick3DViewport *xrViewport, simd_float4x4 headTransform, cp_drawable_t drawable, QQuick3DXrOrigin *xrOrigin, int i)
{
    updateCameraImp(headTransform, drawable, xrOrigin, i);
    xrViewport->setCamera(xrOrigin->eyeCamera(i));
}

void QQuick3DXrManagerPrivate::updateCameraMultiview(QQuick3DViewport *xrViewport, simd_float4x4 headTransform, cp_drawable_t drawable, QQuick3DXrOrigin *xrOrigin)
{
    QQuick3DCamera *cameras[2] {xrOrigin->eyeCamera(0), xrOrigin->eyeCamera(1)};

    for (int i = 0; i < 2; ++i)
        updateCameraImp(headTransform, drawable, xrOrigin, i);

    xrViewport->setMultiViewCameras(cameras);
}


QQuick3DXrManagerPrivate::QQuick3DXrManagerPrivate(QQuick3DXrManager &manager)
    : q_ptr(&manager)
{
}

QQuick3DXrManagerPrivate::~QQuick3DXrManagerPrivate()
{
}

QQuick3DXrManagerPrivate *QQuick3DXrManagerPrivate::get(QQuick3DXrManager *manager)
{
    QSSG_ASSERT(manager != nullptr, return nullptr);
    return manager->d_func();
}

bool QQuick3DXrManagerPrivate::initialize()
{
    Q_Q(QQuick3DXrManager);

    // NOTE: Check if there's a global instance of the compositor layer
    // already created, if not create one. Should probably move this over
    // to the native interface.
    if (!m_compositorLayer) {
        m_compositorLayer = s_compositorLayer->instance;
        if (!m_compositorLayer) {
            m_compositorLayer = new CompositorLayer;
            s_compositorLayer->instance = m_compositorLayer;
        }
    }

    if (!m_renderThread) {
        m_renderThread = new QThread;
        m_renderThread->setObjectName(QLatin1StringView(s_renderThreadName));
        m_compositorLayer->moveToThread(m_renderThread);
        m_renderThread->start();
    }

    if (!m_inputManager)
        m_inputManager = QQuick3DXrInputManager::instance();
    if (!m_anchorManager)
        m_anchorManager = QQuick3DXrAnchorManager::instance();

    // NOTE: Check if the compository layer proxy is already active.
    if (!m_compositorLayer->isInitialized()) {
        if (auto *visionOSApplicaton = qGuiApp->nativeInterface<QNativeInterface::QVisionOSApplication>()) {
            visionOSApplicaton->setImmersiveSpaceCompositorLayer(m_compositorLayer);
            m_compositorLayer->init(this);

            // FIXME: We don't actually handle the case where the rendere changes or we get multiple calls should do something.
            QObject::connect(m_compositorLayer, &CompositorLayer::layerRendererReady, q, &QQuick3DXrManager::initialized, Qt::ConnectionType(Qt::SingleShotConnection | Qt::QueuedConnection));
            QObject::connect(m_compositorLayer, &CompositorLayer::renderStateChanged, q, [q](QQuick3DXrManagerPrivate::RenderState state) {
                switch (state) {
                    case QQuick3DXrManagerPrivate::RenderState::Running:
                        qCDebug(lcQuick3DXr, "Render state: Running");
                        QQuick3DXrManagerPrivate::get(q)->m_running = true;
                        QCoreApplication::postEvent(q, new QEvent(QEvent::UpdateRequest));
                        break;
                    case QQuick3DXrManagerPrivate::RenderState::Invalidated:
                        qCDebug(lcQuick3DXr, "Render state: Invalidated");
                        QQuick3DXrManagerPrivate::get(q)->m_running = false;
                        emit q->sessionEnded();
                        break;
                    case QQuick3DXrManagerPrivate::RenderState::Paused:
                        QQuick3DXrManagerPrivate::get(q)->m_running = true;
                        qCDebug(lcQuick3DXr, "Render state: Paused");
                        break;
                }
            }, Qt::DirectConnection);

            QObject::connect(m_compositorLayer, &CompositorLayer::arStateChanged, q, [q](QQuick3DXrManagerPrivate::ArTrackingState state) {
                switch (state) {
                    case QQuick3DXrManagerPrivate::ArTrackingState::Initialized:
                        qCDebug(lcQuick3DXr, "AR state: Initialized");
                        QQuick3DXrManagerPrivate::get(q)->m_arRunning = false;
                        break;
                    case QQuick3DXrManagerPrivate::ArTrackingState::Running:
                        qCDebug(lcQuick3DXr, "AR state: Running");
                        QQuick3DXrManagerPrivate::get(q)->m_arRunning = true;
                        QCoreApplication::postEvent(q, new QEvent(QEvent::UpdateRequest));
                        break;
                    case QQuick3DXrManagerPrivate::ArTrackingState::Paused:
                        qCDebug(lcQuick3DXr, "AR state: Paused");
                        QQuick3DXrManagerPrivate::get(q)->m_arRunning = false;
                        break;
                    case QQuick3DXrManagerPrivate::ArTrackingState::Stopped:
                        qCDebug(lcQuick3DXr, "AR state: Stopped");
                        QQuick3DXrManagerPrivate::get(q)->m_arRunning = false;
                        break;
                }
            }, Qt::DirectConnection);

            // Listen for spatial events (these are native gestures like pinch click/drag coming from SwiftUI)
            QObject::connect(m_compositorLayer, &CompositorLayer::handleSpatialEventsRequested, q, &QQuick3DXrManager::processSpatialEvents);
        }
        return false;
    }

    return true;
}

void QQuick3DXrManagerPrivate::setupWindow(QQuickWindow *window)
{
    if (!window) {
        qWarning("QQuick3DXrManagerPrivate: Window is null!");
        return;
    }

    QSSG_ASSERT_X(m_compositorLayer != nullptr, "No composition layer!", return);

    cp_layer_renderer_t renderer = m_compositorLayer->layerRenderer();
    if (!renderer) {
        qWarning("QQuick3DXrManagerPrivate: Layer renderer is not available.");
        return;
    }

    auto device = cp_layer_renderer_get_device(renderer);
    auto commandQueue = [device newCommandQueue];

    auto qqGraphicsDevice = QQuickGraphicsDevice::fromDeviceAndCommandQueue(static_cast<MTLDevice*>(device), static_cast<MTLCommandQueue *>(commandQueue));

    window->setGraphicsDevice(qqGraphicsDevice);
}

bool QQuick3DXrManagerPrivate::finalizeGraphics(QRhi *rhi)
{
    Q_UNUSED(rhi);

    m_isGraphicsInitialized = true;
    return m_isGraphicsInitialized;
}

bool QQuick3DXrManagerPrivate::isReady() const
{
    return m_compositorLayer && (m_compositorLayer->layerRenderer() != nullptr);
}

bool QQuick3DXrManagerPrivate::isGraphicsInitialized() const
{
    return m_isGraphicsInitialized;
}

bool QQuick3DXrManagerPrivate::setupGraphics(QQuickWindow *window)
{
    QSSG_ASSERT(window != nullptr, return false);

    Q_ASSERT(m_renderThread != nullptr);
    QQuickWindowPrivate::get(window)->renderControl->prepareThread(m_renderThread);

    return true;
}

void QQuick3DXrManagerPrivate::getDefaultClipDistances(float &nearClip, float &farClip) const
{
    m_compositorLayer->getDefaultDepthRange(nearClip, farClip);
}

void QQuick3DXrManagerPrivate::teardown()
{
    Q_Q(QQuick3DXrManager);

    m_running = false;

    if (m_inputManager)
        QQuick3DXrInputManagerPrivate::get(m_inputManager)->teardown();

    if (m_anchorManager)
        m_anchorManager->teardown();

    if (m_compositorLayer) {
        m_compositorLayer->stopArSession();

        QMetaObject::invokeMethod(m_compositorLayer, "destroy", Qt::BlockingQueuedConnection, Q_ARG(QQuickWindow*, q->m_quickWindow), Q_ARG(CompositorLayer*, m_compositorLayer));
        m_compositorLayer = nullptr;
    }
}

void QQuick3DXrManagerPrivate::setMultiViewRenderingEnabled(bool enable)
{
    Q_UNUSED(enable);
    qWarning() << "Changing multiview rendering is not supported at runtime on VisionOS!";
}

bool QQuick3DXrManagerPrivate::isMultiViewRenderingEnabled() const
{
    return !QQuick3DXrManager::isMultiviewRenderingDisabled();
}

void QQuick3DXrManagerPrivate::setPassthroughEnabled(bool enable)
{
    Q_UNUSED(enable);
    Q_UNIMPLEMENTED(); qWarning() << Q_FUNC_INFO;
}

QtQuick3DXr::ReferenceSpace QQuick3DXrManagerPrivate::getReferenceSpace() const
{
    // FIXME: Not sure exactly what reference space is default or what is supported etc.
    return QtQuick3DXr::ReferenceSpace::ReferenceSpaceLocalFloor;
}

void QQuick3DXrManagerPrivate::setReferenceSpace(QtQuick3DXr::ReferenceSpace newReferenceSpace)
{
    // FIXME: Not sure if it's possible to set a reference space on VisionOS
    Q_UNUSED(newReferenceSpace);
    Q_UNIMPLEMENTED(); qWarning() << Q_FUNC_INFO;
}

void QQuick3DXrManagerPrivate::setDepthSubmissionEnabled(bool enable)
{
    Q_UNUSED(enable);
    if (!enable)
        qWarning("Depth submission is required on VisionOS");
}

void QQuick3DXrManagerPrivate::update()
{
    Q_Q(QQuick3DXrManager);

    // Lock the render mutex and request a new frame to be rendered.
    QMutexLocker<QMutex> locker { &m_compositorLayer->renderLock() };

    if (!m_running || !m_arRunning) {
        qCDebug(lcQuick3DXr, "Not running, skipping update");
        return;
    }

    // polish (GUI thread)
    q->m_renderControl->polishItems();

    m_syncDone = false;

    QCoreApplication::postEvent(m_compositorLayer, new QEvent(asQEvent(CompositorLayer::Event::Render)));

    // Wait for the sync to complete.
    bool waitCompleted = m_compositorLayer->waitForSyncToComplete();
    // The gui thread can now continue.

    QQuick3DXrAnimationDriver *animationDriver = q->m_animationDriver;

    if (Q_LIKELY(waitCompleted && m_syncDone && animationDriver)) {
        animationDriver->setStep(m_nextStepSize);
        animationDriver->advance();
    }

    QCoreApplication::postEvent(q, new QEvent(QEvent::UpdateRequest));
}

void QQuick3DXrManagerPrivate::processXrEvents()
{
    // NOTE: This is not used on visionOS
}

void QQuick3DXrManagerPrivate::prepareAnchorManager(QQuick3DXrAnchorManager *anchorManager, ar_data_providers_t dataProviders)
{
    anchorManager->prepareAnchorManager(dataProviders);
}

void QQuick3DXrManagerPrivate::initAnchorManager(QQuick3DXrAnchorManager *anchorManager)
{
    anchorManager->initAnchorManager();
}

void QQuick3DXrManagerPrivate::initInputManager(QQuick3DXrInputManager *im)
{
    QQuick3DXrInputManagerPrivate::get(im)->initHandtracking();
}

void QQuick3DXrManagerPrivate::setSamples(int samples)
{
    Q_UNUSED(samples);
    qWarning("Setting samples is not supported");
}

QString QQuick3DXrManagerPrivate::runtimeName() const
{
    return QStringLiteral("visionOS");
}

QVersionNumber QQuick3DXrManagerPrivate::runtimeVersion() const
{
    static const auto versionNumber = QOperatingSystemVersion::current().version();
    return versionNumber;
}

QString QQuick3DXrManagerPrivate::errorString() const
{
    return QString();
}

bool QQuick3DXrManagerPrivate::renderFrameImpl(QMutexLocker<QMutex> &locker, QWaitCondition &waitCondition)
{
    Q_Q(QQuick3DXrManager);

    // NOTE: The GUI thread is locked at this point
    QQuickWindow *window = q->m_quickWindow;
    QQuickRenderControl *renderControl = q->m_renderControl;
    QQuick3DXrOrigin *xrOrigin = q->m_xrOrigin;
    QQuick3DViewport *xrViewport = q->m_vrViewport;
    QQuick3DXrAnimationDriver *animationDriver = q->m_animationDriver;

    QSSG_ASSERT_X(window && renderControl && xrViewport && xrOrigin && animationDriver, "Invalid state, rendering aborted", return false);

    const bool multiviewRenderingEnabled = isMultiViewRenderingEnabled();

    Q_ASSERT(QThread::currentThread() != window->thread());

    auto layerRenderer = m_compositorLayer->layerRenderer();
    cp_frame_t frame = cp_layer_renderer_query_next_frame(layerRenderer);
    if (Q_UNLIKELY(frame == nullptr)) {
        qWarning("Failed to get next frame");
        return false;
    }

    cp_frame_timing_t timing = cp_frame_predict_timing(frame);
    if (Q_UNLIKELY(timing == nullptr)) {
        qWarning("Failed to get timing for frame");
        return false;
    }

    cp_frame_start_update(frame);

    cp_frame_end_update(frame);

    cp_time_t optimalInputTime = cp_frame_timing_get_optimal_input_time(timing);
    cp_time_wait_until(optimalInputTime);

    cp_frame_start_submission(frame);
    cp_drawable_t drawable = cp_frame_query_drawable(frame);
    if (Q_UNLIKELY(drawable == nullptr)) {
        qWarning("Failed to get drawable for frame");
        return false;
    }

    cp_frame_timing_t actualTiming = cp_drawable_get_frame_timing(drawable);
    ar_device_anchor_t anchor = m_compositorLayer->createPoseForTiming(actualTiming);
    cp_drawable_set_device_anchor(drawable, anchor);

    // Get the pose transform from the anchor
    simd_float4x4 headTransform = ar_anchor_get_origin_from_anchor_transform(anchor);

    // NOTE: We need to convert from meters to centimeters here
    QMatrix4x4 qtHeadTransform{headTransform.columns[0].x, headTransform.columns[1].x, headTransform.columns[2].x, headTransform.columns[3].x * 100,
                                 headTransform.columns[0].y, headTransform.columns[1].y, headTransform.columns[2].y, headTransform.columns[3].y * 100,
                                 headTransform.columns[0].z, headTransform.columns[1].z, headTransform.columns[2].z, headTransform.columns[3].z * 100,
                                 0.0f, 0.0f, 0.0f, 1.0f};
    xrOrigin->updateTrackedCamera(qtHeadTransform);

    // Update the hands
    if (QSSG_GUARD(m_inputManager != nullptr))
        QQuick3DXrInputManagerPrivate::get(m_inputManager)->updateHandtracking();

    // Animation driver
    // Convert the cp_frame_timing_t ticks to milliseconds
    enum : size_t { DisplayPeriod  = 0, DisplayDelta };
    qint64 stepSizes[2] {0, 0};
    auto &[displayPeriodMS, displayDeltaMS] = stepSizes;
    displayPeriodMS = qint64(cp_time_to_cf_time_interval(optimalInputTime) * 1000.0);
    displayDeltaMS = ((qint64(cp_time_to_cf_time_interval(cp_frame_timing_get_optimal_input_time(actualTiming)) * 1000.0)) - m_previousTime);
    const size_t selector = ((m_previousTime == 0) || (displayDeltaMS > displayPeriodMS)) ? DisplayPeriod : DisplayDelta;
    m_nextStepSize = stepSizes[selector];
    m_previousTime = displayPeriodMS;

    QRhi *rhi = renderControl->rhi();

    const auto drawableCount = cp_drawable_get_view_count(drawable);
    const auto textureCount = cp_drawable_get_texture_count(drawable);

    // NOTE: Expectation is that when multiview rendering is enabled we get a multiple drawables with a single texture array,
    //       each view/eye is then rendered to a slice in the texture array. If multiview rendering is not enabled we get a
    //

    for (size_t i = 0, end = textureCount; i != end ; ++i) {
        // Setup the RenderTarget based on the current drawable
        id<MTLTexture> colorMetalTexture = cp_drawable_get_color_texture(drawable, i);
        auto textureSize = QSize([colorMetalTexture width], [colorMetalTexture height]);

        QQuickRenderTarget renderTarget;

        if (multiviewRenderingEnabled)
            renderTarget = QQuickRenderTarget::fromMetalTexture(static_cast<MTLTexture*>(colorMetalTexture), [colorMetalTexture pixelFormat], [colorMetalTexture pixelFormat]/*viewFormat*/, textureSize, 1 /*sampleCount*/, drawableCount, {});
        else
            renderTarget = QQuickRenderTarget::fromMetalTexture(static_cast<MTLTexture*>(colorMetalTexture), [colorMetalTexture pixelFormat], textureSize);

        auto depthMetalTexture = cp_drawable_get_depth_texture(drawable, i);
        auto depthTextureSize = QSize([depthMetalTexture width], [depthMetalTexture height]);
        MTLPixelFormat depthTextureFormat = [depthMetalTexture pixelFormat];
        static const auto convertFormat = [](MTLPixelFormat format) -> QRhiTexture::Format {
            switch (format) {
            case MTLPixelFormatDepth16Unorm:
                return QRhiTexture::D16;
            case MTLPixelFormatDepth32Float:
                return QRhiTexture::D32F;
            default:
                qWarning("Unsupported depth texture format");
                return QRhiTexture::UnknownFormat;
            }
        };
        auto depthFormat = convertFormat(depthTextureFormat);
        if (depthFormat != QRhiTexture::UnknownFormat) {
            if (m_rhiDepthTexture && (m_rhiDepthTexture->format() != depthFormat || m_rhiDepthTexture->pixelSize() != depthTextureSize)) {
                delete m_rhiDepthTexture;
                m_rhiDepthTexture = nullptr;
            }

            if (!m_rhiDepthTexture) {
                if (multiviewRenderingEnabled)
                    m_rhiDepthTexture = rhi->newTextureArray(depthFormat, drawableCount, depthTextureSize, 1, QRhiTexture::RenderTarget);
                else
                    m_rhiDepthTexture = rhi->newTexture(depthFormat, depthTextureSize, 1, QRhiTexture::RenderTarget);
            }


            m_rhiDepthTexture->createFrom({ quint64(static_cast<MTLTexture*>(depthMetalTexture)), 0});
            renderTarget.setDepthTexture(m_rhiDepthTexture);
        }

        window->setRenderTarget(renderTarget);

        // Update the window size and content item size using the texture size
        window->setGeometry(0,
                            0,
                            textureSize.width(),
                            textureSize.height());
        window->contentItem()->setSize(QSizeF(textureSize.width(),
                                              textureSize.height()));

        // Update the camera pose
        if (QSSG_GUARD(xrOrigin)) {
            if (multiviewRenderingEnabled)
                updateCameraMultiview(xrViewport, headTransform, drawable, xrOrigin);
            else
                updateCamera(xrViewport, headTransform, drawable, xrOrigin, i);
        }

        // We only do this if we are rendering on a separate thread and with multiview rendering enabled,
        // or else the beginFrame and sync will be done on the GUI thread after both eyes have been
        // rendered...
        if (multiviewRenderingEnabled) {
            // Marks the start of the frame.
            renderControl->beginFrame();
            // Synchronization happens here on the render thread (with the GUI thread locked)
            m_syncDone = renderControl->sync();

            if (Q_UNLIKELY(!m_syncDone))
                return false;

            // Signal the GUI thread that the sync is done, so it can continue.
            waitCondition.wakeOne();
            locker.unlock();

            // Render the frame
            renderControl->render();
            // Marks the end of the frame.
            renderControl->endFrame();
        } else {
            renderControl->polishItems();
            renderControl->beginFrame();
            renderControl->sync();
            renderControl->render();
            renderControl->endFrame();
        }
    }

    id<MTLCommandBuffer> commandBuffer = [static_cast<const QRhiMetalNativeHandles*>(renderControl->rhi()->nativeHandles())->cmdQueue commandBuffer];

    cp_drawable_encode_present(drawable, commandBuffer);
    [commandBuffer commit];

    cp_frame_end_submission(frame);

    return true;
}

QT_END_NAMESPACE

#include "qquick3dxrmanager_visionos.moc"
