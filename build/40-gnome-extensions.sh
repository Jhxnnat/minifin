#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# GNOME Shell extensions
###############################################################################
# Installs the image's GNOME Shell extensions system-wide and enables them for
# every user, including users created after the image was built.
#
# Each extension is unpacked into /usr/share/gnome-shell/extensions/<uuid>/,
# where the directory name has to be the uuid the extension declares in its
# metadata.json. Enabling happens through the org.gnome.shell enabled-extensions
# schema default, which is how Bluefin enables its own set. A user who has
# already chosen extensions in dconf keeps that choice.
#
# The set is deliberately small; add a uuid to EGO_EXTENSIONS to ship more.
###############################################################################

# The shell major version is what extensions.gnome.org knows about (50.4 -> 50).
SHELL_MAJOR="$(gnome-shell --version | awk '{print $3}' | cut -d. -f1)"
EXTENSIONS_DIR=/usr/share/gnome-shell/extensions
OVERRIDE_FILE=/usr/share/glib-2.0/schemas/zz1-custom-extensions.gschema.override

# Every uuid installed below. Used in the enable step to build the list, so it
# never has to be kept in sync by hand.
INSTALLED_EXTENSIONS=()

###############################################################################
# 1. From extensions.gnome.org
###############################################################################
# One line per extension, by uuid. Any uuid from https://extensions.gnome.org
# works; the site does not check packages against your shell version, so pick
# ones whose pages list this GNOME release.

EGO_EXTENSIONS=(
	caffeine@patapon.info
	just-perfection-desktop@just-perfection
)

for uuid in "${EGO_EXTENSIONS[@]}"; do
	info_url="https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${SHELL_MAJOR}"
	download_path="$(curl -fsSL "${info_url}" | jq -r .download_url)"

	mkdir -p "${EXTENSIONS_DIR}/${uuid}"
	curl -fsSL "https://extensions.gnome.org${download_path}" -o /tmp/extension.zip
	unzip -q -o /tmp/extension.zip -d "${EXTENSIONS_DIR}/${uuid}"
	rm -f /tmp/extension.zip

	INSTALLED_EXTENSIONS+=("${uuid}")
done

###############################################################################
# 2. Enable them
###############################################################################

# Extensions ship schema XML, never a compiled cache, and some ship no schemas.
shopt -s nullglob
for schemas_dir in "${EXTENSIONS_DIR}"/*/schemas; do
	glib-compile-schemas --strict "${schemas_dir}"
done
shopt -u nullglob

# enabled-extensions is a single array, so this list replaces the default the
# base image ships. Fedora's background-logo entry is kept, then everything
# installed above is appended.
ENABLED_LIST="'background-logo@fedorahosted.org'"
for uuid in "${INSTALLED_EXTENSIONS[@]}"; do
	ENABLED_LIST+=", '${uuid}'"
done

{
	echo "[org.gnome.shell]"
	echo "enabled-extensions=[${ENABLED_LIST}]"
} >"${OVERRIDE_FILE}"

# Rebuild the system schema cache so the override takes effect.
rm -f /usr/share/glib-2.0/schemas/gschemas.compiled
glib-compile-schemas /usr/share/glib-2.0/schemas
