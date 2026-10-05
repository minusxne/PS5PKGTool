# Third-party notices

PS5 PKG Tool is licensed under the GNU General Public License v3.0 (see `LICENSE`). The
components below are used under their own terms.

## ProsperoPkgTool

The PS5 PKG (FIH/CNT/PFS/NAPS) reading, verification, extraction and debug-package creation
implementation is provided by the clean-room MIT engine ProsperoPkgTool, consumed as a vendored
managed library at `PS5PKGTool/ThirdParty/ProsperoPkgTool/ProsperoPkgTool.dll`.

MIT License. Copyright (c) 2026 pearlxcore. No GPL, SDK, or decompiled code is included; the
engine is a clean-room reimplementation validated against independent oracles.

## LibProsperoPkg

The alternative package build/validate/extract backend is provided by LibProsperoPkg, loaded from a
vendored payload at `PS5PKGTool/ThirdParty/LibProsperoPkg12/` (version **1.2.0** - the version the
PPR-PKG / fpkg-gui builder ships; the newer 2.6.0 regressed the NAPS layout). It is loaded in an
isolated assembly-load context together with its bundled dependencies: `BCnEncoder.Net 2.3.0`,
`CommunityToolkit.HighPerformance 8.4.0`, `Magick.NET 14.15.0` (managed + its
`runtimes/win-x64/native/Magick.Native-Q8-x64.dll`), and `libScePubTools.dll`.

GNU General Public License v3.0 or later (GPL-3.0-or-later).
Copyright (c) SvenGDK 2026. https://github.com/SvenGDK/LibProsperoPkg

Because LibProsperoPkg is GPL-3.0-or-later and PS5 PKG Tool links it, the combined work is
distributed under the GPL-3.0 (see `LICENSE`). The full license text ships at
`PS5PKGTool/ThirdParty/LibProsperoPkg12/LICENSE`.

## UFS2Tool

The `PS5PKGTool.Ufs2` filesystem implementation is based on
[SvenGDK/UFS2Tool](https://github.com/SvenGDK/UFS2Tool), used and modified under the BSD 2-Clause
License. Copyright (c) 2026, SvenGDK. The original copyright and license text are retained in
`PS5PKGTool.Ufs2/LICENSE` and in the imported source files.

## DarkUI

The Windows edition's user interface is built on DarkUI, licensed under the MIT License.
Copyright (c) 2017 Robin (Robin Perris). https://github.com/RobinPerris/DarkUI

## BCnEncoder.Net

BCnEncoder.Net (and BCnEncoder.Net.ImageSharp) is distributed under the MIT License. It is used to
encode BC7 textures for PS5 CNT media. https://github.com/Nominom/BCnEncoder.NET

## Oodle.NET

Oodle.NET (MIT License, Copyright (c) 2025 NotOfficer) was the managed wrapper for the native Oodle
decoder. Kraken is now decoded and encoded by the managed engines, and the package reference has
been removed from `PS5PKGTool.Core`.

## Oodle Data Compression

This section applies to the Windows edition only; the Linux edition does not ship or load Oodle.

The Windows release of PS5PKGTool includes the 64 bit Oodle Data Compression 2.9.10 redistributable
`oo2core_9_win64.dll`. Oodle is proprietary Licensed Technology supplied by Epic Games
and RAD Game Tools and is used under the Unreal Engine End User License Agreement:
https://www.unrealengine.com/eula/unreal

Copyright Epic Games, Inc. and/or RAD Game Tools. All rights reserved.

The Oodle Licensed Technology is provided only as an incorporated object code component
of PS5PKGTool and only as needed to use PS5PKGTool. End users may not extract, reuse,
redistribute, or incorporate it into another product. To the maximum extent permitted by
applicable law, PS5PKGTool makes no representations or warranties and accepts no conditions
or liabilities relating to Epic Games' or RAD Game Tools' Licensed Technology.

Bundled file SHA256:
`6F5D41A7892EA6B2DB420F2458DAD2F84A63901C9A93CE9497337B16C195F457`

## Linux edition

The Linux edition (`PS5PKGTool.Bridge` and `PS5PKGTool.Qt`) adds the following components:

- **Qt 6** (Qt Base, Qt Declarative / Qt Quick, Qt Quick Controls, Qt SVG, Qt D-Bus, and optionally
  Qt Multimedia), used under the GNU Lesser General Public License v3.0 and dynamically linked.
  Copyright (c) The Qt Company Ltd. and other contributors. https://www.qt.io
- **.NET runtime**, MIT License, Copyright (c) .NET Foundation and Contributors. The engine is
  published self-contained, so the runtime ships next to `ps5pkgtool-bridge`.
- **Magick.NET native library for linux-x64** (`Magick.Native-Q8-x64.dll.so`, Magick.NET 14.15.0),
  Apache License 2.0, Copyright (c) Dirk Lemstra; it bundles ImageMagick (ImageMagick License).
  It is downloaded from NuGet at build time and placed next to the vendored LibProsperoPkg 1.2.0,
  which needs it to encode artwork. https://github.com/dlemstra/Magick.NET
- **LibProsperoPkg 1.2.0 on Linux**: the vendored payload is copied without
  `libScePubTools.dll` (a Windows-only C++/CLI assembly that cannot load on Linux) and without the
  win-x64 Magick native library.
- **xUnit** and the **Microsoft Test SDK** (Apache License 2.0 / MIT) are used by
  `PS5PKGTool.Bridge.Tests` only and are not distributed.
- The interface icons under `PS5PKGTool.Qt/resources/icons` and the procedurally generated demo
  artwork were made for this project and are covered by the project's GPL-3.0 license. The
  application icon is the Windows edition's icon.

## PS4 PKG Tool assets

The file-type icons under `PS5PKGTool/Resources` are reused from the PS4 PKG Tool project
(https://github.com/pearlxcore/PS4-PKG-Tool), which is licensed under the GNU General Public
License v3.0. Copyright (c) pearlxcore.

## Image format references

The managed exFAT, UFS2/FFPKG, PFSC and PFS implementations were written from public format
documentation and validated against independent tools. Credit to the authors of the tools that
document and handle these formats:

- MkPFS, PSBrew / Renan Barreto (https://github.com/PSBrew/MkPFS), PFS and PFSC/FFPFSC format work.
- UFS2Tool and LibProsperoPkg, SvenGDK (https://github.com/SvenGDK/UFS2Tool), UFS2/FFPKG work. UFS2Tool is used under the BSD 2-Clause License.
- ps5-exfat-builder, kerrdec97 (https://github.com/PSBrew/ps5-exfat-builder), exFAT format work.
- PS5 Dump and Image Converter, strongt1me (https://github.com/strongt1me/PS5-Dump-Image-Converter).
