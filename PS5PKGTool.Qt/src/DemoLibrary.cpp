#include "DemoLibrary.h"

#include <QDir>
#include <QFileInfo>
#include <cmath>
#include <cstring>
#include <QFile>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>
#include <QRadialGradient>
#include <QRandomGenerator>

namespace {

struct DemoTitle
{
    const char *titleId;
    const char *name;
    const char *region;
    int category; // 0 game, 1 DLC, 2 patch
    const char *version;
    QRgb from;
    QRgb to;
    int dataMb;
};

// Fictional titles only; the IDs use the unassigned PPSA9xxxx range.
const DemoTitle kTitles[] = {
    {"PPSA90001", "Nebula Drift", "UP", 0, "01.000.000", 0xff1b2a6b, 0xffe0457b, 6},
    {"PPSA90001", "Nebula Drift", "UP", 2, "01.004.000", 0xff1b2a6b, 0xffe0457b, 2},
    {"PPSA90001", "Nebula Drift", "UP", 2, "01.012.000", 0xff1b2a6b, 0xffe0457b, 2},
    {"PPSA90002", "Crystal Pines", "EP", 0, "01.000.000", 0xff0f4c45, 0xff9ee6c9, 5},
    {"PPSA90003", "Iron Tide Racing", "UP", 0, "01.000.000", 0xff3a1010, 0xffff8a3d, 7},
    {"PPSA90003", "Iron Tide Racing: Night Circuit", "UP", 1, "01.000.000", 0xff1c0f2e, 0xffff8a3d, 1},
    {"PPSA90004", "Paper Lantern", "JP", 0, "01.000.000", 0xff2b1c08, 0xfff3c969, 3},
    {"PPSA90005", "Hollow Signal", "EP", 0, "01.000.000", 0xff07131f, 0xff3fa7ff, 4},
    {"PPSA90006", "Starlit Workshop", "UP", 0, "01.000.000", 0xff2a0f3d, 0xffb48cff, 2},
    {"PPSA90007", "Granite Kingdoms", "UP", 0, "01.000.000", 0xff1a1d22, 0xff8fa3b8, 5},
};

void paintArt(QImage &image, const DemoTitle &title, bool icon)
{
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing);
    const QRectF bounds = image.rect();
    QLinearGradient gradient(bounds.topLeft(), bounds.bottomRight());
    gradient.setColorAt(0, QColor::fromRgb(title.from));
    gradient.setColorAt(1, QColor::fromRgb(title.to));
    painter.fillRect(bounds, gradient);

    QRandomGenerator random(qHash(QByteArray(title.name)));
    for (int i = 0; i < 9; ++i) {
        const double radius = bounds.width() * (0.08 + random.bounded(0.35));
        const QPointF centre(random.bounded(bounds.width()), random.bounded(bounds.height()));
        QRadialGradient glow(centre, radius);
        QColor tint = i % 2 ? QColor::fromRgb(title.to) : QColor(255, 255, 255);
        tint.setAlphaF(0.10 + random.bounded(0.18));
        glow.setColorAt(0, tint);
        tint.setAlpha(0);
        glow.setColorAt(1, tint);
        painter.setBrush(glow);
        painter.setPen(Qt::NoPen);
        painter.drawEllipse(centre, radius, radius);
    }
    // A horizon of soft hills gives every title a "scene".
    QPainterPath hills;
    hills.moveTo(0, bounds.height());
    for (int x = 0; x <= 8; ++x)
        hills.lineTo(bounds.width() * x / 8.0, bounds.height() * (0.68 + 0.12 * std::sin(x * 1.3 + qHash(QByteArray(title.name)) % 7)));
    hills.lineTo(bounds.width(), bounds.height());
    hills.closeSubpath();
    painter.fillPath(hills, QColor(0, 0, 0, 90));

    QFont font(QStringLiteral("Sans Serif"));
    font.setWeight(QFont::DemiBold);
    painter.setPen(QColor(255, 255, 255, 235));
    if (icon) {
        const QString words = QString::fromUtf8(title.name).section(QLatin1Char(':'), 0, 0);
        font.setPixelSize(static_cast<int>(bounds.height() * 0.13));
        painter.setFont(font);
        painter.drawText(bounds.adjusted(bounds.width() * 0.08, 0, -bounds.width() * 0.08, -bounds.height() * 0.1),
                         Qt::AlignHCenter | Qt::AlignBottom | Qt::TextWordWrap, words.toUpper());
        if (title.category == 1) {
            font.setPixelSize(static_cast<int>(bounds.height() * 0.07));
            painter.setFont(font);
            painter.drawText(bounds.adjusted(0, bounds.height() * 0.08, 0, 0), Qt::AlignHCenter | Qt::AlignTop, QStringLiteral("ADD-ON"));
        }
    }
    font.setPixelSize(static_cast<int>(bounds.height() * (icon ? 0.045 : 0.022)));
    font.setWeight(QFont::Normal);
    painter.setFont(font);
    painter.setPen(QColor(255, 255, 255, 150));
    painter.drawText(bounds.adjusted(0, 0, -bounds.width() * 0.03, -bounds.height() * 0.03), Qt::AlignRight | Qt::AlignBottom,
                     QStringLiteral("DEMO"));
}

void writeFile(const QString &path, const QByteArray &bytes)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        file.write(bytes);
}

QByteArray minimalElf()
{
    QByteArray elf(8192, '\0');
    const char header[] = {0x7f, 'E', 'L', 'F', 2, 1, 1, 0};
    memcpy(elf.data(), header, sizeof header);
    elf[16] = 2;    // ET_EXEC
    elf[18] = 0x3e; // x86-64
    elf[20] = 1;
    elf[32] = 64;   // e_phoff
    elf[52] = 64;   // e_ehsize
    elf[54] = 56;   // e_phentsize
    elf[56] = 1;    // e_phnum
    elf[64] = 1;    // PT_LOAD
    elf[68] = 5;
    elf[73] = 0x10; // p_offset 0x1000
    elf[82] = 0x40; // p_vaddr 0x400000
    elf[90] = 0x40;
    elf[97] = 0x10; // p_filesz 0x1000
    elf[105] = 0x10;
    elf[113] = 0x40;
    return elf;
}

} // namespace

QString DemoLibrary::create(const QString &directory)
{
    QDir().mkpath(directory);
    for (const DemoTitle &title : kTitles) {
        const QString kind = title.category == 0 ? QStringLiteral("app") : title.category == 1 ? QStringLiteral("ac")
                                                                                              : QStringLiteral("patch");
        const QString root = QDir(directory).filePath(QStringLiteral("%1-%2-%3").arg(QLatin1String(title.titleId), kind,
                                                                                      QString::fromLatin1(title.version).replace('.', '_')));
        if (QFileInfo::exists(root + QStringLiteral("/sce_sys/param.json")))
            continue;
        const QString contentId = QStringLiteral("%1%2-%3_00-%4")
                                      .arg(QLatin1String(title.region), QStringLiteral("9999"), QLatin1String(title.titleId),
                                           title.category == 1 ? QStringLiteral("NIGHTCIRCUIT0000") : QStringLiteral("DEMOTITLE0000000"));
        QJsonObject localized{{QStringLiteral("defaultLanguage"), QStringLiteral("en-US")},
                              {QStringLiteral("en-US"), QJsonObject{{QStringLiteral("titleName"), QString::fromUtf8(title.name)}}}};
        QJsonObject param{
            {QStringLiteral("titleId"), QLatin1String(title.titleId)},
            {QStringLiteral("contentId"), contentId},
            {QStringLiteral("conceptId"), QStringLiteral("9%1").arg(QLatin1String(title.titleId).mid(5))},
            {QStringLiteral("contentVersion"), QLatin1String(title.version)},
            {QStringLiteral("masterVersion"), QStringLiteral("01.00")},
            {QStringLiteral("requiredSystemSoftwareVersion"),
             title.category == 2 ? QStringLiteral("0x0700000000000000") : QStringLiteral("0x0450000000000000")},
            {QStringLiteral("sdkVersion"), QStringLiteral("0x0450000000000000")},
            {QStringLiteral("applicationCategoryType"), title.category},
            {QStringLiteral("applicationDrmType"), QStringLiteral("standard")},
            {QStringLiteral("localizedParameters"), localized},
            {QStringLiteral("creationDate"), QStringLiteral("2026-01-15 10:00:00")},
        };
        writeFile(root + QStringLiteral("/sce_sys/param.json"), QJsonDocument(param).toJson());

        QImage icon(512, 512, QImage::Format_ARGB32_Premultiplied);
        paintArt(icon, title, true);
        icon.save(root + QStringLiteral("/sce_sys/icon0.png"));
        if (title.category != 1) {
            QImage keyArt(1920, 1080, QImage::Format_ARGB32_Premultiplied);
            paintArt(keyArt, title, false);
            keyArt.save(root + QStringLiteral("/sce_sys/pic0.png"));
        }
        writeFile(root + QStringLiteral("/eboot.bin"), minimalElf());
        writeFile(root + QStringLiteral("/README-DEMO.txt"),
                  "This folder was generated by PS5 PKG Tool --demo. It is not a real game.\n");
        QByteArray chunk(1024 * 1024, '\0');
        for (int i = 0; i < chunk.size(); ++i)
            chunk[i] = static_cast<char>((i * 31) % 251);
        for (int i = 0; i < title.dataMb; ++i)
            writeFile(root + QStringLiteral("/data/pack%1.dat").arg(i, 2, 10, QLatin1Char('0')), chunk);
    }
    return directory;
}
