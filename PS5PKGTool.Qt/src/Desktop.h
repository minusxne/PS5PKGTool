#pragma once

#include <QObject>
#include <QUrl>
#include <QVariantList>

/// Small desktop integration helpers for QML: open and reveal paths, the clipboard, the
/// freedesktop.org trash, and a few path utilities.
class Desktop : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString homePath READ homePath CONSTANT)
    Q_PROPERTY(QString version READ version CONSTANT)
    Q_PROPERTY(QString platform READ platform CONSTANT)

public:
    explicit Desktop(QObject *parent = nullptr);

    QString homePath() const;
    QString version() const;
    QString platform() const;

    Q_INVOKABLE bool openPath(const QString &path) const;
    Q_INVOKABLE bool openUrl(const QString &url) const;
    /// Shows the item selected in the file manager (org.freedesktop.FileManager1), or opens its folder.
    Q_INVOKABLE bool reveal(const QString &path) const;
    Q_INVOKABLE void copyText(const QString &text) const;
    /// Moves each path to the trash (or deletes it permanently); returns [{path, ok, error}].
    Q_INVOKABLE QVariantList removePaths(const QStringList &paths, bool permanently) const;
    Q_INVOKABLE bool exists(const QString &path) const;
    Q_INVOKABLE bool isDir(const QString &path) const;
    Q_INVOKABLE QString fileUrl(const QString &path) const;
    Q_INVOKABLE QString localPath(const QVariant &url) const;
    Q_INVOKABLE QString fileName(const QString &path) const;
    Q_INVOKABLE QString parentDir(const QString &path) const;
    Q_INVOKABLE QString joinPath(const QString &directory, const QString &name) const;
    Q_INVOKABLE bool writeText(const QString &path, const QString &text) const;
    Q_INVOKABLE bool copyFile(const QString &source, const QString &target) const;
    Q_INVOKABLE QString formatBytes(double bytes) const;
    Q_INVOKABLE QString freeSpaceText(const QString &path) const;
    /// Saves the current frame of a window (used by --screenshot).
    Q_INVOKABLE bool saveScreenshot(QObject *window, const QString &path) const;
};
