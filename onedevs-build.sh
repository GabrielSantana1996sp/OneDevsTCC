#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2025 Gabriel Santana
set -euo pipefail
DIST="trixie"
CODENAME="AlbertEinstein"
APPNAME="OneDevsOS - ${CODENAME}"
VOLUME="ONEDEVS_${CODENAME}_1.0"
PUBLISHER="OneDevsOS Project (${CODENAME})"
USERNAME="dev"
HOSTNAME="onedevs"
ARCH="amd64"
LIVEBUILD_DIR="$(pwd)"
PACKAGE_LIST="${LIVEBUILD_DIR}/config/package-lists/onedevs.list.chroot"
ARCHIVES_DIR="${LIVEBUILD_DIR}/config/archives"
COMMIT="38f0fe21e88015f157a1cfccbd06fc67a5e9bb18"
RAW="https://raw.githubusercontent.com/GabrielSantana1996sp/OneDevsTCC/${COMMIT}/IMG"
log()  { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
error(){ log "ERRO: $*"; exit 1; }
ONLINE=0
check_network() {
  if ! ip route show default >/dev/null 2>&1; then ONLINE=0; return 0; fi
  if bash -c "cat < /dev/null > /dev/tcp/8.8.8.8/53" >/dev/null 2>&1; then ONLINE=1; return 0; fi
  if ping -c1 -W3 8.8.8.8 >/dev/null 2>&1; then ONLINE=1; return 0; fi
  ONLINE=0
}
check_network
[ "${ONLINE}" -eq 1 ] && log "Rede detectada: modo ONLINE" || log "Nenhuma rede: modo OFFLINE"
check_dependencies() {
  log "Verificando dependências..."
  local DEPS="debootstrap live-build xorriso squashfs-tools syslinux-common isolinux"
  local MISSING=""
  for dep in $DEPS; do
    dpkg-query -W -f='${Status}' "$dep" 2>/dev/null | grep -q "install ok installed" || MISSING="$MISSING $dep"
  done
  if [ -n "$MISSING" ]; then
    log "Dependências faltando:$MISSING"
    sudo apt-get update -qq
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y $MISSING
  else
    log "Todas as dependências instaladas."
  fi
}
generate_livebuild_files() {
  log "Gerando arquivos do live-build..."
  mkdir -p config/{package-lists,hooks/live,apt,archives}
  mkdir -p config/includes.chroot/etc/{calamares/modules,calamares/scripts,apt/apt.conf.d}
  mkdir -p config/includes.chroot/etc/{lightdm/lightdm-gtk-greeter.conf.d,sysctl.d}
  mkdir -p config/includes.chroot/etc/skel/{Desktop,.config/autostart}
  mkdir -p config/includes.chroot/usr/share/{calamares/branding/onedevs,backgrounds/onedevs}
  mkdir -p config/includes.chroot/usr/share/{plymouth/themes/onedevs,applications,polkit-1/actions}
  mkdir -p config/includes.chroot/usr/local/bin

  # ── APT ───────────────────────────────────────────────────────────────────
  cat > config/apt/apt.conf <<'EOF'
Acquire::Check-Valid-Until "false";
Acquire::Check-Date "false";
EOF

  # FIX: sem bloqueio de grub-pc (conflito resolvido usando só grub-efi)
  cat > config/apt/preferences <<'EOF'
Package: *
Pin: release o=Debian
Pin-Priority: 500
EOF

  cat > config/includes.chroot/etc/apt/apt.conf.d/99onedevs <<'EOF'
Acquire::Check-Valid-Until "false";
Acquire::Check-Date "false";
EOF

  # ── Lista de pacotes ──────────────────────────────────────────────────────
  if [ ! -f config/package-lists/onedevs.list.chroot ]; then
    cat > config/package-lists/onedevs.list.chroot <<'EOF'
# Sistema Base
live-boot live-config live-config-systemd

# Desktop XFCE
xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
xfce4-session xfce4-power-manager xfce4-panel xfce4-settings
xfce4-terminal lxappearance feh
pasystray pavucontrol
thunar thunar-archive-plugin
mousepad
network-manager-gnome
lightdm-gtk-greeter-settings
xfce4-whiskermenu-plugin
papirus-icon-theme
adwaita-icon-theme

# Desenvolvimento
python3 python3-pip python3-venv
default-jdk default-jre
golang-go
nodejs npm
rustc cargo
ruby bundler
geany
vim neovim
git
make cmake autoconf automake
gdb

# Pentest
nmap
wireshark
aircrack-ng
medusa
john
nikto
sqlmap
binwalk
netcat-openbsd

# Bootloader UEFI (grub-efi APENAS — grub-pc conflita no Debian Trixie)
grub-efi-amd64
grub-efi-amd64-bin
grub-efi-amd64-signed
shim-signed
os-prober

# DevOps
podman
ansible
docker.io
systemd-container

# Segurança DevSecOps
apparmor
nftables
fail2ban
clamav clamav-daemon
gnupg
auditd
lynis
aide
tripwire
debsums
gpg
logcheck

# Utilitários
util-linux
tmux
htop
ranger
synaptic
keepassxc
curl wget
rsync
net-tools
bind9-dnsutils
traceroute
gparted
cups
bluez blueman
xdg-utils
gvfs
udisks2
gdebi
flatpak
fonts-noto fonts-noto-cjk
polkitd pkexec
snapd
chromium

# Instalador
calamares

# Fastfetch
fastfetch

# Plymouth
plymouth plymouth-themes

# Localização
locales keyboard-configuration console-setup

# Kernel e firmware
linux-image-amd64
firmware-linux
firmware-realtek
firmware-iwlwifi
firmware-misc-nonfree

# Xorg
xserver-xorg
xserver-xorg-video-all
mesa-utils
EOF
    log "Criada config/package-lists/onedevs.list.chroot"
  fi

  # FIX: sem exclude list — grub-efi é o único bootloader
  # (remover !grub-pc evita conflito de pacotes)

  # ── Hook 0001: configura grub-efi para UEFI ──────────────────────────────
  cat > config/hooks/live/0001-grub-efi-config.hook.chroot <<'EOF'
#!/bin/bash
set -e
mkdir -p /etc/default/grub.d
cat > /etc/default/grub.d/onedevs.cfg <<'GRUBCFG'
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="OneDevsOS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUBCFG
echo "grub-efi configurado para UEFI."
EOF
  chmod +x config/hooks/live/0001-grub-efi-config.hook.chroot

  # ── Hook 9997: assets do GitHub ───────────────────────────────────────────
  cat > config/hooks/live/9997-onedevs-assets.hook.chroot <<HOOKEOF
#!/bin/bash
set -e
echo "=== Baixando assets ==="
COMMIT="${COMMIT}"
RAW="https://raw.githubusercontent.com/GabrielSantana1996sp/OneDevsTCC/\${COMMIT}/IMG"
mkdir -p /usr/share/backgrounds/onedevs /usr/share/calamares/branding/onedevs
mkdir -p /etc/calamares/branding/onedevs /usr/share/plymouth/themes/onedevs
dl() { curl -fsSL --retry 3 --retry-delay 2 "\$1" -o "\$2" && echo "OK: \$3" || echo "AVISO: falha \$3"; }
dl "\${RAW}/Wallpapers/Classico.png"      /usr/share/backgrounds/onedevs/Classico.png      "Classico"
dl "\${RAW}/Wallpapers/Cosmos.png"        /usr/share/backgrounds/onedevs/Cosmos.png        "Cosmos"
dl "\${RAW}/Wallpapers/Energia.png"       /usr/share/backgrounds/onedevs/Energia.png       "Energia"
dl "\${RAW}/Wallpapers/RetroTerminal.png" /usr/share/backgrounds/onedevs/RetroTerminal.png "RetroTerminal"
dl "\${RAW}/Wallpapers/universe.png"      /usr/share/backgrounds/onedevs/universe.png      "universe"
dl "\${RAW}/Ligthdm/LigthDM.png"         /usr/share/backgrounds/onedevs/wallpaper.png     "LightDM wallpaper"
[ -s /usr/share/backgrounds/onedevs/wallpaper.png ] || \
  cp /usr/share/backgrounds/onedevs/Classico.png /usr/share/backgrounds/onedevs/wallpaper.png 2>/dev/null || true
dl "\${RAW}/Calamares/Calamares.png"      /usr/share/calamares/branding/onedevs/logo.png   "logo Calamares"
cp /usr/share/calamares/branding/onedevs/logo.png /etc/calamares/branding/onedevs/logo.png 2>/dev/null || true
dl "\${RAW}/BootSlash/Boot%20splash%20(Plymouth).png" /usr/share/plymouth/themes/onedevs/boot.png "boot splash"
# ── Fastfetch: config e arte ASCII do repositório ─────────────────────────
FF_COMMIT="a2c07762c6279c468a00c5cb61ad61d2a5945a93"
FF_RAW="https://raw.githubusercontent.com/GabrielSantana1996sp/OneDevsTCC/\${FF_COMMIT}"
mkdir -p /etc/fastfetch /etc/skel/.config/fastfetch
dl "\${FF_RAW}/onedevos.txt"    /etc/fastfetch/onedevsos.txt              "fastfetch art"
dl "\${FF_RAW}/fastfetch.jsonc" /etc/skel/.config/fastfetch/config.jsonc "fastfetch config"
echo "=== Assets OK ==="
HOOKEOF
  chmod +x config/hooks/live/9997-onedevs-assets.hook.chroot

  # ── Hook 9998: instala Nix ────────────────────────────────────────────────
  cat > config/hooks/live/9998-onedevs-external.hook.chroot <<'EOF'
#!/bin/bash
set -e
echo "Instalando Nix..."
sh <(curl --proto '=https' --tlsv1.2 -sSf https://nixos.org/nix/install) --daemon || true
[ -f /etc/profile.d/nix.sh ] && echo ". /etc/profile.d/nix.sh" >> /home/dev/.bashrc && chown dev:dev /home/dev/.bashrc || true
EOF
  chmod +x config/hooks/live/9998-onedevs-external.hook.chroot

  # ── Hook 9999: usuário e serviços ─────────────────────────────────────────
  cat > config/hooks/live/9999-onedevs-config.hook.chroot <<'EOF'
#!/bin/bash
set -e
echo "Configurando usuário e serviços..."
if ! id -u dev >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G sudo,netdev,plugdev,audio,video dev
  echo "dev:live" | chpasswd
fi
systemctl enable lightdm NetworkManager snapd.socket snapd.service || true
if [ -f /usr/share/plymouth/themes/onedevs/onedevs.plymouth ]; then
  plymouth-set-default-theme onedevs || true
  update-initramfs -u || true
fi
echo "dev ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/dev
chmod 440 /etc/sudoers.d/dev
chmod +x /etc/skel/Desktop/*.desktop 2>/dev/null || true
cat >> /etc/skel/.bashrc <<'BASHEOF'

# OneDevs OS — system info
if command -v fastfetch >/dev/null 2>&1; then
  fastfetch
fi
BASHEOF
cat > /etc/os-release <<'OSRELEASE'
NAME="OneDevsOS"
VERSION="1.0 (AlbertEinstein)"
ID=onedevs
ID_LIKE=debian
PRETTY_NAME="OneDevsOS 1.0 AlbertEinstein"
VERSION_ID="1.0"
VERSION_CODENAME=alberteinstein
HOME_URL="https://onedevsofficial@proton.me"
OSRELEASE
cat > /etc/issue <<'ISSUE'
OneDevsOS 1.0 AlbertEinstein - DevSecOps Edition
Usuário: dev | Senha: live
\l
ISSUE
echo "Configuração concluída."
EOF
  chmod +x config/hooks/live/9999-onedevs-config.hook.chroot

  # ── Calamares: settings.conf ──────────────────────────────────────────────
  cat > config/includes.chroot/etc/calamares/settings.conf <<'EOF'
---
modules-search: [ local, /usr/lib/calamares/modules ]
instances:
- id: remove-live
  module: shellprocess
  config: shellprocess@remove-live.conf
sequence:
- show:
  - welcome
  - locale
  - keyboard
  - partition
  - users
  - summary
- exec:
  - partition
  - mount
  - unpackfs
  - machineid
  - fstab
  - locale
  - keyboard
  - users
  - hwclock
  - bootloader
  - shellprocess@remove-live
  - umount
- show:
  - finished
branding: onedevs
prompt-install: true
dont-chroot: false
EOF

  # ── Calamares: partition.conf ─────────────────────────────────────────────
  # FIX: removido erase-ram15 inválido, adicionado partitionLayout correto
  # FIX: NÃO usar type:"ESP" nem attributes — causa sfdisk --part-type ESP
  #      que falha no Debian Trixie. Calamares identifica EFI pelo mountPoint.
  cat > config/includes.chroot/etc/calamares/modules/partition.conf <<'EOF'
---
defaultFileSystemType: ext4
defaultPartitionTableType: gpt
allowManualPartitioning: true
requiredStorage: 15.0
efiSystemPartitionSize: 512M
efiSystemPartitionName: EFI
efiSystemPartitionMountPoint: /boot/efi
partitionLayout:
  - name: "efi"
    size: "512M"
    mountPoint: "/boot/efi"
    filesystem: "fat32"
  - name: "boot"
    size: "1024M"
    mountPoint: "/boot"
    filesystem: "ext4"
  - name: "root"
    size: "20480M"
    mountPoint: "/"
    filesystem: "ext4"
  - name: "swap"
    size: "4096M"
    filesystem: "linuxswap"
  - name: "home"
    size: "100%"
    mountPoint: "/home"
    filesystem: "ext4"
userSwapChoices:
  - none
  - small
  - suspend
  - file
initialSwapChoice: small
EOF

  # ── Calamares: bootloader.conf ────────────────────────────────────────────
  # FIX: installEFIFallback:true → grub-install --removable
  #      funciona em VM e bare metal sem precisar de EFI vars
  cat > config/includes.chroot/etc/calamares/modules/bootloader.conf <<'EOF'
---
efiBootLoader: grub
grubInstall: grub-install
grubMkconfig: grub-mkconfig
grubCfg: /boot/grub/grub.cfg
grubProbe: grub-probe
efiBootLoaderId: OneDevsOS
installEFIFallback: true
EOF

  # ── Calamares: fstab.conf ─────────────────────────────────────────────────
  cat > config/includes.chroot/etc/calamares/modules/fstab.conf <<'EOF'
---
mountOptions:
  - filesystem: default
    options: [ defaults, relatime ]
  - filesystem: ext4
    options: [ defaults, relatime, errors=remount-ro ]
  - filesystem: fat32
    options: [ defaults, umask=0077, shortname=mixed ]
  - filesystem: linuxswap
    options: [ sw ]
efiMountPoint: /boot/efi
efiMountOptions: defaults,umask=0077
ssdExtraMountOptions:
  - filesystem: ext4
    options: noatime,discard
  - filesystem: fat32
    options: noatime
EOF

  # ── Calamares: unpackfs.conf ──────────────────────────────────────────────
  # FIX: path correto — medium/live/ (não rootfs/)
  cat > config/includes.chroot/etc/calamares/modules/unpackfs.conf <<'EOF'
---
unpack:
  - source: /run/live/medium/live/filesystem.squashfs
    sourcefs: squashfs
    destination: ""
EOF

  # ── Calamares: mount.conf ─────────────────────────────────────────────────
  # FIX: removidos /dev e /run com options:bind (bug Calamares 3.3.14)
  cat > config/includes.chroot/etc/calamares/modules/mount.conf <<'EOF'
---
extraMounts:
  - device: proc
    fs: proc
    mountPoint: /proc
  - device: sys
    fs: sysfs
    mountPoint: /sys
extraMountsEfi:
  - device: efivarfs
    fs: efivarfs
    mountPoint: /sys/firmware/efi/efivars
EOF

  # ── Calamares: users.conf ─────────────────────────────────────────────────
  cat > config/includes.chroot/etc/calamares/modules/users.conf <<'EOF'
---
defaultGroups:
- users
- lp
- video
- network
- storage
- wheel
- audio
- sudo
- netdev
- plugdev
autologinGroup: autologin
doAutologin: false
sudoersGroup: sudo
setRootPassword: true
doReusePassword: false
passwordRequirements:
  minLength: 4
  maxLength: -1
allowWeakPasswords: true
allowWeakPasswordsDefault: true
userShell: /bin/bash
EOF

  # ── Calamares: shellprocess remove-live ──────────────────────────────────
  cat > config/includes.chroot/etc/calamares/modules/shellprocess@remove-live.conf <<'EOF'
---
dontChroot: false
timeout: 30
script:
  - "-": /etc/calamares/scripts/remove-live-user.sh
EOF

  cat > config/includes.chroot/etc/calamares/scripts/remove-live-user.sh <<'EOF'
#!/bin/bash
set -e
echo "[OneDevsOS] Limpando ambiente live..."
id -u dev >/dev/null 2>&1 && userdel -r dev 2>/dev/null || true
rm -f /etc/sudoers.d/dev
passwd -l root 2>/dev/null || true
sed -i 's/^autologin-user=.*//' /etc/lightdm/lightdm.conf 2>/dev/null || true
cat > /etc/issue <<'ISSUE'
OneDevsOS 1.0 AlbertEinstein - DevSecOps Edition
\n \l
ISSUE
echo "[OneDevsOS] Sistema pronto."
EOF
  chmod +x config/includes.chroot/etc/calamares/scripts/remove-live-user.sh

  # ── Calamares: branding ───────────────────────────────────────────────────
  cat > config/includes.chroot/usr/share/calamares/branding/onedevs/branding.desc <<'EOF'
---
componentName: onedevs
strings:
  productName: "OneDevsOS"
  shortProductName: "OneDevsOS"
  version: "1.0 AlbertEinstein"
  shortVersion: "1.0"
  versionedName: "OneDevsOS 1.0"
  shortVersionedName: "OneDevsOS 1.0"
  bootloaderEntryName: "OneDevsOS"
  productUrl: "https://onedevsofficial@proton.me"
  supportUrl: "https://onedevsofficial@proton.me"
  knownIssuesUrl: "https://onedevsofficial@proton.me"
  releaseNotesUrl: "https://onedevs@proton.me"
images:
  productLogo: "logo.png"
  productIcon: "logo.png"
slideshow: "show.qml"
style:
  sidebarBackground: "#2c3e50"
  sidebarText: "#ecf0f1"
  sidebarTextSelect: "#3498db"
EOF

  cat > config/includes.chroot/usr/share/calamares/branding/onedevs/show.qml <<'EOF'
import QtQuick 2.0
Rectangle {
  color: "#2c3e50"
  anchors.fill: parent
  Image {
    id: logo
    source: "logo.png"
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -40
    fillMode: Image.PreserveAspectFit
    width: 200; height: 200
  }
  Text {
    anchors.top: logo.bottom
    anchors.topMargin: 20
    anchors.horizontalCenter: parent.horizontalCenter
    text: "OneDevsOS 1.0 AlbertEinstein"
    font.pixelSize: 22; font.bold: true
    color: "#ecf0f1"
  }
  Text {
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 20
    anchors.horizontalCenter: parent.horizontalCenter
    text: "DevSecOps Edition — Instalando..."
    font.pixelSize: 14; color: "#bdc3c7"
  }
}
EOF

  # ── LightDM ───────────────────────────────────────────────────────────────
  cat > config/includes.chroot/etc/lightdm/lightdm-gtk-greeter.conf.d/01_onedevs.conf <<'EOF'
[greeter]
background=/usr/share/backgrounds/onedevs/wallpaper.png
theme-name=Adwaita-dark
icon-theme-name=Papirus-Dark
font-name=Sans 11
xft-antialias=true
xft-dpi=96
xft-hintstyle=hintfull
xft-rgba=rgb
indicators=~host;~spacer;~clock;~spacer;~session;~power
EOF

  # ── Plymouth ──────────────────────────────────────────────────────────────
  cat > config/includes.chroot/usr/share/plymouth/themes/onedevs/onedevs.plymouth <<'EOF'
[Plymouth Theme]
Name=OneDevsOS
Description=Boot theme for OneDevsOS
ModuleName=script
[script]
ImageDir=/usr/share/plymouth/themes/onedevs
ScriptFile=/usr/share/plymouth/themes/onedevs/onedevs.script
EOF

  cat > config/includes.chroot/usr/share/plymouth/themes/onedevs/onedevs.script <<'EOF'
Window.SetBackgroundTopColor(0.16, 0.24, 0.31);
Window.SetBackgroundBottomColor(0.11, 0.16, 0.22);
logo = Image("boot.png");
logo_sprite = Sprite(logo);
logo_sprite.SetPosition(
  Window.GetWidth()/2  - logo.GetWidth()/2,
  Window.GetHeight()/2 - logo.GetHeight()/2,
  10000
);
message_sprite = Sprite();
message_sprite.SetPosition(Window.GetWidth()/2 - 100, Window.GetHeight() - 50, 10000);
fun message_callback(text) {
  my_image = Image.Text(text, 1, 1, 1);
  message_sprite.SetImage(my_image);
}
Plymouth.SetMessageFunction(message_callback);
EOF

  # ── Desktop: wrapper + atalho ─────────────────────────────────────────────
  cat > config/includes.chroot/usr/local/bin/onedevs-install <<'EOF'
#!/bin/bash
exec sudo -E calamares "$@"
EOF
  chmod +x config/includes.chroot/usr/local/bin/onedevs-install

  cat > config/includes.chroot/etc/skel/Desktop/Instalar-OneDevsOS.desktop <<'EOF'
[Desktop Entry]
Name=Instalar OneDevsOS
Name[pt_BR]=Instalar OneDevsOS
Comment=Instalar OneDevsOS no disco
Comment[pt_BR]=Instalar OneDevsOS no disco
Exec=onedevs-install
Icon=system-software-install
Type=Application
Categories=System;Settings;
Terminal=false
StartupNotify=true
EOF
  chmod +x config/includes.chroot/etc/skel/Desktop/Instalar-OneDevsOS.desktop

  # ── Polkit ────────────────────────────────────────────────────────────────
  cat > config/includes.chroot/usr/share/polkit-1/actions/org.onedevs.calamares.policy <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC
 "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <action id="org.freedesktop.policykit.exec">
    <description>Run Calamares installer</description>
    <message>Authentication required</message>
    <defaults>
      <allow_any>yes</allow_any>
      <allow_inactive>yes</allow_inactive>
      <allow_active>yes</allow_active>
    </defaults>
  </action>
</policyconfig>
EOF

  log "Arquivos do live-build gerados/atualizados."
}

run_build() {
  log "Sincronizando relógio..."
  sudo timedatectl set-ntp true 2>/dev/null || true
  sleep 3
  command -v ntpdate >/dev/null 2>&1 && sudo ntpdate -u pool.ntp.org 2>/dev/null || true
  log "Horário: $(date)"
  log "Limpando ambiente anterior..."
  sudo lb clean --purge || true
  log "Executando lb config..."
  lb config \
    --mode debian \
    --distribution "$DIST" \
    --binary-images iso-hybrid \
    --architectures "$ARCH" \
    --debian-installer none \
    --archive-areas "main contrib non-free non-free-firmware" \
    --linux-packages linux-image \
    --linux-flavours amd64 \
    --mirror-bootstrap "http://deb.debian.org/debian" \
    --mirror-chroot "http://deb.debian.org/debian" \
    --mirror-binary "http://deb.debian.org/debian" \
    --mirror-chroot-security "http://security.debian.org/debian-security" \
    --mirror-binary-security "http://security.debian.org/debian-security" \
    --security false \
    --apt-secure false \
    --iso-application "$APPNAME" \
    --iso-volume "$VOLUME" \
    --iso-publisher "$PUBLISHER" \
    --bootappend-live "boot=live components quiet splash persistence persistence-label=ONDEVS username=$USERNAME hostname=$HOSTNAME"
  log "Iniciando build da ISO (pode levar 1-2h)..."
  sudo lb build 2>&1 | tee build-onedevsos.log
  local BUILD_EXIT=${PIPESTATUS[0]:-0}
  if [ "${BUILD_EXIT}" -eq 0 ]; then
    log "Build concluído com sucesso!"
    local ISO_CANDIDATE
    ISO_CANDIDATE=$(ls -1t live-image-*.hybrid.iso 2>/dev/null | head -1 || true)
    if [ -n "${ISO_CANDIDATE}" ]; then
      local CODENAME_LC ISO_NAME
      CODENAME_LC=$(echo "${CODENAME}" | tr '[:upper:]' '[:lower:]')
      ISO_NAME="onedevsos-${CODENAME_LC}-1.0-${ARCH}.iso"
      mv "${ISO_CANDIDATE}" "${ISO_NAME}" || true
      log "ISO: ${ISO_NAME} ($(du -h "${ISO_NAME}" | cut -f1))"
      log "Testar em UEFI:"
      log "  cp /usr/share/OVMF/OVMF_VARS_4M.fd /tmp/OVMF_VARS.fd"
      log "  qemu-img create -f qcow2 disco.img 50G"
      log "  qemu-system-x86_64 -m 4096 -enable-kvm -machine q35,smm=on \\"
      log "    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \\"
      log "    -drive if=pflash,format=raw,file=/tmp/OVMF_VARS.fd \\"
      log "    -cdrom ${ISO_NAME} -drive file=disco.img,format=qcow2,if=virtio -boot d \\"
      log "    -vga virtio -display gtk"
    else
      log "ISO não encontrada; verifique build-onedevsos.log"
    fi
  else
    error "Falha no build. Verifique build-onedevsos.log"
  fi
}

case "${1:-}" in
  generate_only)
    generate_livebuild_files
    log "Modo generate_only completo."
    exit 0
    ;;
  clean)
    log "Limpando ambiente de build..."
    sudo lb clean --purge
    rm -rf config/ .build/ .stage/
    log "Ambiente limpo."
    exit 0
    ;;
esac

log "OneDevsOS Build Script - ${CODENAME} (${DIST}) ${ARCH}"
check_dependencies
generate_livebuild_files

if [ "${ONLINE:-0}" -eq 1 ]; then
  log "Modo ONLINE: live-build baixará pacotes do Debian durante o build"
else
  log "Modo OFFLINE: verificando cache..."
  if [ -f "${ARCHIVES_DIR}/dists/${DIST}/main/binary-${ARCH}/Packages.gz" ]; then
    log "Cache encontrado — build offline possível."
  else
    error "Cache não encontrado. Rode com internet primeiro."
  fi
fi

run_build
log "Processo finalizado."
exit 0
