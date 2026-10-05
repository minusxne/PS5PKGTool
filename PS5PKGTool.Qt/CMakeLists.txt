cmake_minimum_required(VERSION 3.21)

project(ps5pkgtool VERSION 1.2.0 LANGUAGES CXX
        DESCRIPTION "PS5 PKG Tool - Linux edition"
        HOMEPAGE_URL "https://github.com/pearlxcore/PS5PkgTool")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Network DBus Svg)
find_package(Qt6 6.5 QUIET COMPONENTS Multimedia)

qt_standard_project_setup(REQUIRES 6.5)

# Where the .NET bridge lives during development (dotnet build output); installs use
# <prefix>/lib/ps5pkgtool/bridge, which the app finds relative to its own binary.
set(PS5PKGTOOL_DEV_BRIDGE "${CMAKE_CURRENT_SOURCE_DIR}/../PS5PKGTool.Bridge/bin/Debug/net10.0/ps5pkgtool-bridge"
    CACHE FILEPATH "Bridge executable used when running from the build tree")

qt_add_executable(ps5pkgtool
    src/main.cpp
    src/BridgeClient.h src/BridgeClient.cpp
    src/LibraryStore.h src/LibraryStore.cpp
    src/TableModel.h src/TableModel.cpp
    src/FileBrowserModel.h src/FileBrowserModel.cpp
    src/Desktop.h src/Desktop.cpp
    src/DemoLibrary.h src/DemoLibrary.cpp
)

target_include_directories(ps5pkgtool PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

target_compile_definitions(ps5pkgtool PRIVATE
    PS5PKGTOOL_VERSION="${PROJECT_VERSION}"
    PS5PKGTOOL_DEV_BRIDGE="${PS5PKGTOOL_DEV_BRIDGE}")

file(GLOB PS5_QML RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS qml/*.qml)
file(GLOB PS5_ICONS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS resources/icons/*.svg)

# Keep every QML file next to the module's qmldir (qrc:/qt/qml/PS5PkgTool/) so the module's
# singletons and C++ types resolve without explicit imports; icons live in icons/ beside them.
foreach(file IN LISTS PS5_QML)
    get_filename_component(name ${file} NAME)
    set_source_files_properties(${file} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()
foreach(file IN LISTS PS5_ICONS)
    get_filename_component(name ${file} NAME)
    set_source_files_properties(${file} PROPERTIES QT_RESOURCE_ALIAS icons/${name})
endforeach()
set_source_files_properties(resources/app/ps5pkgtool-256.png PROPERTIES QT_RESOURCE_ALIAS app/ps5pkgtool-256.png)
set_source_files_properties(qml/Theme.qml qml/App.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(ps5pkgtool
    URI PS5PkgTool
    VERSION 1.0
    QML_FILES ${PS5_QML}
    RESOURCES ${PS5_ICONS} resources/app/ps5pkgtool-256.png
)

target_link_libraries(ps5pkgtool PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Network Qt6::DBus Qt6::Svg)

if (Qt6Multimedia_FOUND)
    target_compile_definitions(ps5pkgtool PRIVATE PS5PKGTOOL_HAVE_MULTIMEDIA=1)
endif()

if (CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(ps5pkgtool PRIVATE -Wall -Wextra -Wpedantic)
endif()

include(GNUInstallDirs)
install(TARGETS ps5pkgtool RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES resources/app/ps5pkgtool.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES resources/app/io.github.pearlxcore.PS5PkgTool.metainfo.xml DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo)
foreach(size 64 128 256)
    install(FILES resources/app/ps5pkgtool-${size}.png
            DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/${size}x${size}/apps RENAME ps5pkgtool.png)
endforeach()
