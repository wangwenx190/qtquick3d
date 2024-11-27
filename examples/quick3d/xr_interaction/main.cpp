// Copyright (C) 2024 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

#include <QGuiApplication>
#include <QQmlApplicationEngine>

#include <QtCore/qfileselector.h>

int main(int argc, char *argv[])
{
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");

    qputenv("QSG_INFO", "1");

#if defined(Q_OS_WIN)
    qputenv("QSG_RHI_BACKEND", "d3d12");
#elif defined(Q_OS_ANDROID)
    qputenv("QSG_RHI_BACKEND", "vulkan");
#endif

    qputenv("QT_QUICK3D_XR_MULTIVIEW", "1");

    QGuiApplication app(argc, argv);

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.load(QUrl(QLatin1StringView("qrc:/main.qml")));

    return app.exec();
}
