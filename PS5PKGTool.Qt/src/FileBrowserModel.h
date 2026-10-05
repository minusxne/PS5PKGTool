#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

/// Folder-by-folder view of the flat file list of a dump, image or package: folders first (with
/// their total size and file count), then files. A search lists matches from every folder.
class FileBrowserModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QString folder READ folder WRITE setFolder NOTIFY folderChanged)
    Q_PROPERTY(QString search READ search WRITE setSearch NOTIFY searchChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int fileCount READ fileCount NOTIFY filesChanged)
    Q_PROPERTY(qint64 totalBytes READ totalBytes NOTIFY filesChanged)
    Q_PROPERTY(QStringList crumbs READ crumbs NOTIFY folderChanged)
    QML_ELEMENT

public:
    enum Role { NameRole = Qt::UserRole + 1, PathRole, IsDirRole, SizeRole, SizeTextRole, ItemsRole, ExtensionRole, OriginRole,
                EncryptedRole, KindRole };

    explicit FileBrowserModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString folder() const { return m_folder; }
    void setFolder(const QString &folder);
    QString search() const { return m_search; }
    void setSearch(const QString &search);
    int count() const { return static_cast<int>(m_entries.size()); }
    int fileCount() const { return static_cast<int>(m_files.size()); }
    qint64 totalBytes() const { return m_totalBytes; }
    QStringList crumbs() const;

    Q_INVOKABLE void setFiles(const QVariantList &files);
    Q_INVOKABLE void clear() { setFiles({}); }
    Q_INVOKABLE void up();
    Q_INVOKABLE QVariantMap get(int index) const;
    /// Every file path at or below a folder (for "extract folder").
    Q_INVOKABLE QStringList filesUnder(const QString &folder) const;
    Q_INVOKABLE QStringList allFiles() const;
    Q_INVOKABLE static QString formatBytes(qint64 bytes);
    Q_INVOKABLE static QString kindOf(const QString &path);

signals:
    void folderChanged();
    void searchChanged();
    void countChanged();
    void filesChanged();

private:
    struct File
    {
        QString path;
        qint64 size = 0;
        QString origin;
        bool encrypted = false;
    };
    struct Entry
    {
        QString name;
        QString path;
        bool isDir = false;
        qint64 size = 0;
        int items = 0;
        int file = -1;
    };

    void rebuild();

    QVector<File> m_files;
    QVector<Entry> m_entries;
    QString m_folder;
    QString m_search;
    qint64 m_totalBytes = 0;
};
