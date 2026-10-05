#include "LibraryStore.h"

#include "BridgeClient.h"

#include <QUrl>

namespace {
// Every field of a bridge GameRow exposed as a model role (camelCase, as serialized).
const QStringList kFields = {
    QStringLiteral("title"), QStringLiteral("titleId"), QStringLiteral("contentId"), QStringLiteral("conceptId"),
    QStringLiteral("category"), QStringLiteral("role"), QStringLiteral("region"), QStringLiteral("format"),
    QStringLiteral("source"), QStringLiteral("sourceKind"), QStringLiteral("platform"), QStringLiteral("sizeBytes"),
    QStringLiteral("sizeText"), QStringLiteral("version"), QStringLiteral("contentVersion"), QStringLiteral("masterVersion"),
    QStringLiteral("targetVersion"), QStringLiteral("firmware"), QStringLiteral("sdk"), QStringLiteral("drm"),
    QStringLiteral("features"), QStringLiteral("language"), QStringLiteral("creationDate"), QStringLiteral("fileName"),
    QStringLiteral("location"), QStringLiteral("missing"), QStringLiteral("superseded"), QStringLiteral("missingBase"),
    QStringLiteral("warningCount"), QStringLiteral("icon"), QStringLiteral("background"), QStringLiteral("iconUrl"),
    QStringLiteral("backgroundUrl")};

QString toUrl(const QString &path)
{
    return path.isEmpty() ? QString() : QUrl::fromLocalFile(path).toString();
}

void addUrls(QVariantMap &row)
{
    row.insert(QStringLiteral("iconUrl"), toUrl(row.value(QStringLiteral("icon")).toString()));
    row.insert(QStringLiteral("backgroundUrl"), toUrl(row.value(QStringLiteral("background")).toString()));
}
} // namespace

// ------------------------------------------------------------------------------------------ GameListModel

GameListModel::GameListModel(LibraryStore *store, bool withHeaders, QObject *parent)
    : QAbstractListModel(parent), m_store(store), m_withHeaders(withHeaders)
{
}

const QStringList &GameListModel::fields()
{
    return kFields;
}

int GameListModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : static_cast<int>(m_entries.size());
}

QHash<int, QByteArray> GameListModel::roleNames() const
{
    QHash<int, QByteArray> roles{{KindRole, "kind"},
                                 {IdRole, "gameId"},
                                 {GroupKeyRole, "groupKey"},
                                 {GroupLabelRole, "groupLabel"},
                                 {GroupCountRole, "groupCount"},
                                 {CollapsedRole, "collapsed"}};
    for (int i = 0; i < kFields.size(); ++i)
        roles.insert(FirstFieldRole + i, kFields.at(i).toUtf8());
    return roles;
}

QVariant GameListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return {};
    const Entry &entry = m_entries.at(index.row());
    const auto &groups = m_store->groups();
    const LibraryStore::Group *group = entry.group >= 0 && entry.group < groups.size() ? &groups.at(entry.group) : nullptr;
    switch (role) {
    case KindRole:
        return entry.header ? QStringLiteral("header") : QStringLiteral("game");
    case IdRole:
        return entry.header ? QString() : entry.id;
    case GroupKeyRole:
        return group ? group->key : QString();
    case GroupLabelRole:
        return group ? group->label : QString();
    case GroupCountRole:
        return group ? group->ids.size() : 0;
    case CollapsedRole:
        return group ? m_collapsed.contains(group->key) : false;
    default:
        break;
    }
    if (entry.header || role < FirstFieldRole || role >= FirstFieldRole + kFields.size())
        return {};
    const QVariantMap *row = m_store->find(entry.id);
    return row ? row->value(kFields.at(role - FirstFieldRole)) : QVariant();
}

QVariantMap GameListModel::get(int index) const
{
    if (index < 0 || index >= m_entries.size())
        return {};
    const Entry &entry = m_entries.at(index);
    if (entry.header) {
        const auto &group = m_store->groups().at(entry.group);
        return {{QStringLiteral("kind"), QStringLiteral("header")},
                {QStringLiteral("groupKey"), group.key},
                {QStringLiteral("groupLabel"), group.label},
                {QStringLiteral("groupCount"), group.ids.size()}};
    }
    QVariantMap row = m_store->row(entry.id);
    row.insert(QStringLiteral("kind"), QStringLiteral("game"));
    return row;
}

int GameListModel::indexOf(const QString &id) const
{
    return m_indexById.value(id, -1);
}

QString GameListModel::idAt(int index) const
{
    if (index < 0 || index >= m_entries.size() || m_entries.at(index).header)
        return {};
    return m_entries.at(index).id;
}

void GameListModel::toggleGroup(const QString &key)
{
    if (m_collapsed.contains(key))
        m_collapsed.remove(key);
    else
        m_collapsed.insert(key);
    rebuild();
}

void GameListModel::setAllCollapsed(bool collapsed)
{
    m_collapsed.clear();
    if (collapsed)
        for (const auto &group : m_store->groups())
            m_collapsed.insert(group.key);
    rebuild();
}

QStringList GameListModel::groupIds(const QString &key) const
{
    for (const auto &group : m_store->groups())
        if (group.key == key)
            return group.ids;
    return {};
}

void GameListModel::rebuild()
{
    beginResetModel();
    m_entries.clear();
    m_indexById.clear();
    m_gameCount = 0;
    const auto &groups = m_store->groups();
    if (m_withHeaders && !groups.isEmpty()) {
        for (int g = 0; g < groups.size(); ++g) {
            m_entries.append(Entry{true, groups.at(g).key, g});
            if (m_collapsed.contains(groups.at(g).key))
                continue;
            for (const QString &id : groups.at(g).ids) {
                m_indexById.insert(id, static_cast<int>(m_entries.size()));
                m_entries.append(Entry{false, id, g});
                ++m_gameCount;
            }
        }
    } else {
        for (const QString &id : m_store->order()) {
            m_indexById.insert(id, static_cast<int>(m_entries.size()));
            m_entries.append(Entry{false, id, -1});
            ++m_gameCount;
        }
    }
    endResetModel();
    emit countChanged();
}

void GameListModel::rowChanged(const QString &id)
{
    const int index = m_indexById.value(id, -1);
    if (index < 0)
        return;
    const QModelIndex modelIndex = this->index(index);
    emit dataChanged(modelIndex, modelIndex);
}

// ------------------------------------------------------------------------------------------ LibraryStore

LibraryStore::LibraryStore(BridgeClient *bridge, QObject *parent)
    : QObject(parent), m_bridge(bridge), m_games(new GameListModel(this, false, this)), m_list(new GameListModel(this, true, this))
{
    m_artTimer.setSingleShot(true);
    m_artTimer.setInterval(60);
    connect(&m_artTimer, &QTimer::timeout, this, &LibraryStore::flushArtRequests);
}

void LibraryStore::setRows(const QVariantList &rows)
{
    QHash<QString, QVariantMap> next;
    next.reserve(rows.size());
    for (const QVariant &value : rows) {
        QVariantMap row = value.toMap();
        const QString id = row.value(QStringLiteral("id")).toString();
        if (id.isEmpty())
            continue;
        addUrls(row);
        // Keep artwork that arrived after the bridge built this row.
        const auto existing = m_rows.constFind(id);
        if (existing != m_rows.constEnd()) {
            for (const char *key : {"icon", "background", "iconUrl", "backgroundUrl"}) {
                const QString name = QString::fromLatin1(key);
                if (row.value(name).toString().isEmpty() && !existing->value(name).toString().isEmpty())
                    row.insert(name, existing->value(name));
            }
        }
        next.insert(id, row);
    }
    m_rows = std::move(next);
    // Forget artwork requests for rows that changed so they can be asked for again.
    for (auto it = m_requested.begin(); it != m_requested.end();) {
        if (!m_rows.contains(*it) || m_rows.value(*it).value(QStringLiteral("icon")).toString().isEmpty())
            it = m_requested.erase(it);
        else
            ++it;
    }
    m_order.erase(std::remove_if(m_order.begin(), m_order.end(), [this](const QString &id) { return !m_rows.contains(id); }),
                  m_order.end());
    m_games->rebuild();
    m_list->rebuild();
    emit rowsChanged();
    emit viewChanged();
}

void LibraryStore::setView(const QVariantMap &view)
{
    m_order.clear();
    for (const QVariant &id : view.value(QStringLiteral("ids")).toList())
        if (m_rows.contains(id.toString()))
            m_order.append(id.toString());
    m_groups.clear();
    for (const QVariant &value : view.value(QStringLiteral("groups")).toList()) {
        const QVariantMap group = value.toMap();
        Group entry{group.value(QStringLiteral("key")).toString(), group.value(QStringLiteral("label")).toString(), {}};
        for (const QVariant &id : group.value(QStringLiteral("ids")).toList())
            if (m_rows.contains(id.toString()))
                entry.ids.append(id.toString());
        if (!entry.ids.isEmpty())
            m_groups.append(entry);
    }
    m_warning = view.value(QStringLiteral("warning")).toString();
    m_games->rebuild();
    m_list->rebuild();
    emit viewChanged();
}

QVariantMap LibraryStore::row(const QString &id) const
{
    return m_rows.value(id);
}

const QVariantMap *LibraryStore::find(const QString &id) const
{
    auto it = m_rows.constFind(id);
    return it == m_rows.constEnd() ? nullptr : &it.value();
}

void LibraryStore::patchRow(const QString &id, const QVariantMap &values)
{
    auto it = m_rows.find(id);
    if (it == m_rows.end())
        return;
    for (auto value = values.constBegin(); value != values.constEnd(); ++value)
        it->insert(value.key(), value.value());
    addUrls(*it);
    m_games->rowChanged(id);
    m_list->rowChanged(id);
    emit artChanged(id);
}

void LibraryStore::requestArt(const QString &id, bool full)
{
    if (!m_rows.contains(id))
        return;
    if (full) {
        if (m_requestedFull.contains(id))
            return;
        m_requestedFull.insert(id);
        m_queueFull.append(id);
    } else {
        if (m_requested.contains(id) || !m_rows.value(id).value(QStringLiteral("icon")).toString().isEmpty())
            return;
        m_requested.insert(id);
        m_queue.append(id);
    }
    if (!m_artTimer.isActive())
        m_artTimer.start();
}

void LibraryStore::flushArtRequests()
{
    if (!m_bridge)
        return;
    // A few small batches at a time keep the first visible tiles fast on large libraries.
    const auto send = [this](QStringList &queue, bool full) {
        if (queue.isEmpty() || m_artInFlight >= 3)
            return;
        QStringList batch = queue.mid(0, full ? 2 : 12);
        queue.remove(0, batch.size());
        ++m_artInFlight;
        m_bridge->callNative(
            QStringLiteral("library.thumbnails"),
            {{QStringLiteral("ids"), batch}, {QStringLiteral("full"), full}},
            [this](const QVariant &result) {
                --m_artInFlight;
                const QVariantMap items = result.toMap().value(QStringLiteral("items")).toMap();
                for (auto it = items.constBegin(); it != items.constEnd(); ++it) {
                    const QVariantMap art = it.value().toMap();
                    QVariantMap patch{{QStringLiteral("icon"), art.value(QStringLiteral("icon"))}};
                    if (!art.value(QStringLiteral("background")).toString().isEmpty())
                        patch.insert(QStringLiteral("background"), art.value(QStringLiteral("background")));
                    patchRow(it.key(), patch);
                }
                if (!m_queue.isEmpty() || !m_queueFull.isEmpty())
                    m_artTimer.start();
            },
            [this, batch, full](const QVariantMap &) {
                --m_artInFlight;
                for (const QString &id : batch)
                    (full ? m_requestedFull : m_requested).remove(id);
            });
    };
    send(m_queueFull, true);
    send(m_queue, false);
    send(m_queue, false);
    if ((!m_queue.isEmpty() || !m_queueFull.isEmpty()) && m_artInFlight < 3)
        m_artTimer.start();
}
