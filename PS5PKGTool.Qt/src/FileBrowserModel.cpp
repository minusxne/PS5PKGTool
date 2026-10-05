#include "FileBrowserModel.h"

#include <QCollator>
#include <QFileInfo>
#include <QLocale>
#include <algorithm>

FileBrowserModel::FileBrowserModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int FileBrowserModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : static_cast<int>(m_entries.size());
}

QHash<int, QByteArray> FileBrowserModel::roleNames() const
{
    return {{NameRole, "name"},       {PathRole, "path"},       {IsDirRole, "isDir"},     {SizeRole, "size"},
            {SizeTextRole, "sizeText"}, {ItemsRole, "items"},   {ExtensionRole, "extension"}, {OriginRole, "origin"},
            {EncryptedRole, "encrypted"}, {KindRole, "kind"}};
}

QVariant FileBrowserModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_entries.size())
        return {};
    const Entry &entry = m_entries.at(index.row());
    const File *file = entry.file >= 0 ? &m_files.at(entry.file) : nullptr;
    switch (role) {
    case NameRole:
        return entry.name;
    case PathRole:
        return entry.path;
    case IsDirRole:
        return entry.isDir;
    case SizeRole:
        return entry.size;
    case SizeTextRole:
        return formatBytes(entry.size);
    case ItemsRole:
        return entry.items;
    case ExtensionRole:
        return entry.isDir ? QString() : QFileInfo(entry.name).suffix().toLower();
    case OriginRole:
        return file ? file->origin : QString();
    case EncryptedRole:
        return file ? file->encrypted : false;
    case KindRole:
        return entry.isDir ? QStringLiteral("folder") : kindOf(entry.name);
    default:
        return {};
    }
}

QString FileBrowserModel::kindOf(const QString &path)
{
    const QString suffix = QFileInfo(path).suffix().toLower();
    static const QStringList images{"png", "jpg", "jpeg", "dds", "bmp", "gif", "webp"};
    static const QStringList audio{"at9", "wav", "mp3", "ogg", "opus", "flac", "aac", "m4a"};
    static const QStringList video{"mp4", "m4v", "webm", "mkv", "mov", "avi", "bik", "usm", "ts", "m2ts"};
    static const QStringList text{"json", "txt", "xml", "ini", "cfg", "conf", "log", "csv", "yaml", "yml", "md", "html", "htm",
                                  "css", "js", "lua", "sh"};
    static const QStringList code{"bin", "elf", "self", "sprx", "prx", "so"};
    static const QStringList archive{"pkg", "exfat", "ffpkg", "ffpfsc", "pfs", "ucp", "zip"};
    if (images.contains(suffix))
        return QStringLiteral("image");
    if (audio.contains(suffix))
        return QStringLiteral("audio");
    if (video.contains(suffix))
        return QStringLiteral("video");
    if (text.contains(suffix))
        return QStringLiteral("text");
    if (code.contains(suffix))
        return QStringLiteral("binary");
    if (archive.contains(suffix))
        return QStringLiteral("archive");
    return QStringLiteral("file");
}

QString FileBrowserModel::formatBytes(qint64 bytes)
{
    static const char *units[] = {"B", "KB", "MB", "GB", "TB"};
    double value = std::max<qint64>(0, bytes);
    int unit = 0;
    while (value >= 1024.0 && unit < 4) {
        value /= 1024.0;
        ++unit;
    }
    return QStringLiteral("%1 %2").arg(QLocale::c().toString(value, 'f', unit == 0 ? 0 : (value < 10 ? 2 : 1))).arg(QLatin1String(units[unit]));
}

void FileBrowserModel::setFiles(const QVariantList &files)
{
    m_files.clear();
    m_totalBytes = 0;
    m_files.reserve(files.size());
    for (const QVariant &value : files) {
        const QVariantMap map = value.toMap();
        File file{map.value(QStringLiteral("path")).toString(), map.value(QStringLiteral("size")).toLongLong(),
                  map.value(QStringLiteral("origin")).toString(), map.value(QStringLiteral("encrypted")).toBool()};
        m_totalBytes += file.size;
        m_files.append(file);
    }
    m_folder.clear();
    m_search.clear();
    rebuild();
    emit filesChanged();
    emit folderChanged();
    emit searchChanged();
}

void FileBrowserModel::setFolder(const QString &folder)
{
    QString normalized = folder;
    while (normalized.endsWith(QLatin1Char('/')))
        normalized.chop(1);
    if (m_folder == normalized)
        return;
    m_folder = normalized;
    rebuild();
    emit folderChanged();
}

void FileBrowserModel::setSearch(const QString &search)
{
    if (m_search == search)
        return;
    m_search = search;
    rebuild();
    emit searchChanged();
}

void FileBrowserModel::up()
{
    const qsizetype slash = m_folder.lastIndexOf(QLatin1Char('/'));
    setFolder(slash < 0 ? QString() : m_folder.left(slash));
}

QStringList FileBrowserModel::crumbs() const
{
    return m_folder.isEmpty() ? QStringList() : m_folder.split(QLatin1Char('/'));
}

QVariantMap FileBrowserModel::get(int index) const
{
    if (index < 0 || index >= m_entries.size())
        return {};
    const Entry &entry = m_entries.at(index);
    return {{QStringLiteral("name"), entry.name},
            {QStringLiteral("path"), entry.path},
            {QStringLiteral("isDir"), entry.isDir},
            {QStringLiteral("size"), entry.size},
            {QStringLiteral("sizeText"), formatBytes(entry.size)},
            {QStringLiteral("items"), entry.items},
            {QStringLiteral("kind"), entry.isDir ? QStringLiteral("folder") : kindOf(entry.name)},
            {QStringLiteral("encrypted"), entry.file >= 0 && m_files.at(entry.file).encrypted}};
}

QStringList FileBrowserModel::filesUnder(const QString &folder) const
{
    QStringList result;
    const QString prefix = folder.isEmpty() ? QString() : folder + QLatin1Char('/');
    for (const File &file : m_files)
        if (prefix.isEmpty() || file.path.startsWith(prefix))
            result.append(file.path);
    return result;
}

QStringList FileBrowserModel::allFiles() const
{
    return filesUnder(QString());
}

void FileBrowserModel::rebuild()
{
    beginResetModel();
    m_entries.clear();
    const QString needle = m_search.trimmed();
    if (!needle.isEmpty()) {
        for (int i = 0; i < m_files.size(); ++i) {
            const File &file = m_files.at(i);
            if (file.path.contains(needle, Qt::CaseInsensitive))
                m_entries.append(Entry{file.path, file.path, false, file.size, 0, i});
        }
    } else {
        const QString prefix = m_folder.isEmpty() ? QString() : m_folder + QLatin1Char('/');
        QHash<QString, int> folders;
        QVector<Entry> files;
        for (int i = 0; i < m_files.size(); ++i) {
            const File &file = m_files.at(i);
            if (!prefix.isEmpty() && !file.path.startsWith(prefix))
                continue;
            const QString rest = file.path.mid(prefix.size());
            const qsizetype slash = rest.indexOf(QLatin1Char('/'));
            if (slash < 0) {
                files.append(Entry{rest, file.path, false, file.size, 0, i});
                continue;
            }
            const QString name = rest.left(slash);
            auto it = folders.find(name);
            if (it == folders.end()) {
                it = folders.insert(name, static_cast<int>(m_entries.size()));
                m_entries.append(Entry{name, prefix + name, true, 0, 0, -1});
            }
            Entry &folderEntry = m_entries[it.value()];
            folderEntry.size += file.size;
            ++folderEntry.items;
        }
        QCollator collator;
        collator.setNumericMode(true);
        collator.setCaseSensitivity(Qt::CaseInsensitive);
        const auto byName = [&collator](const Entry &a, const Entry &b) { return collator.compare(a.name, b.name) < 0; };
        std::sort(m_entries.begin(), m_entries.end(), byName);
        std::sort(files.begin(), files.end(), byName);
        m_entries += files;
    }
    endResetModel();
    emit countChanged();
}
