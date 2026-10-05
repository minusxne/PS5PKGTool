#include "Desktop.h"

#include "FileBrowserModel.h"

#include <QClipboard>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQuickWindow>
#include <QStorageInfo>
#include <QSysInfo>

Desktop::Desktop(QObject *parent)
    : QObject(parent)
{
}

QString Desktop::homePath() const
{
    return QDir::homePath();
}

QString Desktop::version() const
{
    return QStringLiteral(PS5PKGTOOL_VERSION);
}

QString Desktop::platform() const
{
    return QSysInfo::prettyProductName() + QStringLiteral(" · Qt ") + QString::fromLatin1(qVersion()) + QStringLiteral(" · ") +
           QGuiApplication::platformName();
}

bool Desktop::openPath(const QString &path) const
{
    if (path.isEmpty())
        return false;
    return QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

bool Desktop::openUrl(const QString &url) const
{
    return QDesktopServices::openUrl(QUrl(url));
}

bool Desktop::reveal(const QString &path) const
{
    if (path.isEmpty() || !QFileInfo::exists(path))
        return false;
    QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.FileManager1"),
                                                          QStringLiteral("/org/freedesktop/FileManager1"),
                                                          QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("ShowItems"));
    message << QStringList{QUrl::fromLocalFile(path).toString()} << QString();
    const QDBusMessage reply = QDBusConnection::sessionBus().call(message, QDBus::Block, 1500);
    if (reply.type() != QDBusMessage::ErrorMessage)
        return true;
    const QFileInfo info(path);
    return QDesktopServices::openUrl(QUrl::fromLocalFile(info.isDir() ? path : info.absolutePath()));
}

void Desktop::copyText(const QString &text) const
{
    QGuiApplication::clipboard()->setText(text);
}

QVariantList Desktop::removePaths(const QStringList &paths, bool permanently) const
{
    QVariantList results;
    for (const QString &path : paths) {
        QVariantMap result{{QStringLiteral("path"), path}, {QStringLiteral("ok"), false}};
        const QFileInfo info(path);
        if (!info.exists() && !info.isSymLink()) {
            result.insert(QStringLiteral("error"), tr("Not found"));
        } else if (!permanently) {
            QFile file(path);
            if (file.moveToTrash())
                result.insert(QStringLiteral("ok"), true);
            else
                result.insert(QStringLiteral("error"), file.errorString().isEmpty() ? tr("The trash is not available for this location")
                                                                                    : file.errorString());
        } else if (info.isDir() && !info.isSymLink()) {
            const bool ok = QDir(path).removeRecursively();
            result.insert(QStringLiteral("ok"), ok);
            if (!ok)
                result.insert(QStringLiteral("error"), tr("Some files could not be deleted"));
        } else {
            QFile file(path);
            const bool ok = file.remove();
            result.insert(QStringLiteral("ok"), ok);
            if (!ok)
                result.insert(QStringLiteral("error"), file.errorString());
        }
        results.append(result);
    }
    return results;
}

bool Desktop::exists(const QString &path) const
{
    return !path.isEmpty() && QFileInfo::exists(path);
}

bool Desktop::isDir(const QString &path) const
{
    return !path.isEmpty() && QFileInfo(path).isDir();
}

QString Desktop::fileUrl(const QString &path) const
{
    return path.isEmpty() ? QString() : QUrl::fromLocalFile(path).toString();
}

QString Desktop::localPath(const QVariant &url) const
{
    const QUrl value = url.typeId() == QMetaType::QUrl ? url.toUrl() : QUrl(url.toString());
    if (value.isLocalFile())
        return value.toLocalFile();
    const QString text = url.toString();
    return text.startsWith(QLatin1Char('/')) ? text : QString();
}

QString Desktop::fileName(const QString &path) const
{
    QString trimmed = path;
    while (trimmed.size() > 1 && trimmed.endsWith(QLatin1Char('/')))
        trimmed.chop(1);
    return QFileInfo(trimmed).fileName();
}

QString Desktop::parentDir(const QString &path) const
{
    return QFileInfo(path).absolutePath();
}

QString Desktop::joinPath(const QString &directory, const QString &name) const
{
    return QDir(directory).filePath(name);
}

bool Desktop::writeText(const QString &path, const QString &text) const
{
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        return false;
    return file.write(text.toUtf8()) >= 0;
}

bool Desktop::copyFile(const QString &source, const QString &target) const
{
    if (QFileInfo::exists(target))
        QFile::remove(target);
    return QFile::copy(source, target);
}

QString Desktop::formatBytes(double bytes) const
{
    return FileBrowserModel::formatBytes(static_cast<qint64>(bytes));
}

QString Desktop::freeSpaceText(const QString &path) const
{
    QString probe = path;
    while (!probe.isEmpty() && !QFileInfo::exists(probe))
        probe = QFileInfo(probe).absolutePath() == probe ? QString() : QFileInfo(probe).absolutePath();
    if (probe.isEmpty())
        return {};
    const QStorageInfo storage(probe);
    if (!storage.isValid())
        return {};
    return tr("%1 free on %2").arg(formatBytes(static_cast<double>(storage.bytesAvailable())), storage.rootPath());
}

bool Desktop::saveScreenshot(QObject *window, const QString &path) const
{
    auto *quickWindow = qobject_cast<QQuickWindow *>(window);
    if (!quickWindow)
        return false;
    const QImage image = quickWindow->grabWindow();
    return !image.isNull() && image.save(path);
}
