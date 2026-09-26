PKG = com.nerdstrike.sysglance
VERSION = $(shell python3 -c "import json; print(json.load(open('metadata.json'))['KPlugin']['Version'])")

# qmllint is not on PATH on Fedora: it ships in <libdir>/qt6/bin beside the rest
# of the Qt tools. PATH wins where it has one (other distributions, a Qt built
# elsewhere); override with QML_LINT=/path/to/qmllint.
QML_LINT ?= $(shell command -v qmllint 2>/dev/null || echo /usr/lib64/qt6/bin/qmllint)

.PHONY: install upgrade uninstall lint restart dist

# Build the installable/store-uploadable package archive
dist: lint
	rm -f $(PKG)-v$(VERSION).plasmoid
	zip -r $(PKG)-v$(VERSION).plasmoid metadata.json contents LICENSE -x '*~'

install:
	kpackagetool6 --type Plasma/Applet --install .

upgrade: lint
	kpackagetool6 --type Plasma/Applet --upgrade .
	systemctl --user restart plasma-plasmashell.service

uninstall:
	kpackagetool6 --type Plasma/Applet --remove $(PKG)

lint:
	$(QML_LINT) contents/ui/*.qml contents/config/*.qml

restart:
	systemctl --user restart plasma-plasmashell.service
