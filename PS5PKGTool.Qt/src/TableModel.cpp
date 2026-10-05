#include "TableModel.h"

#include <QCollator>
#include <algorithm>

TableModel::TableModel(QObject *parent)
    : QAbstractTableModel(parent)
{
}

int TableModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : static_cast<int>(m_visible.size());
}

int TableModel::columnCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : static_cast<int>(m_columns.size());
}

QHash<int, QByteArray> TableModel::roleNames() const
{
    return {{Qt::DisplayRole, "display"}};
}

QVariant TableModel::data(const QModelIndex &index, int role) const
{
    if (role != Qt::DisplayRole || !index.isValid() || index.row() >= m_visible.size())
        return {};
    const QStringList &row = m_rows.at(m_visible.at(index.row()));
    return index.column() < row.size() ? row.at(index.column()) : QString();
}

QVariant TableModel::headerData(int section, Qt::Orientation orientation, int role) const
{
    if (role != Qt::DisplayRole)
        return {};
    if (orientation == Qt::Horizontal)
        return section >= 0 && section < m_columns.size() ? m_columns.at(section) : QString();
    return section + 1;
}

void TableModel::setTable(const QVariantMap &table)
{
    beginResetModel();
    m_table = table;
    m_columns.clear();
    m_rows.clear();
    for (const QVariant &column : table.value(QStringLiteral("columns")).toList())
        m_columns.append(column.toString());
    for (const QVariant &row : table.value(QStringLiteral("rows")).toList()) {
        QStringList cells;
        for (const QVariant &cell : row.toList())
            cells.append(cell.toString());
        m_rows.append(cells);
    }
    m_sortColumn = -1;
    m_sortAscending = true;
    m_visible.clear();
    for (int i = 0; i < m_rows.size(); ++i)
        m_visible.append(i);
    endResetModel();
    refilter();
    emit tableChanged();
    emit sortChanged();
}

void TableModel::setFilter(const QString &filter)
{
    if (m_filter == filter)
        return;
    m_filter = filter;
    refilter();
    emit filterChanged();
}

void TableModel::refilter()
{
    beginResetModel();
    m_visible.clear();
    const QString needle = m_filter.trimmed();
    for (int i = 0; i < m_rows.size(); ++i) {
        if (needle.isEmpty() || std::any_of(m_rows.at(i).cbegin(), m_rows.at(i).cend(), [&needle](const QString &cell) {
                return cell.contains(needle, Qt::CaseInsensitive);
            }))
            m_visible.append(i);
    }
    if (m_sortColumn >= 0) {
        QCollator collator;
        collator.setNumericMode(true);
        collator.setCaseSensitivity(Qt::CaseInsensitive);
        const int column = m_sortColumn;
        const bool ascending = m_sortAscending;
        std::stable_sort(m_visible.begin(), m_visible.end(), [&](int a, int b) {
            const QString left = column < m_rows.at(a).size() ? m_rows.at(a).at(column) : QString();
            const QString right = column < m_rows.at(b).size() ? m_rows.at(b).at(column) : QString();
            const int result = collator.compare(left, right);
            return ascending ? result < 0 : result > 0;
        });
    }
    endResetModel();
    emit countChanged();
}

int TableModel::columnWidth(int column, int charWidth) const
{
    if (column < 0 || column >= m_columns.size())
        return 80;
    qsizetype longest = m_columns.at(column).size() + 2;
    int sampled = 0;
    for (const QStringList &row : m_rows) {
        if (column < row.size())
            longest = std::max(longest, row.at(column).size());
        if (++sampled > 400)
            break;
    }
    return static_cast<int>(std::clamp<qsizetype>(longest, 4, 60) * charWidth + 24);
}

void TableModel::sortBy(int column)
{
    if (m_sortColumn == column)
        m_sortAscending = !m_sortAscending;
    else {
        m_sortColumn = column;
        m_sortAscending = true;
    }
    refilter();
    emit sortChanged();
}

QStringList TableModel::rowAt(int row) const
{
    return row >= 0 && row < m_visible.size() ? m_rows.at(m_visible.at(row)) : QStringList();
}

QString TableModel::copyText(int row) const
{
    if (row >= 0)
        return rowAt(row).join(QLatin1Char('\t'));
    QStringList lines{m_columns.join(QLatin1Char('\t'))};
    for (int index : m_visible)
        lines.append(m_rows.at(index).join(QLatin1Char('\t')));
    return lines.join(QLatin1Char('\n'));
}
