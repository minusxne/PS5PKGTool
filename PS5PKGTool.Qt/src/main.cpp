#include "BridgeClient.h"
#include "DemoLibrary.h"
#include "Desktop.h"
#include "LibraryStore.h"

#include <QCommandLineParser>
#include <QDir>
#include <QFileInfo>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QIcon>
#include <QLocalServer>
#include <QLocalSocket>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTimer>

namespace {

QString instanceName()
{
    return QStringLiteral("ps5pkgtool-%1").arg(qEnvironmentVariable("USER", QStringLiteral("user")));
}

/// Forwards the arguments to an already running instance; true when one answered.
bool forwardToRunningInstance(const QStringList &paths)
{
    QLocalSocket socket;
    socket.connectToServer(instanceName());
    if (!socket.waitForConnected(300))
        return false;
    socket.write((paths.isEmpty() ? QStringLiteral("activate") : paths.join(QLatin1Char('\n'))).toUtf8());
    socket.waitForBytesWritten(1000);
    socket.disconnectFromServer();
    return true;
}

void chooseFont(QGuiApplication &app)
{
    const QStringList families = QFontDatabase::families();
    for (const QString &preferred : {QStringLiteral("Inter"), QStringLiteral("Noto Sans"), QStringLiteral("Cantarell"),
                                     QStringLiteral("Ubuntu"), QStringLiteral("DejaVu Sans")}) {
        if (families.contains(preferred)) {
            QFont font(preferred);
            font.setPointSizeF(10.5);
            font.setHintingPreference(QFont::PreferNoHinting);
            app.setFont(font);
            return;
        }
    }
}

} // namespace

int main(int argc, char *argv[])
{
    QGuiApplication::setHighDpiScaleFactorRoundingPolicy(Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("PS5 PKG Tool"));
    QGuiApplication::setApplicationDisplayName(QStringLiteral("PS5 PKG Tool"));
    QGuiApplication::setApplicationVersion(QStringLiteral(PS5PKGTOOL_VERSION));
    QGuiApplication::setOrganizationName(QStringLiteral("PS5PKGTool"));
    QGuiApplication::setDesktopFileName(QStringLiteral("ps5pkgtool"));
    QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/qt/qml/PS5PkgTool/app/ps5pkgtool-256.png")));

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Manage, inspect, convert and build PS5 dumps, images and debug packages."));
    parser.addHelpOption();
    parser.addVersionOption();
    parser.addPositionalArgument(QStringLiteral("paths"), QStringLiteral("Dump folders, packages or images to open."), QStringLiteral("[paths...]"));
    QCommandLineOption demoOption(QStringLiteral("demo"),
                                  QStringLiteral("Start with a separate profile and a generated library of fictional demo titles."));
    QCommandLineOption screenshotOption(QStringLiteral("screenshot"), QStringLiteral("Render a page, save it to <file> and exit."),
                                        QStringLiteral("file"));
    QCommandLineOption pageOption(QStringLiteral("page"), QStringLiteral("Page for --screenshot: games, grid, list, details, tools, tasks, settings."),
                                  QStringLiteral("page"), QStringLiteral("games"));
    QCommandLineOption sizeOption(QStringLiteral("size"), QStringLiteral("Window size, for example 1600x900."), QStringLiteral("size"));
    parser.addOptions({demoOption, screenshotOption, pageOption, sizeOption});
    parser.process(app);

    const QStringList paths = [&] {
        QStringList result;
        for (const QString &path : parser.positionalArguments())
            result.append(QFileInfo(path).absoluteFilePath());
        return result;
    }();
    const bool demo = parser.isSet(demoOption);
    const QString screenshot = parser.value(screenshotOption);

    // One window per user: a second launch hands its paths to the running instance.
    QLocalServer instanceServer;
    if (!demo && screenshot.isEmpty()) {
        if (forwardToRunningInstance(paths))
            return 0;
        QLocalServer::removeServer(instanceName());
        instanceServer.listen(instanceName());
    }

    QString demoLibrary;
    if (demo) {
        // The demo uses its own profile so it never touches the real library or settings.
        const QString profile = QDir(QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation))
                                    .filePath(QStringLiteral("ps5pkgtool-demo"));
        qputenv("XDG_DATA_HOME", (profile + QStringLiteral("/data")).toUtf8());
        qputenv("XDG_CACHE_HOME", (profile + QStringLiteral("/cache")).toUtf8());
        demoLibrary = DemoLibrary::create(profile + QStringLiteral("/library"));
    }

    QQuickStyle::setStyle(QStringLiteral("Basic"));
    chooseFont(app);

    BridgeClient bridge;
    LibraryStore library(&bridge);
    Desktop desktop;

    QQmlApplicationEngine engine;
    bridge.setEngine(&engine);
    qmlRegisterSingletonInstance("PS5PkgTool.Native", 1, 0, "Bridge", &bridge);
    qmlRegisterSingletonInstance("PS5PkgTool.Native", 1, 0, "Library", &library);
    qmlRegisterSingletonInstance("PS5PkgTool.Native", 1, 0, "Desktop", &desktop);
    qmlRegisterUncreatableType<GameListModel>("PS5PkgTool.Native", 1, 0, "GameListModel", QStringLiteral("Provided by Library"));

    QVariantMap startup{{QStringLiteral("openPaths"), paths},
                        {QStringLiteral("demoLibrary"), demoLibrary},
                        {QStringLiteral("screenshot"), screenshot},
                        {QStringLiteral("page"), parser.value(pageOption)}};
    engine.setInitialProperties({{QStringLiteral("startup"), startup}});

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(1); },
                     Qt::QueuedConnection);
    engine.loadFromModule("PS5PkgTool", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());

    if (parser.isSet(sizeOption) && window) {
        const QStringList size = parser.value(sizeOption).split(QLatin1Char('x'));
        if (size.size() == 2)
            window->resize(size.at(0).toInt(), size.at(1).toInt());
    }

    QObject::connect(&instanceServer, &QLocalServer::newConnection, &app, [&instanceServer, window] {
        QLocalSocket *socket = instanceServer.nextPendingConnection();
        QObject::connect(socket, &QLocalSocket::readyRead, socket, [socket, window] {
            const QString payload = QString::fromUtf8(socket->readAll());
            if (window) {
                window->show();
                window->raise();
                window->requestActivate();
                if (payload != QStringLiteral("activate"))
                    QMetaObject::invokeMethod(window, "openPaths", Q_ARG(QVariant, payload.split(QLatin1Char('\n'))));
            }
            socket->deleteLater();
        });
    });

    if (!screenshot.isEmpty() && window) {
        // The QML side emits screenshotReady() once the requested page is populated.
        QObject::connect(window, SIGNAL(screenshotReady()), &app, SLOT(quit()));
        QTimer::singleShot(60000, &app, [] {
            qWarning("Screenshot timed out.");
            QCoreApplication::exit(2);
        });
    }

    bridge.start();
    const int result = QGuiApplication::exec();
    bridge.stop();
    return result;
}
