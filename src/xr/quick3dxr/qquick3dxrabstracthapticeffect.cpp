// Copyright (C) 2024 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#include "qquick3dxrabstracthapticeffect_p.h"

QT_BEGIN_NAMESPACE

void QQuick3DXrAbstractHapticEffect::start()
{
}

void QQuick3DXrAbstractHapticEffect::stop()
{
}

/*!
    \qmltype XrHapticEffect
    \qmlabstract
    \inherits QtObject
    \inqmlmodule QtQuick3D.Xr
    \brief Represents a haptic effect.
    \since 6.9

    XrHapticEffect defines the characteristics of the haptic effect.

    This type is abstract. Use a subtype, such as \l XrBasicHapticEffect.

    \sa XrHapticFeedback XrBasicHapticEffect
 */

/*!
    \qmltype XrBasicHapticEffect
    \inherits XrHapticEffect
    \inqmlmodule QtQuick3D.Xr
    \brief Allows setting controller haptics using amplitude, duration and frequency.
    \since 6.9

    \qml
    XrBasicHapticEffect {
        amplitude: 0.5
        duration: 300
        frequency: 3000
    }
    \endqml

    \sa XrHapticFeedback
*/

/*!
    \qmlproperty bool XrBasicHapticEffect::amplitude()
    \brief Defines the amplitude of the effect's vibration.
    Acceptable values are from 0.0 to 1.0
    \default 0.5
 */
float QQuick3DXrBasicHapticEffect::amplitude()
{
    return m_amplitude;
}

void QQuick3DXrBasicHapticEffect::setAmplitude(float newAmplitude)
{
    if (m_amplitude == newAmplitude)
        return;
    m_amplitude = newAmplitude;
    emit amplitudeChanged();
}

void QQuick3DXrBasicHapticEffect::start()
{
    m_running = true;
}

void QQuick3DXrBasicHapticEffect::stop()
{
    m_running = false;
}

bool QQuick3DXrBasicHapticEffect::getRunning()
{
    return m_running;
}

/*!
    \qmlproperty bool XrBasicHapticEffect::duration()
    \brief Defines the duration of the haptic effect in milliseconds.
    \default 30
 */
float QQuick3DXrBasicHapticEffect::duration()
{
    return m_duration;
}

void QQuick3DXrBasicHapticEffect::setDuration(float newDuration)
{
    if (m_duration == newDuration)
        return;
    m_duration = newDuration;
    emit durationChanged();
}

/*!
    \qmlproperty bool XrBasicHapticEffect::frequency()
    \brief Defines the frequency of the haptic effect in Hz
    \default 3000
 */

float QQuick3DXrBasicHapticEffect::frequency()
{
    return m_frequency;
}

void QQuick3DXrBasicHapticEffect::setFrequency(float newFrequency)
{
    if (m_frequency == newFrequency)
        return;
    m_frequency = newFrequency;
    emit frequencyChanged();
}

QT_END_NAMESPACE
