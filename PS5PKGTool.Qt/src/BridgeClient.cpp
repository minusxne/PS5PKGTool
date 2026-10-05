#include "BridgeClient.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJSEngine>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcessEnvironment>
#include <QStandardPaths>
#include <QTimer>

BridgeClient::BridgeClient(QObject *parent)
    : QObject(parent)
{
    m_process.setProcessChannelMode(QProcess::SeparateChannels);
    connect(&m_process, &QProcess::readyReadStandardOutput, this, &BridgeClient::readStdout);
    connect(&m_process, &QProcess::readyReadStandardError, this, &BridgeClient::readStderr);
    connect(&m_process, &QProcess::finished, this, &BridgeClient::onFinished);
    connect(&m_process, &QProcess::stateChanged, this, [this] { emit connectedChanged(); });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            const QString message = tr("The PS5 PKG Tool engine could not be started (%1).").arg(m_executable);
            setStatus(message);
            emit failed(message);
        }
    });
}

BridgeClient::~BridgeClient()
{
    stop();
}

QString BridgeClient::locateBridge()
{
    const QString overridden = qEnvironmentVariable("PS5PKGTOOL_BRIDGE");
    if (!overridden.isEmpty())
        return overridden;

    const QString appDir = QCoreApplication::applicationDirPath();
    const QStringList candidates = {
        appDir + QStringLiteral("/../lib/ps5pkgtool/bridge/ps5pkgtool-bridge"),
        appDir + QStringLiteral("/bridge/ps5pkgtool-bridge"),
        appDir + QStringLiteral("/../bridge/ps5pkgtool-bridge"),
        QStringLiteral("/usr/lib/ps5pkgtool/bridge/ps5pkgtool-bridge"),
        QStringLiteral(PS5PKGTOOL_DEV_BRIDGE),
    };
    for (const QString &candidate : candidates) {
        QFileInfo info(candidate);
        if (info.exists() && info.isExecutable())
            return info.canonicalFilePath();
    }
    return candidates.last();
}

void BridgeClient::start()
{
    if (m_process.state() != QProcess::NotRunning)
        return;
    m_stopping = false;
    m_executable = locateBridge();
    setReady(false);
    setStatus(tr("Starting the engine…"));

    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    // A framework-dependent development build needs to find a user-local .NET install.
    if (!env.contains(QStringLiteral("DOTNET_ROOT"))) {
        const QString userDotnet = QDir::homePath() + QStringLiteral("/.dotnet");
        if (QFileInfo::exists(userDotnet + QStringLiteral("/dotnet")))
            env.insert(QStringLiteral("DOTNET_ROOT"), userDotnet);
    }
    env.insert(QStringLiteral("DOTNET_CLI_TELEMETRY_OPTOUT"), QStringLiteral("1"));
    m_process.setProcessEnvironment(env);
    m_process.setWorkingDirectory(QFileInfo(m_executable).absolutePath());
    m_process.start(m_executable, {});
}

void BridgeClient::stop()
{
    if (m_process.state() == QProcess::NotRunning)
        return;
    m_stopping = true;
    const QByteArray request = QJsonDocument(QJsonObject{{QStringLiteral("id"), 0},
                                                         {QStringLiteral("method"), QStringLiteral("app.shutdown")}})
                                   .toJson(QJsonDocument::Compact) + '\n';
    m_process.write(request);
    m_process.closeWriteChannel();
    if (!m_process.waitForFinished(4000)) {
        m_process.terminate();
        if (!m_process.waitForFinished(2000))
            m_process.kill();
    }
}

int BridgeClient::call(const QString &method, const QVariantMap &params, const QJSValue &onResult, const QJSValue &onError)
{
    QJSValue ok = onResult;
    QJSValue err = onError;
    QPointer<QJSEngine> engine = m_engine;
    return callNative(
        method, params,
        [ok, engine](const QVariant &result) mutable {
            if (ok.isCallable() && engine)
                ok.call({engine->toScriptValue(result)});
        },
        [err, engine, method](const QVariantMap &error) mutable {
            if (err.isCallable() && engine)
                err.call({engine->toScriptValue(error)});
            else
                qWarning().noquote() << "bridge:" << method << "failed:" << error.value(QStringLiteral("message")).toString();
        });
}

int BridgeClient::callNative(const QString &method, const QVariantMap &params, ResultHandler onResult, ErrorHandler onError)
{
    const int id = m_nextId++;
    if (m_process.state() != QProcess::Running) {
        QVariantMap error{{QStringLiteral("code"), QStringLiteral("offline")},
                          {QStringLiteral("message"), tr("The engine is not running.")}};
        if (onError)
            QTimer::singleShot(0, this, [onError, error] { onError(error); });
        return id;
    }
    m_pending.insert(id, Pending{method, std::move(onResult), std::move(onError)});
    QJsonObject request{{QStringLiteral("id"), id},
                        {QStringLiteral("method"), method},
                        {QStringLiteral("params"), QJsonObject::fromVariantMap(params)}};
    m_process.write(QJsonDocument(request).toJson(QJsonDocument::Compact) + '\n');
    return id;
}

void BridgeClient::cancel(int id)
{
    if (!m_pending.contains(id))
        return;
    callNative(QStringLiteral("call.cancel"), {{QStringLiteral("id"), id}}, nullptr, nullptr);
}

void BridgeClient::readStdout()
{
    m_buffer.append(m_process.readAllStandardOutput());
    qsizetype newline;
    while ((newline = m_buffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_buffer.left(newline);
        m_buffer.remove(0, newline + 1);
        if (!line.trimmed().isEmpty())
            handleLine(line);
    }
}

void BridgeClient::readStderr()
{
    m_errorBuffer.append(m_process.readAllStandardError());
    qsizetype newline;
    while ((newline = m_errorBuffer.indexOf('\n')) >= 0) {
        const QString line = QString::fromUtf8(m_errorBuffer.left(newline)).trimmed();
        m_errorBuffer.remove(0, newline + 1);
        if (!line.isEmpty())
            emit stderrLine(line);
    }
}

void BridgeClient::handleLine(const QByteArray &line)
{
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        emit stderrLine(QString::fromUtf8(line));
        return;
    }
    const QJsonObject message = document.object();
    if (message.contains(QStringLiteral("event"))) {
        const QString name = message.value(QStringLiteral("event")).toString();
        const QVariant data = message.value(QStringLiteral("data")).toVariant();
        if (name == QStringLiteral("ready")) {
            m_restarts = 0;
            setStatus(QString());
            setReady(true);
        }
        emit event(name, data);
        return;
    }

    const int id = message.value(QStringLiteral("id")).toInt();
    auto it = m_pending.find(id);
    if (it == m_pending.end())
        return;
    Pending pending = std::move(it.value());
    m_pending.erase(it);
    if (message.contains(QStringLiteral("error"))) {
        if (pending.onError)
            pending.onError(message.value(QStringLiteral("error")).toObject().toVariantMap());
        else
            qWarning().noquote() << "bridge:" << pending.method << "failed:"
                                 << message.value(QStringLiteral("error")).toObject().value(QStringLiteral("message")).toString();
    } else if (pending.onResult) {
        pending.onResult(message.value(QStringLiteral("result")).toVariant());
    }
}

void BridgeClient::onFinished(int exitCode, QProcess::ExitStatus status)
{
    setReady(false);
    m_buffer.clear();
    failAllPending(tr("The engine stopped."));
    if (m_stopping)
        return;
    const QString reason = status == QProcess::CrashExit ? tr("crashed") : tr("exited with code %1").arg(exitCode);
    if (m_restarts < 3) {
        ++m_restarts;
        setStatus(tr("The engine %1. Restarting…").arg(reason));
        QTimer::singleShot(800 * m_restarts, this, &BridgeClient::start);
    } else {
        const QString message = tr("The engine %1 repeatedly. Check the log, then restart PS5 PKG Tool.").arg(reason);
        setStatus(message);
        emit failed(message);
    }
}

void BridgeClient::failAllPending(const QString &message)
{
    const auto pending = std::exchange(m_pending, {});
    for (const Pending &entry : pending) {
        if (entry.onError)
            entry.onError({{QStringLiteral("code"), QStringLiteral("offline")}, {QStringLiteral("message"), message}});
    }
}

void BridgeClient::setStatus(const QString &status)
{
    if (m_status == status)
        return;
    m_status = status;
    emit statusChanged();
}

void BridgeClient::setReady(bool ready)
{
    if (m_ready == ready)
        return;
    m_ready = ready;
    emit readyChanged();
}
