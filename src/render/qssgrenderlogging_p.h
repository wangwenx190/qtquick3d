/****************************************************************************
**
** Copyright (C) 2019 The Qt Company Ltd.
** Contact: https://www.qt.io/licensing/
**
** This file is part of Qt Quick 3D.
**
** $QT_BEGIN_LICENSE:GPL$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and The Qt Company. For licensing terms
** and conditions see https://www.qt.io/terms-conditions. For further
** information use the contact form at https://www.qt.io/contact-us.
**
** GNU General Public License Usage
** Alternatively, this file may be used under the terms of the GNU
** General Public License version 3 or (at your option) any later version
** approved by the KDE Free Qt Foundation. The licenses are as published by
** the Free Software Foundation and appearing in the file LICENSE.GPL3
** included in the packaging of this file. Please review the following
** information to ensure the GNU General Public License requirements will
** be met: https://www.gnu.org/licenses/gpl-3.0.html.
**
** $QT_END_LICENSE$
**
****************************************************************************/


#ifndef QSSGRENDERLOGGING_H
#define QSSGRENDERLOGGING_H

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

#include <QtQuick3DRender/private/qtquick3drenderglobal_p.h>
#include <QtCore/QLoggingCategory>

QT_BEGIN_NAMESPACE

Q_DECLARE_LOGGING_CATEGORY(GL_ERROR)
Q_DECLARE_LOGGING_CATEGORY(INVALID_PARAMETER)
Q_DECLARE_LOGGING_CATEGORY(INVALID_OPERATION)
Q_DECLARE_LOGGING_CATEGORY(OUT_OF_MEMORY)
Q_DECLARE_LOGGING_CATEGORY(INTERNAL_ERROR)
Q_DECLARE_LOGGING_CATEGORY(PERF_WARNING)
Q_DECLARE_LOGGING_CATEGORY(PERF_INFO)
Q_DECLARE_LOGGING_CATEGORY(TRACE_INFO)
Q_DECLARE_LOGGING_CATEGORY(WARNING)
Q_DECLARE_LOGGING_CATEGORY(SHADER_INFO)

QT_END_NAMESPACE

#endif // QSSGRENDERLOGGING_H
