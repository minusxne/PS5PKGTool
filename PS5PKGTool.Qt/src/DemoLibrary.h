#pragma once

#include <QString>

/// Generates a small library of fictional, clearly-labelled demo titles (unpacked dump folders
/// with procedurally drawn artwork). Used by --demo to explore the interface and to take the
/// README screenshots without real game data.
namespace DemoLibrary {
/// Creates the demo dumps under <directory> (idempotent) and returns the folder.
QString create(const QString &directory);
}
