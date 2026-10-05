#pragma once

#include <QHash>
#include <QJSValue>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QVariant>

#include <functional>

#include <QJSEngine>

/// Talks to the .NET bridge process (ps5pkgtool-bridge) over JSON lines on stdin/stdout.
/// Every call gets exactly one result or error; unsolicited events arrive through event().
/// The bridge is restarted automatically if it exits unexpectedly.
class BridgeClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString executable READ executable CONSTANT)

public:
    using ResultHandler = std::function<void(const QVariant &)>;
    using ErrorHandler = std::function<void(const QVariantMap &)>;

    explicit BridgeClient(QObject *parent = nullptr);
    ~BridgeClient() override;

    void setEngine(QJSEngine *engine) { m_engine = engine; }
    void start();
    void stop();

    bool connected() const { return m_process.state() == QProcess::Running; }
    bool ready() const { return m_ready; }
    QString status() const { return m_status; }
    QString executable() const { return m_executable; }

    /// Calls a bridge method. onResult(result) or onError({code, message, detail}) runs on the GUI thread.
    Q_INVOKABLE int call(const QString &method, const QVariantMap &params = {},
                         const QJSValue &onResult = QJSValue(), const QJSValue &onError = QJSValue());
    int callNative(const QString &method, const QVariantMap &params, ResultHandler onResult,
                   ErrorHandler onError = nullptr);
    Q_INVOKABLE void cancel(int id);

    static QString locateBridge();

signals:
    void event(const QString &name, const QVariant &data);
    void connectedChanged();
    void readyChanged();
    void statusChanged();
    void failed(const QString &message);
    void stderrLine(const QString &line);

private:
    struct Pending
    {
        QString method;
        ResultHandler onResult;
        ErrorHandler onError;
    };

    void readStdout();
    void readStderr();
    void handleLine(const QByteArray &line);
    void onFinished(int exitCode, QProcess::ExitStatus status);
    void failAllPending(const QString &message);
    void setStatus(const QString &status);
    void setReady(bool ready);

    QProcess m_process;
    QByteArray m_buffer;
    QByteArray m_errorBuffer;
    QHash<int, Pending> m_pending;
    int m_nextId = 1;
    int m_restarts = 0;
    bool m_ready = false;
    bool m_stopping = false;
    QString m_status;
    QString m_executable;
    QPointer<QJSEngine> m_engine;
};
