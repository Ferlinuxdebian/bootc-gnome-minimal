#!/bin/bash
set -e

MARKER="/var/lib/flatpak-bootstrap.done"

if [ -f "$MARKER" ]; then
    exit 0
fi

flatpak remote-delete fedora || true
sleep 2
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
sleep 2

apps=(
app.drey.Dialect
be.alexandervanhee.gradia
ca.desrt.dconf-editor
com.brave.Browser
com.dec05eba.gpu_screen_recorder
com.github.finefindus.eyedropper
com.github.tchx84.Flatseal
com.mattjakeman.ExtensionManager
com.obsproject.Studio
com.protonvpn.www
com.spotify.Client
fr.handbrake.ghb
im.riot.Riot
io.github.fabrialberio.pinapp
io.github.flattool.Ignition
io.github.flattool.Warehouse
io.gitlab.news_flash.NewsFlash
io.mpv.Mpv
io.typora.Typora
net.nokyan.Resources
org.altlinux.Tuner
org.deluge_torrent.deluge
org.gimp.GIMP
org.gnome.Calculator
org.gnome.Evince
org.gnome.Loupe
org.gnome.Showtime
org.gnome.meld
org.libreoffice.LibreOffice
org.localsend.localsend_app
org.mozilla.firefox
org.shotcut.Shotcut
org.telegram.desktop
org.upscayl.Upscayl
org.videolan.VLC
page.codeberg.libre_menu_editor.LibreMenuEditor
page.tesk.Refine
xyz.tytanium.DoorKnocker
)

installed=$(flatpak list --app --columns=application)

missing=()

for app in "${apps[@]}"; do
    if ! grep -qx "$app" <<< "$installed"; then
        missing+=("$app")
    fi
done

if [ "${#missing[@]}" -eq 0 ]; then
    touch "$MARKER"
    exit 0
fi

echo "Instalando Flatpaks ausentes..."
flatpak install -y flathub "${missing[@]}"

touch "$MARKER"