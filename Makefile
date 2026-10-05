# Shortcuts for the Linux edition. Run "make help" for the list.
PREFIX ?= $(HOME)/.local

.PHONY: help setup build run demo test install uninstall appimage clean

help:
	@echo "make setup      install dependencies, build and install for your user (guided)"
	@echo "make build      build into ./dist"
	@echo "make run        build, then start the app from ./dist"
	@echo "make demo       build, then start with the fictional demo library"
	@echo "make test       run the engine's test suite"
	@echo "make install    build and install to PREFIX (default: ~/.local)"
	@echo "make uninstall  remove the installation from PREFIX"
	@echo "make appimage   build an AppImage"
	@echo "make clean      remove build outputs"

setup:
	./setup-linux.sh

build:
	./build-linux.sh

run: build
	./dist/bin/ps5pkgtool

demo: build
	./dist/bin/ps5pkgtool --demo

test:
	$${DOTNET:-$$(command -v dotnet || echo $(HOME)/.dotnet/dotnet)} test PS5PKGTool.Linux.slnx

install:
	./build-linux.sh --install "$(PREFIX)"

uninstall:
	./setup-linux.sh --uninstall --prefix "$(PREFIX)"

appimage:
	./build-linux.sh --appimage

clean:
	rm -rf build dist PS5_PKG_Tool-x86_64.AppImage
