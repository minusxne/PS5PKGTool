#pragma once

#include <QAbstractTableModel>
#include <QStringList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

/// A read-only string table ({columns, rows} from the bridge) with a text filter and sorting,
/// for the details page's data grids (UDS, executable, container, PlayGo…).
class TableModel : public QAbstractTableModel
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap table READ table WRITE setTable NOTIFY tableChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(QStringList columns READ columns NOTIFY tableChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY tableChanged)
    Q_PROPERTY(int sortColumn READ sortColumn NOTIFY sortChanged)
    Q_PROPERTY(bool sortAscending READ sortAscending NOTIFY sortChanged)
    QML_ELEMENT

public:
    explicit TableModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    int columnCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QVariant headerData(int section, Qt::Orientation orientation, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QVariantMap table() const { return m_table; }
    void setTable(const QVariantMap &table);
    QString filter() const { return m_filter; }
    void setFilter(const QString &filter);
    QStringList columns() const { return m_columns; }
    int count() const { return static_cast<int>(m_visible.size()); }
    int totalCount() const { return static_cast<int>(m_rows.size()); }
    int sortColumn() const { return m_sortColumn; }
    bool sortAscending() const { return m_sortAscending; }

    /// Suggested width in pixels for a column, from its longest value (capped).
    Q_INVOKABLE int columnWidth(int column, int charWidth = 8) const;
    Q_INVOKABLE void sortBy(int column);
    Q_INVOKABLE QStringList rowAt(int row) const;
    /// Tab-separated text of one row, or of every visible row when row is -1.
    Q_INVOKABLE QString copyText(int row = -1) const;

signals:
    void tableChanged();
    void filterChanged();
    void countChanged();
    void sortChanged();

private:
    void refilter();

    QVariantMap m_table;
    QStringList m_columns;
    QVector<QStringList> m_rows;
    QVector<int> m_visible;
    QString m_filter;
    int m_sortColumn = -1;
    bool m_sortAscending = true;
};
