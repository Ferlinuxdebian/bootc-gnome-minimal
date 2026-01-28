#!/bin/bash
set -e

flatpak remote-delete fedora
sleep 2
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
sleep 2
flatpak install -y flathub \
app.drey.Dialect \
be.alexandervanhee.gradia \
ca.desrt.dconf-editor \
com.brave.Browser \
com.dec05eba.gpu_screen_recorder \
com.github.finefindus.eyedropper \
com.github.tchx84.Flatseal \
com.mattjakeman.ExtensionManager \
com.obsproject.Studio \
com.protonvpn.www \
com.spotify.Client \
fr.handbrake.ghb \
im.riot.Riot \
io.github.celluloid_player.Celluloid \
io.github.fabrialberio.pinapp \
io.github.flattool.Ignition \
io.github.flattool.Warehouse \
io.github.getnf.embellish \
io.github.josephmawa.TextCompare \
io.github.onionware_github.onionmedia \
io.github.thetumultuousunicornofdarkness.cpu-x \
io.gitlab.news_flash.NewsFlash \
io.missioncenter.MissionCenter \
io.mpv.Mpv \
io.typora.Typora \
nl.hjdskes.gcolor3 \
org.altlinux.Tuner \
org.deluge_torrent.deluge \
org.gimp.GIMP \
org.gnome.Calculator \
org.gnome.Evince \
org.gnome.Loupe \
org.gnome.font-viewer \
org.gnome.meld \
org.libreoffice.LibreOffice \
org.mozilla.Thunderbird \
org.mozilla.firefox \
org.shotcut.Shotcut \
org.telegram.desktop \
org.videolan.VLC \
page.codeberg.libre_menu_editor.LibreMenuEditor \
page.tesk.Refine \
xyz.tytanium.DoorKnocker

