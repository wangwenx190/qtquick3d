// Copyright (C) 2024 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#include "qquick3dxrabstracthapticeffect_p.h"

QT_BEGIN_NAMESPACE

/*!
    \qmltype XrBasicHapticEffect
    \inherits XrAbstractHapticEffect
    \inqmlmodule QtQuick3D.Xr
    \brief Allows setting controller haptics using amplitude, duration and frequency.
*/
void AbstractHapticEffect::start()
{

}

void AbstractHapticEffect::stop()
{

}


/*!
    \qmltype XrHapticEffect
    \inherits Item
    \inqmlmodule QtQuick3D.Xr
    \brief Represents a haptic effect.

    \qml
    XrBasicHapticEffect {
        amplitude: 0.5
        duration: 300
        frequency: 3000
    }
    \endqml

 */

/*!
    \qmlproperty bool XrBasicHapticEffect::amplitude()
    \brief Defines the amplitude of the vibration between 0.0 and 1.0
    \default 0
 */
float BasicHapticEffect::amplitude()
{
    return m_amplitude;
}

void BasicHapticEffect::setAmplitude(float newAmplitude)
{
    if (m_amplitude == newAmplitude)
        return;
    m_amplitude = newAmplitude;
    emit amplitudeChanged();
}

void BasicHapticEffect::start()
{
    m_running = true;
}

void BasicHapticEffect::stop()
{
    m_running = false;
}

bool BasicHapticEffect::getRunning()
{
    return m_running;
}

/*!
    \qmlproperty bool XrBasicHapticEffect::duration()
    \brief Defines the duration of the haptic effect in milliseconds.
    \default 0
 */
float BasicHapticEffect::duration()
{
    return m_duration;
}

void BasicHapticEffect::setDuration(float newDuration)
{
    if (m_duration == newDuration)
        return;
    m_duration = newDuration;
    emit durationChanged();
}

/*!
    \qmlproperty bool XrBasicHapticEffect::frequency()
    \brief Defines the frequency of the haptic effect in Hz
    \default 0
 */

float BasicHapticEffect::frequency()
{
    return m_frequency;
}

void BasicHapticEffect::setFrequency(float newFrequency)
{
    if (m_frequency == newFrequency)
        return;
    m_frequency = newFrequency;
    emit frequencyChanged();
}

QT_END_NAMESPACE
