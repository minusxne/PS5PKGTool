#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QPointer>
#include <QSet>
#include <QTimer>
#include <QVariantMap>

class BridgeClient;
class LibraryStore;

/// An ordered view of the library for one presentation: the home rail and the grid use games only;
/// the list view interleaves collapsible group headers.
class GameListModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int gameCount READ gameCount NOTIFY countChanged)

public:
    enum Role { KindRole = Qt::UserRole + 1, IdRole, GroupKeyRole, GroupLabelRole, GroupCountRole, CollapsedRole, FirstFieldRole };

    GameListModel(LibraryStore *store, bool withHeaders, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return static_cast<int>(m_entries.size()); }
    int gameCount() const { return m_gameCount; }

    Q_INVOKABLE QVariantMap get(int index) const;
    Q_INVOKABLE int indexOf(const QString &id) const;
    Q_INVOKABLE QString idAt(int index) const;
    Q_INVOKABLE void toggleGroup(const QString &key);
    Q_INVOKABLE void setAllCollapsed(bool collapsed);
    Q_INVOKABLE QStringList groupIds(const QString &key) const;

    void rebuild();
    void rowChanged(const QString &id);

    static const QStringList &fields();

signals:
    void countChanged();

private:
    struct Entry
    {
        bool header = false;
        QString id;      // game id, or group key for a header
        int group = -1;
    };

    LibraryStore *m_store;
    bool m_withHeaders;
    QVector<Entry> m_entries;
    QHash<QString, int> m_indexById;
    QSet<QString> m_collapsed;
    int m_gameCount = 0;
};

/// Holds every library row (as sent by the bridge) and the current filtered/sorted order. Artwork
/// is requested lazily from the bridge in small batches as tiles become visible.
class LibraryStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(GameListModel *games READ games CONSTANT)
    Q_PROPERTY(GameListModel *list READ list CONSTANT)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY viewChanged)
    Q_PROPERTY(int visibleCount READ visibleCount NOTIFY viewChanged)
    Q_PROPERTY(QString warning READ warning NOTIFY viewChanged)
    Q_PROPERTY(bool grouped READ grouped NOTIFY viewChanged)

public:
    struct Group
    {
        QString key;
        QString label;
        QStringList ids;
    };

    explicit LibraryStore(BridgeClient *bridge, QObject *parent = nullptr);

    GameListModel *games() { return m_games; }
    GameListModel *list() { return m_list; }
    int totalCount() const { return static_cast<int>(m_rows.size()); }
    int visibleCount() const { return static_cast<int>(m_order.size()); }
    QString warning() const { return m_warning; }
    bool grouped() const { return !m_groups.isEmpty(); }

    /// Replaces every row (from library.list).
    Q_INVOKABLE void setRows(const QVariantList &rows);
    /// Applies a view (from library.view): ordered ids, groups and a query warning.
    Q_INVOKABLE void setView(const QVariantMap &view);
    Q_INVOKABLE QVariantMap row(const QString &id) const;
    Q_INVOKABLE bool contains(const QString &id) const { return m_rows.contains(id); }
    Q_INVOKABLE QStringList visibleIds() const { return m_order; }
    /// Asks the bridge for artwork of an item (batched); full also fetches the background art.
    Q_INVOKABLE void requestArt(const QString &id, bool full = false);
    /// Updates one row in place (for example after a details load reported new artwork).
    Q_INVOKABLE void patchRow(const QString &id, const QVariantMap &values);

    const QVariantMap *find(const QString &id) const;
    const QStringList &order() const { return m_order; }
    const QVector<Group> &groups() const { return m_groups; }

signals:
    void viewChanged();
    void rowsChanged();
    void artChanged(const QString &id);

private:
    void flushArtRequests();

    QPointer<BridgeClient> m_bridge;
    QHash<QString, QVariantMap> m_rows;
    QStringList m_order;
    QVector<Group> m_groups;
    QString m_warning;
    GameListModel *m_games;
    GameListModel *m_list;
    QSet<QString> m_requested;
    QSet<QString> m_requestedFull;
    QStringList m_queue;
    QStringList m_queueFull;
    QTimer m_artTimer;
    int m_artInFlight = 0;
};
