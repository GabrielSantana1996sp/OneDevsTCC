#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2025 Gabriel Santana
#
# Este arquivo faz parte do projeto OneDevs.
# Licenciado sob Apache License 2.0 (veja LICENSE).
#
# Atenção: este projeto pode incluir softwares de terceiros
# licenciados sob GPL, MIT, BSD e outras licenças.
# Cada componente mantém sua licença original.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
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
TMPWORK="/tmp/onedevs-archives-work"

# URLs raw do GitHub (commit fixo para estabilidade)
COMMIT="38f0fe21e88015f157a1cfccbd06fc67a5e9bb18"
RAW="https://raw.githubusercontent.com/GabrielSantana1996sp/OneDevsTCC/${COMMIT}/IMG"

log()  { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
error(){ log "ERRO: $*"; exit 1; }

# ── Checagem de rede ──────────────────────────────────────────────────────────
ONLINE=0
check_network() {
  if ! ip route show default >/dev/null 2>&1; then ONLINE=0; return 0; fi
  if bash -c "cat < /dev/null > /dev/tcp/8.8.8.8/53" >/dev/null 2>&1; then ONLINE=1; return 0; fi
  if ping -c1 -W3 8.8.8.8 >/dev/null 2>&1; then ONLINE=1; return 0; fi
  ONLINE=0
}
check_network
[ "${ONLINE}" -eq 1 ] && log "Rede detectada: modo ONLINE" || log "Nenhuma rede: modo OFFLINE"

# ── Verificação de dependências ───────────────────────────────────────────────
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

# ── Prepara cache de pacotes ────────────────────────────────────────────────
prepare_full_cache() {
  log "Preparando cache completo de pacotes (Modo Offline Seguro)..."
  
  [ -f "${PACKAGE_LIST}" ] || error "Lista não encontrada: ${PACKAGE_LIST}"
  
  rm -rf "${ARCHIVES_DIR}"
  mkdir -p "${ARCHIVES_DIR}/pool/main/custom"
  mkdir -p "${ARCHIVES_DIR}/dists/${DIST}/main/binary-${ARCH}"
  
  local PACKAGES
  PACKAGES=$(grep -v '^[[:space:]]*#' "${PACKAGE_LIST}" | grep -v '^[[:space:]]*$' | tr '\n' ' ')
  
  if [ -z "${PACKAGES}" ]; then
    log "Lista de pacotes vazia. Pulando cache."
    return 0
  fi

  log "Baixando ${#PACKAGES} pacotes para o cache local..."
  sudo apt-get -q update || true
  sudo apt-get --download-only --fix-missing install -y $PACKAGES 2>&1 | tee /tmp/apt_download.log || true

  log "Copiando pacotes para o diretório de build..."
  find /var/cache/apt/archives -maxdepth 1 -name "*.deb" -exec cp -v -- "{}" "${ARCHIVES_DIR}/pool/main/custom/" \;

  log "Gerando índices locais (Packages.gz e Release)..."
  command -v dpkg-scanpackages >/dev/null 2>&1 || sudo apt-get install -y dpkg-dev
  command -v apt-ftparchive   >/dev/null 2>&1 || sudo apt-get install -y apt-utils
  
  pushd "${ARCHIVES_DIR}" >/dev/null
  
  if dpkg-scanpackages pool /dev/null | gzip -9c > "dists/${DIST}/main/binary-${ARCH}/Packages.gz"; then
    log "Índice Packages.gz gerado com sucesso."
  else
    log "ERRO: Falha ao gerar Packages.gz."
    popd >/dev/null
    return 1
  fi

  if apt-ftparchive release . > Release; then
    log "Arquivo Release gerado com sucesso."
  else
    log "ERRO: Falha ao gerar Release."
    popd >/dev/null
    return 1
  fi
  
  chmod -R a+r .
  popd >/dev/null
  
  local COUNT
  COUNT=$(ls -1 "${ARCHIVES_DIR}/pool/main/custom/"*.deb 2>/dev/null | wc -l)
  log "Cache preparado com ${COUNT} pacotes. Build offline seguro."
  
  if ls ${ARCHIVES_DIR}/pool/main/custom/*linux-image* >/dev/null 2>&1; then
    log " Kernel encontrado no cache."
  else
    log " AVISO: Kernel não encontrado no cache. O build pode falhar se não houver internet."
  fi
}

# ── Gera arquivos do live-build ───────────────────────────────────────────────
generate_livebuild_files() {
  log "Gerando arquivos do live-build..."

  mkdir -p config/{package-lists,hooks/live,apt,archives}
  mkdir -p config/includes.chroot/etc/{calamares/modules,apt/apt.conf.d}
  mkdir -p config/includes.chroot/etc/{lightdm/lightdm-gtk-greeter.conf.d,sysctl.d}
  mkdir -p config/includes.chroot/etc/skel/{Desktop,.config/autostart}
  mkdir -p config/includes.chroot/usr/share/{calamares/branding/onedevs,backgrounds/onedevs}
  mkdir -p config/includes.chroot/usr/share/{plymouth/themes/onedevs,applications,polkit-1/actions}

  # ── APT ────────────────────────────────────────────────────────────────────
  cat > config/apt/apt.conf <<'EOF'
Acquire::Check-Valid-Until "false";
Acquire::Check-Date "false";
APT::Get::AllowUnauthenticated "true";
EOF

  cat > config/apt/preferences <<'EOF'
Package: *
Pin: release o=Debian
Pin-Priority: 500

Package: grub-pc grub-pc-bin
Pin: release *
Pin-Priority: -1
EOF

  cat > config/includes.chroot/etc/apt/apt.conf.d/99onedevs <<'EOF'
Acquire::Check-Valid-Until "false";
Acquire::Check-Date "false";
APT::Get::AllowUnauthenticated "true";
Acquire::Languages "none";
EOF

  # ── Lista de pacotes ──────────────────────────────────────────────────────
  if [ ! -f config/package-lists/onedevs.list.chroot ]; then
    cat > config/package-lists/onedevs.list.chroot <<'EOF'
# Sistema Base
live-boot live-config live-config-systemd parted cryptsetup initramfs-tools

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

# Bootloader (apenas EFI)
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

# Segurança
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

  cat > config/package-lists/exclude.list.chroot <<'EOF'
!grub-pc
!grub-pc-bin
EOF

  # ── Hook 0001: bloqueia grub-pc ───────────────────────────────────────────
  cat > config/hooks/live/0001-block-grub-pc.hook.chroot <<'EOF'
#!/bin/bash
set -e
echo "=== Bloqueando grub-pc no chroot ==="
mkdir -p /etc/apt/preferences.d
cat > /etc/apt/preferences.d/block-grub-pc <<'PREF'
Package: grub-pc grub-pc-bin
Pin: release *
Pin-Priority: -1
PREF
echo "grub-pc bloqueado."
EOF
  chmod +x config/hooks/live/0001-block-grub-pc.hook.chroot

  # ── Hook 9997: baixa assets do GitHub ─────────────────────────────────────
  cat > config/hooks/live/9997-onedevs-assets.hook.chroot <<HOOKEOF
#!/bin/bash
set -e
echo "=== Baixando assets do OneDevsOS do GitHub ==="

COMMIT="${COMMIT}"
RAW="https://raw.githubusercontent.com/GabrielSantana1996sp/OneDevsTCC/\${COMMIT}/IMG"

mkdir -p /usr/share/backgrounds/onedevs
mkdir -p /usr/share/calamares/branding/onedevs
mkdir -p /etc/calamares/branding/onedevs
mkdir -p /usr/share/plymouth/themes/onedevs

dl() {
  local url="\$1" dest="\$2" name="\$3"
  if curl -fsSL --retry 3 --retry-delay 2 "\$url" -o "\$dest"; then
    echo "OK: \$name ($(du -h "\$dest" 2>/dev/null | cut -f1))"
  else
    echo "AVISO: falha ao baixar \$name"
  fi
}

dl "\${RAW}/Wallpapers/Classico.png"     /usr/share/backgrounds/onedevs/Classico.png     "Classico"
dl "\${RAW}/Wallpapers/Cosmos.png"       /usr/share/backgrounds/onedevs/Cosmos.png       "Cosmos"
dl "\${RAW}/Wallpapers/Energia.png"      /usr/share/backgrounds/onedevs/Energia.png      "Energia"
dl "\${RAW}/Wallpapers/RetroTerminal.png" /usr/share/backgrounds/onedevs/RetroTerminal.png "RetroTerminal"
dl "\${RAW}/Wallpapers/universe.png"     /usr/share/backgrounds/onedevs/universe.png     "universe"

cp /usr/share/backgrounds/onedevs/Classico.png /usr/share/backgrounds/onedevs/wallpaper.png

dl "\${RAW}/Calamares/Calamares.png" \
   /usr/share/calamares/branding/onedevs/logo.png "logo Calamares"
cp /usr/share/calamares/branding/onedevs/logo.png \
   /etc/calamares/branding/onedevs/logo.png 2>/dev/null || true

dl "\${RAW}/BootSlash/Boot%20splash%20(Plymouth).png" \
   /usr/share/plymouth/themes/onedevs/boot.png "boot splash"

echo "=== Listagem assets ==="
ls -lh /usr/share/backgrounds/onedevs/         2>/dev/null || true
ls -lh /usr/share/calamares/branding/onedevs/  2>/dev/null || true
ls -lh /usr/share/plymouth/themes/onedevs/     2>/dev/null || true
echo "=== Hook 9997 OK ==="
HOOKEOF
  chmod +x config/hooks/live/9997-onedevs-assets.hook.chroot

  # ── Hook 9998: instala Nix ────────────────────────────────────────────────
  cat > config/hooks/live/9998-onedevs-external.hook.chroot <<'EOF'
#!/bin/bash
set -e
echo "Instalando Nix dentro do chroot..."
sh <(curl --proto '=https' --tlsv1.2 -sSf https://nixos.org/nix/install) --daemon || true
if [ -f /etc/profile.d/nix.sh ]; then
    echo ". /etc/profile.d/nix.sh" >> /home/dev/.bashrc
    chown dev:dev /home/dev/.bashrc
fi
EOF
  chmod +x config/hooks/live/9998-onedevs-external.hook.chroot

  # ── Hook 9999: configura usuário e serviços ───────────────────────────────
  cat > config/hooks/live/9999-onedevs-config.hook.chroot <<'EOF'
#!/bin/bash
set -e
echo "Configurando usuário e serviços..."

if ! id -u dev >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G sudo,netdev,plugdev,audio,video dev
  echo "dev:live" | chpasswd
fi

systemctl enable snapd.socket   || true
systemctl enable snapd.service  || true
systemctl enable dbus.service   || true
systemctl start dbus            || true
systemctl enable lightdm        || true
systemctl enable NetworkManager || true

if [ -f /usr/share/plymouth/themes/onedevs/onedevs.plymouth ]; then
  plymouth-set-default-theme onedevs || true
  update-initramfs -u || true
fi

echo "dev ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/dev
chmod 440 /etc/sudoers.d/dev
chmod +x /etc/skel/Desktop/*.desktop 2>/dev/null || true
EOF
  chmod +x config/hooks/live/9999-onedevs-config.hook.chroot

  # ── Calamares: MODULE PRE_PARTITION (PARA RODAR NA INSTALAÇÃO) ────────────
  cat > config/includes.chroot/etc/calamares/modules/pre_partition.sh <<'SCRIPT'
#!/bin/bash
set -e

echo "=== Módulo Calamares: Pré-Particionamento Personalizado ==="

DISK=""
for d in /dev/sd[a-z] /dev/nvme[0-9]*n[0-9]*; do
  if [ -b "$d" ]; then
    DISK="$d"
    break
  fi
done

if [ -z "$DISK" ]; then
  echo "ERRO: Nenhum disco encontrado para instalação."
  exit 1
fi

echo "Disco alvo: $DISK"

parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary fat32 1MiB 1025MiB
parted -s "$DISK" set 1 boot on
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 1025MiB 21GiB
parted -s "$DISK" mkpart primary ext4 21GiB 26GiB
parted -s "$DISK" mkpart primary linux-swap 26GiB 30GiB
parted -s "$DISK" mkpart primary ext4 30GiB 100%

sleep 2

PASS="onedevs_live"

setup_luks() {
  local PART=$1
  local NAME=$2
  echo "Criptografando $PART..."
  echo "$PASS" | cryptsetup luksFormat --batch-mode --type luks2 --pbkdf argon2id "$PART" -
  echo "$PASS" | cryptsetup open "$PART" luks-$NAME
}

setup_luks "${DISK}3" "root"
setup_luks "${DISK}4" "var"
setup_luks "${DISK}5" "swap"
setup_luks "${DISK}6" "home"

mkfs.vfat -F 32 -n "EFI" "${DISK}1"
mkfs.ext4 -L "root_enc" "/dev/mapper/luks-root"
mkfs.ext4 -L "var_enc" "/dev/mapper/luks-var"
mkfs.ext4 -L "home_enc" "/dev/mapper/luks-home"

RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
SWAP_SIZE_KB=$((RAM_KB * 15 / 100))
MIN_SWAP=524288
MAX_SWAP=8388608

if [ "$SWAP_SIZE_KB" -lt "$MIN_SWAP" ]; then SWAP_SIZE_KB=$MIN_SWAP; elif [ "$SWAP_SIZE_KB" -gt "$MAX_SWAP" ]; then SWAP_SIZE_KB=$MAX_SWAP; fi
SWAP_SIZE_MB=$((SWAP_SIZE_KB / 1024))

mkswap "/dev/mapper/luks-swap"
swapon "/dev/mapper/luks-swap"

CURRENT_SWAP=$(swapon --show --bytes --noheadings | awk '{sum+=$2} END {print sum+0}')
if [ "$CURRENT_SWAP" -lt "$SWAP_SIZE_KB" ]; then
  DIFF=$((SWAP_SIZE_KB - CURRENT_SWAP))
  DIFF_MB=$((DIFF / 1024))
  mkdir -p /mnt/home_temp
  mount "/dev/mapper/luks-home" /mnt/home_temp
  dd if=/dev/zero of=/mnt/home_temp/swapfile bs=1M count=$DIFF_MB status=progress
  chmod 600 /mnt/home_temp/swapfile
  mkswap /mnt/home_temp/swapfile
  swapon /mnt/home_temp/swapfile
  umount /mnt/home_temp
  rmdir /mnt/home_temp
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

echo "=== Pré-Particionamento Concluído ==="
SCRIPT
  chmod +x config/includes.chroot/etc/calamares/modules/pre_partition.sh

  # ── Calamares: Configuração do Script Customizado ─────────────────────────
  cat > config/includes.chroot/etc/calamares/modules/shellprocess@pre_partition.conf <<'EOF'
---
command: "/etc/calamares/modules/pre_partition.sh"
workingDirectory: "/"
environment: []
EOF

  # ── Calamares: grubcfg.conf (Habilitar Crypto no GRUB) ────────────────────
  cat > config/includes.chroot/etc/calamares/modules/grubcfg.conf <<'EOF'
---
defaults:
  GRUB_ENABLE_CRYPTODISK: true
  GRUB_CMDLINE_LINUX_DEFAULT: "quiet splash"
  # Outras configurações padrão do GRUB podem ser adicionadas aqui
EOF

  # ── Calamares: settings.conf (ATUALIZADO) ─────────────────────────────────
  cat > config/includes.chroot/etc/calamares/settings.conf <<'EOF'
---
# SPDX-FileCopyrightText: no
# SPDX-License-Identifier: CC0-1.0
#
# Configuration file for Calamares
#
# This is the top-level configuration file for Calamares.
# It specifies what modules will be used, as well as some
# overall characteristics -- is this a setup program, or
# an installer. More specific configuration is devolved
# to the branding file (for the UI) and the individual
# module configuration files (for functionality).
---
# Modules can be job modules (with different interfaces) and QtWidgets view
# modules. They could all be placed in a number of different paths.
# "modules-search" is a list of strings, each of these can either be a full
# path to a directory or the keyword "local".
#
# "local" means:
#   - modules in $LIBDIR/calamares/modules, with
#   - settings in SHARE/calamares/modules or /etc/calamares/modules.
# In debug-mode (e.g. calamares -d) "local" also adds some paths
# that make sense from inside the build-directory, so that you
# can build-and-run with the latest modules immediately.
#
# Strings other than "local" are taken as paths and interpreted
# relative to wherever Calamares is started. It is therefore **strongly**
# recommended to use only absolute paths here. This is mostly useful
# if your distro has forks of standard Calamares modules, but also
# uses some form of upstream packaging which might overwrite those
# forked modules -- then you can keep modules somewhere outside of
# the "regular" module tree.
#
#
# YAML: list of strings.
modules-search: [ local ]

# Instances section. This section is optional, and it defines custom instances
# for modules of any kind. An instance entry has these keys:
# - *module* name, which matches the module name from the module descriptor
#   (usually the name of the directory under `src/modules/`, but third-
#   party modules may diverge.
# - *id* (optional) an identifier to distinguish this instance from
#   all the others. If none is given, the name of the module is used.
#   Together, the module and id form an instance key (see below).
# - *config* (optional) a filename for the configuration. If none is
#   given, *module*`.conf` is used (e.g. `welcome.conf` for the welcome
#   module)
# - *weight* (optional) In the *exec* phase of the sequence, progress
#   is reported as jobs are completed. The jobs from a single module
#   together contribute the full weight of that module. The overall
#   progress (0 .. 100%) is divided up according to the weight of each
#   module. Give modules that take a lot of time to complete, a larger
#   weight to keep the overall progress moving along steadily. This
#   weight overrides a weight given in the module descriptor. If no weight
#   is given, uses the value from the module descriptor, or 1 if there
#   isn't one there either.
# - *autoProceed* (optional) If true, automatically proceed to the next
#   ViewStep page whenever the "Next" button is enabled. This allows fully
#   automated (unattended) installations. It is disabled (false)
#   by default.
#
# The primary goal of this mechanism is to allow loading multiple instances
# of the same module, with different configuration. If you don't need this,
# the instances section can safely be left empty.
#
# Module name plus instance name makes an instance key, e.g.
# "packagechooserq@licenseq", where "packagechooserq" is the module name (for the packagechooserq
# viewmodule) and "licenseq" is the instance name. In the *sequence*
# section below, use instance-keys to name instances (instead of just
# a module name, for modules which have only a single instance).
#
# Every module implicitly has an instance with the instance name equal
# to its module name, e.g. "welcome@welcome". In the *sequence* section,
# mentioning a module without a full instance key (e.g. "welcome")
# means that implicit module.
#
# An instance may specify its configuration file (e.g. `webview-home.conf`).
# The implicit instances all have configuration files named `<module>.conf`.
# This (implict) way matches the source examples, where the welcome
# module contains an example `welcome.conf`. Specify a *config* for
# any module (also implicit instances) to change which file is used.
#
# For more information on running module instances, run Calamares in debug
# mode and check the Modules page in the Debug information interface.
#
# A module that is often used with instances is shellprocess, which will
# run shell commands specified in the configuration file. By configuring
# more than one instance of the module, multiple shell sessions can be run
# during install.
#
# YAML: list of maps of string:string key-value pairs.
#instances:
#- id:          licenseq
#  module:      packagechooserq
#  config:      licenseq.conf
#- module:      partition
#  autoProceed: true

# Sequence section. This section describes the sequence of modules, both
# viewmodules and jobmodules, as they should appear and/or run.
#
# A jobmodule instance key (or name) can only appear in an exec phase, whereas
# a viewmodule instance key (or name) can appear in both exec and show phases.
# There is no limit to the number of show or exec phases. However, the same
# module instance key should not appear more than once per phase, and
# deployers should take notice that the global storage structure is persistent
# throughout the application lifetime, possibly influencing behavior across
# phases. A show phase defines a sequence of viewmodules (and therefore
# pages). These viewmodules can offer up jobs for the execution queue.
#
# An exec phase displays a progress page (with brandable slideshow). This
# progress page iterates over the modules listed in the *immediately
# preceding* show phase, and enqueues their jobs, as well as any other jobs
# from jobmodules, in the order defined in the current exec phase.
#
# It then executes the job queue and clears it. If a viewmodule offers up a
# job for execution, but the module name (or instance key) isn't listed in the
# immediately following exec phase, this job will not be executed.
#
# YAML: list of lists of strings.
sequence:
- show:
  - welcome
#  - notesqml
#  - packagechooserq@licenseq
  - locale
  - keyboard
  - partition
  - users
#  - tracking
  - summary
- exec:
#  - dummycpp
#  - dummyprocess
#  - dummypython
  - partition
#  - zfs
  - mount
  - luksbootkeyfile          # <--- CRIA A CHAVE DE DESBLOQUEIO
  - initramfscfg             # <--- CONFIGURA O INITRAMFS (DEBIAN)
  - unpackfs
  - machineid
  - locale
  - keyboard
  - localecfg
#  - luksbootkeyfile
#  - luksopenswaphookcfg
#  - dracutlukscfg
  - fstab
#  - plymouthcfg
#  - zfshostid
  - initcpiocfg
  - initcpio
  - users
  - displaymanager
  - networkcfg
  - hwclock
  - services-systemd
#  - dracut
  - initramfs
#  - grubcfg
  - bootloader
  - umount
- show:
  - finished

# A branding component is a directory, either in SHARE/calamares/branding or
# in /etc/calamares/branding (the latter takes precedence). The directory must
# contain a YAML file branding.desc which may reference additional resources
# (such as images) as paths relative to the current directory.
#
# A branding component can also ship a QML slideshow for execution pages,
# along with translation files.
#
# Only the name of the branding component (directory) should be specified
# here, Calamares then takes care of finding it and loading the contents.
#
# YAML: string.
branding: default

# If this is set to true, Calamares will show an "Are you sure?" prompt right
# before each execution phase, i.e. at points of no return. If this is set to
# false, no prompt is shown. Default is false, but Calamares will complain if
# this is not explicitly set.
#
# YAML: boolean.
prompt-install: false

# If this is set to true, Calamares will execute all target environment
# commands in the current environment, without chroot. This setting should
# only be used when setting up Calamares as a post-install configuration tool,
# as opposed to a full operating system installer.
#
# Some official Calamares modules are not expected to function with this
# setting. (e.g. partitioning seems like a bad idea, since that is expected to
# have been done already)
#
# Default is false (for a normal installer), but Calamares will complain if
# this is not explicitly set.
#
# YAML: boolean.
dont-chroot: false

# If this is set to true, Calamares refers to itself as a "setup program"
# rather than an "installer". Defaults to the value of dont-chroot, but
# Calamares will complain if this is not explicitly set.
oem-setup: false

# If this is set to true, the "Cancel" button will be disabled entirely.
# The button is also hidden from view.
#
# This can be useful if when e.g. Calamares is used as a post-install
# configuration tool and you require the user to go through all the
# configuration steps.
#
# Default is false, but Calamares will complain if this is not explicitly set.
#
# YAML: boolean.
disable-cancel: false

# If this is set to true, the "Cancel" button will be disabled once
# you start the 'Installation', meaning there won't be a way to cancel
# the Installation until it has finished or installation has failed.
#
# Default is false, but Calamares will complain if this is not explicitly set.
#
# YAML: boolean.
disable-cancel-during-exec: false

# If this is set to true, the "Next" and "Back" button will be hidden once
# you start the 'Installation'.
#
# Default is false, but Calamares will complain if this is not explicitly set.
#
# YAML: boolean.
hide-back-and-next-during-exec: false

# If this is set to true, then once the end of the sequence has
# been reached, the quit (done) button is clicked automatically
# and Calamares will close. Default is false: the user will see
# that the end of installation has been reached, and that things are ok.
#
#
quit-at-end: false

EOF

  # ── Calamares: partition.conf (APENAS MONTAGEM) ───────────────────────────
  cat > config/includes.chroot/etc/calamares/modules/partition.conf <<'EOF'
---
# SPDX-FileCopyrightText: no
# SPDX-License-Identifier: CC0-1.0
#

# Options for EFI system partition.
#
# - *mountPoint*
#   This setting specifies the mount point of the EFI system partition. Some
#   distributions (Fedora, Debian, Manjaro, etc.) use /boot/efi, others (KaOS,
#   etc.) use just /boot.
#
#   Defaults to "/boot/efi", may be empty (but weird effects ensue)
# - *recommendedSize*
#   This optional setting specifies the size of the EFI system partition.
#   If nothing is specified, the default size of 300MiB will be used.
#   When writing quantities here, M is treated as MiB, and if you really
#   want one-million (10^6) bytes, use MB.
# - *minimumSize*
#   This optional setting specifies the absolute minimum size of the EFI
#   system partition. If nothing is specified, the *recommendedSize*
#   is used instead.
# - *label*
#   This optional setting specifies the name of the EFI system partition (see
#   PARTLABEL; gpt only; requires KPMCore >= 4.2.0).
#   If nothing is specified, the partition name is left unset.
#
# Going below the *recommended* size is allowed, but the user will
# get a warning that it might not work. Going below the *minimum*
# size is not allowed and the user will be told it will not work.
#
# Both quantities must be at least 32MiB, this is enforced by the EFI
# spec. If minimum is not specified, it defaults to the recommended
# size. Distros that allow more user latitude can set the minimum lower.
efi:
    mountPoint:         "/boot/efi"
    recommendedSize:    300MiB
    minimumSize:        32MiB
    label:              "EFI"

# Deprecated alias of efi.mountPoint
# efiSystemPartition:     "/boot/efi"

# Deprecated alias of efi.recommendedSize
# efiSystemPartitionSize:          300MiB

# Deprecated alias of efi.label
# efiSystemPartitionName:     EFI

# In autogenerated partitioning, allow the user to select a swap size?
# If there is exactly one choice, no UI is presented, and the user
# cannot make a choice -- this setting is used. If there is more than
# one choice, a UI is presented.
#
# Legacy settings *neverCreateSwap* and *ensureSuspendToDisk* correspond
# to values of *userSwapChoices* as follows:
#    - *neverCreateSwap* is true, means [none]
#    - *neverCreateSwap* is false, *ensureSuspendToDisk* is false, [small]
#    - *neverCreateSwap* is false, *ensureSuspendToDisk* is true, [suspend]
#
# Autogenerated swap sizes are as follows:
#    - *suspend*: Swap is always at least total memory size,
#      and up to 4GiB RAM follows the rule-of-thumb 2 * memory;
#      from 4GiB to 8 GiB it stays steady at 8GiB, and over 8 GiB memory
#      swap is the size of main memory.
#    - *small*: Follows the rules above, but Swap is at
#      most 8GiB, and no more than 10% of available disk.
# In both cases, a fudge factor (usually 10% extra) is applied so that there
# is some space for administrative overhead (e.g. 8 GiB swap will allocate
# 8.8GiB on disk in the end).
#
# If *file* is enabled here, make sure to have the *fstab* module
# as well (later in the exec phase) so that the swap file is
# actually created.
userSwapChoices:
    - none      # Create no swap, use no swap
    - small     # Up to 4GB
    - suspend   # At least main memory size
    # - reuse     # Re-use existing swap, but don't create any (unsupported right now)
    - file      # To swap file instead of partition

# This optional setting specifies the name of the swap partition (see
# PARTLABEL; gpt only; requires KPMCore >= 4.2.0).
# If nothing is specified, the partition name is left unset.
# swapPartitionName:      swap

# LEGACY SETTINGS (these will generate a warning)
# ensureSuspendToDisk:    true
# neverCreateSwap:        false

# This setting specifies the LUKS generation (i.e LUKS1, LUKS2) used internally by
# cryptsetup when creating an encrypted partition.
#
# This option is set to luks1 by default, as grub doesn't support LUKS2 + Argon2id
# currently. On the other hand grub does support LUKS2 with PBKDF2 and could therefore be
# also set to luks2. Also there are some patches for grub and Argon2.
# See: https://aur.archlinux.org/packages/grub-improved-luks2-git
#
# Choices: luks1, luks2 (in addition, "luks" means "luks1")
#
# The default is luks1
#
luksGeneration: luks1

# This setting determines if encryption should be allowed when using zfs.  This
# setting has no effect unless zfs support is provided.
#
# This setting is to handle the fact that some bootloaders(such as grub) do not
# support zfs encryption.
#
# The default is true
#
# allowZfsEncryption: true

# Correctly draw nested (e.g. logical) partitions as such.
drawNestedPartitions:   false

# Show/hide partition labels on manual partitioning page.
alwaysShowPartitionLabels: true

# Allow manual partitioning.
#
# When set to false, this option hides the "Manual partitioning" button,
# limiting the user's choice to "Erase", "Replace" or "Alongside".
# This can be useful when using a custom partition layout we don't want
# the user to modify.
#
# If nothing is specified, manual partitioning is enabled.
#allowManualPartitioning:   true

# Show not encrypted boot partition warning.
#
# When set to false, this option does not show the
# "Boot partition not encrypted" warning when encrypting the
# root partition but not /boot partition.
#
# If nothing is specified, the warning is shown.
#showNotEncryptedBootMessage:   true

# Initial selection on the Choice page
#
# There are four radio buttons (in principle: erase, replace, alongside, manual),
# and you can pick which of them, if any, is initially selected. For most
# installers, "none" is the right choice: it makes the user pick something specific,
# rather than accidentally being able to click past an important choice (in particular,
# "erase" is a dangerous choice).
#
# The default is "none"
#
initialPartitioningChoice: none
#
# Similarly, some of the installation choices may offer a choice of swap;
# the available choices depend on *userSwapChoices*, above, and this
# setting can be used to pick a specific one.
#
# The default is "none" (no swap) if that is one of the enabled options, otherwise
# one of the items from the options.
initialSwapChoice: none

# armInstall
#
# Leaves 16MB empty at the start of a drive when partitioning
# where usually the u-boot loader goes
#
# armInstall: false

# Default partition table type, used when a "erase" disk is made.
#
# When erasing a disk, a new partition table is created on disk.
# In other cases, e.g. Replace and Alongside, as well as when using
# manual partitioning, this partition table exists already on disk
# and it is left unmodified.
#
# Possible values: gpt, msdos (or other names defined by KPMcore).
# Names are case-sensitive.
#
# If nothing is specified, Calamares defaults to "gpt" if system is
# efi or "msdos" otherwise.
#
# defaultPartitionTableType: msdos

# Specify whether to create a partition table layout suitable for a hybrid
# (BIOS + EFI) bootloader installation. This will prepend both bios-boot and
# EFI system partitions to the partition layout, regardless of whether the
# booted system uses BIOS or EFI firmware. Defaults to false.
#
# createHybridBootloaderLayout: false

# Requirement for partition table type
#
# Restrict the installation on disks that match the type of partition
# tables that are specified.
#
# Possible values: msdos, gpt (or other names defined by KPMcore).
# Names are case-sensitive.
#
# If nothing is specified, Calamares defaults to both "msdos" and "gpt".
#
# requiredPartitionTableType: gpt
# requiredPartitionTableType:
#     - msdos
#     - gpt

# Default filesystem type, used when a "new" partition is made.
#
# When replacing a partition, the new filesystem type will be from the
# defaultFileSystemType value. In other cases, e.g. Erase and Alongside,
# as well as when using manual partitioning and creating a new
# partition, this filesystem type is pre-selected. Note that
# editing a partition in manual-creation mode will not automatically
# change the filesystem type to this default value -- it is not
# creating a new partition.
#
# Suggested values: ext2, ext3, ext4, reiser, xfs, jfs, btrfs
# If nothing is specified, Calamares defaults to "ext4".
#
# Names are case-sensitive and defined by KPMCore.
defaultFileSystemType:  "ext4"

# Selectable filesystem type, used when "erase" is done.
#
# When erasing the disk, the *defaultFileSystemType* is used (see
# above), but it is also possible to give users a choice:
# list suitable filesystems here. A drop-down is provided
# to pick which is the filesystems will be used.
#
# The value *defaultFileSystemType* is added to this list (with a warning)
# if not present; the default pick is the *defaultFileSystemType*.
#
# If not specified at all, uses *defaultFileSystemType* without a
# warning (this matches traditional no-choice-available behavior best).
# availableFileSystemTypes:  ["ext4","f2fs"]

# Per-directory filesystem restrictions.
#
# This optional setting specifies what filesystems the user can and cannot use
# for various directories and mountpoints when using manual partitioning.
#
# If nothing is specified, the only restriction enforced by default is that
# the EFI system partition must use the fat32 filesystem.
#
# Otherwise, the filesystem restrictions are defined as follow:
#
# directoryFilesystemRestrictions:
#     - directory: "any"
#       allowedFilesystemTypes: ["all"]
#     - directory: "/"
#       allowedFilesystemTypes: ["ext4","xfs","btrfs","jfs","f2fs"]
#     - mountpoint: "efi"
#       allowedFilesystemTypes: ["fat32"]
#       onlyWhenMountpoint: true
#
# There can be any number of mountpoints listed, each entry having the
# following attributes:
#   - mountpoint: mountpoint's full path
#                 or
#                 "any" to specify a global whitelist that applies to all
#                 mountpoints
#                 or
#                 "efi" to specify a whitelist specific to the EFI system
#                 partition, wherever that partition is located
#   - allowedFilesystemTypes: the list of all filesystems valid for this
#                             mountpoint. If the list contains exactly one
#                             element, and that element is the special value
#                             "any", all filesystem types recognized by
#                             Calamares will be allowed.
#   - onlyWhenMountpoint: Whether the restriction should apply only when the
#                         specified directory is a mountpoint. When set to
#                         true, Calamares will only enforce the listed
#                         restrictions when the user makes a separate partition
#                         for this directory and assigns the mountpoint
#                         accordingly. When set to false, Calamares will
#                         ensure this directory uses the specified filesystem
#                         even if the directory is part of a filesystem on a
#                         different mountpoint. Defaults to false.

# The ClearMounts job unmounts / unmaps things before partitioning.
# Some special entries under /dev/mapper are excepted from this process.
# The example lists the three hard-coded exceptions which always apply
# (they don't need to be listed here). Add other names or wildcards (with
# a trailing '*') to this list if the live-ISO has additional mounts.
essentialMounts: [ "live-*", "control", "ventoy" ]

# Show/hide LUKS related functionality in automated partitioning modes.
# Disable this if you choose not to deploy early unlocking support in GRUB2
# and/or your distribution's initramfs solution.
#
# BIG FAT WARNING:
#
# This option is unsupported, as it cuts out a crucial security feature.
# Disabling LUKS and shipping Calamares without a correctly configured GRUB2
# and initramfs is considered suboptimal use of the Calamares software. The
# Calamares team will not provide user support for any potential issue that
# may arise as a consequence of setting this option to false.
# It is strongly recommended that system integrators put in the work to support
# LUKS unlocking support in GRUB2 and initramfs/dracut/mkinitcpio/etc.
# For more information on setting up GRUB2 for Calamares with LUKS, see
# the Calamares website at https://calamares.io/docs/partitions/#luks .
#
# If nothing is specified, LUKS is enabled in automated modes.
#enableLuksAutomatedPartitioning:    true

# When enableLuksAutomatedPartitioning is true, this option will pre-check
# encryption checkbox. This option is only usefull to help people to not forget
# to cypher their disk when installing in enterprise (for example).
#preCheckEncryption:    false

# LVM support
#
# There is only one sub-key available, *enable* (defaults to true)
# which can be used to show (default) or hide the LVM buttons in the partitioning module.
lvm:
    enable: true

# Partition layout.
#
# This optional setting specifies a custom partition layout.
#
# If nothing is specified, the default partition layout is a single partition
# for root that uses 100% of the space and uses the filesystem defined by
# defaultFileSystemType.
#
# Note: the EFI system partition is prepended automatically to the layout if
# needed; the swap partition is appended to the layout if enabled (selections
# "small" or "suspend" in *userSwapChoices*).
#
# Otherwise, the partition layout is defined as follow:
#
# partitionLayout:
#     - name: "rootfs"
#       type: "4f68bce3-e8cd-4db1-96e7-fbcaf984b709"
#       filesystem: "ext4"
#       noEncrypt: false
#       mountPoint: "/"
#       size: 20%
#       minSize: 500M
#       maxSize: 10G
#       attributes: 0xffff000000000003
#     - name: "home"
#       type: "933ac7e1-2eb4-4f13-b844-0e14e2aef915"
#       filesystem: "ext4"
#       noEncrypt: false
#       mountPoint: "/home"
#       size: 3G
#       minSize: 1.5G
#       features:
#         64bit: false
#         casefold: true
#     - name: "data"
#       filesystem: "fat32"
#       mountPoint: "/data"
#       features:
#         sector-size: 4096
#         sectors-per-cluster: 128
#       size: 100%
#
# There can be any number of partitions, each entry having the following attributes:
#   - name: filesystem label
#           and
#           partition name (gpt only; since KPMCore 4.2.0)
#   - uuid: partition uuid (optional parameter; gpt only; requires KPMCore >= 4.2.0)
#   - type: partition type (optional parameter; gpt only; requires KPMCore >= 4.2.0)
#   - attributes: partition attributes (optional parameter; gpt only; requires KPMCore >= 4.2.0)
#   - filesystem: filesystem type (optional parameter)
#       - if not set at all, treat as "unformatted"
#       - if "unformatted", no filesystem will be created
#       - if "unknown" (or an unknown FS name, like "elephant") then the
#         default filesystem type, or the user's choice, will be applied instead
#         of "unknown" (e.g. the user might pick ext4, or xfs).
#   - noEncrypt: whether this partition is exempt from encryption if enabled (optional parameter; default is false)
#   - mountPoint: partition mount point (optional parameter; not mounted if unset)
#   - size: partition size in bytes (append 'K', 'M' or 'G' for KiB, MiB or GiB)
#           or
#           % of the available drive space if a '%' is appended to the value
#   - minSize: minimum partition size (optional parameter)
#   - maxSize: maximum partition size (optional parameter)
#   - features: filesystem features (optional parameter; requires KPMCore >= 4.2.0)
#       name: boolean or integer or string

# Checking for available storage
#
# This overlaps with the setting of the same name in the welcome module's
# requirements section. If nothing is set by the welcome module, this
# value is used instead. It is still a problem if there is no required
# size set at all, and the replace and resize options will not be offered
# if no required size is set.
#
# The value is in Gibibytes (GiB).
#
# BIG FAT WARNING: except for OEM-phase-0 use, you should be using
#                  the welcome module, **and** configure this value in
#                  `welcome.conf`, not here.
# requiredStorage: 3.5

EOF

  # ── Calamares: UNPACKFS CONFIG ────────────────────────────────────────────
  cat > config/includes.chroot/etc/calamares/modules/unpackfs.conf <<'EOF'
---
unpackfs:
  - source: "/live/image/live-root.squashfs"
    target: "/"
    filesystem: "squashfs"
    options: []
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

  # ── Calamares: branding.desc ──────────────────────────────────────────────
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

  # ── Calamares: slideshow ──────────────────────────────────────────────────
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

  # ── LightDM: wallpaper ────────────────────────────────────────────────────
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

  # ── Plymouth: tema ────────────────────────────────────────────────────────
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

  # ── Desktop: atalho do instalador ─────────────────────────────────────────
  cat > config/includes.chroot/etc/skel/Desktop/Instalar-OneDevsOS.desktop <<'EOF'
[Desktop Entry]
Name=Instalar OneDevsOS
Name[pt_BR]=Instalar OneDevsOS
Comment=Instalar OneDevsOS no disco
Comment[pt_BR]=Instalar OneDevsOS no disco
Exec=sudo -E calamares
Icon=system-software-install
Type=Application
Categories=System;Settings;
Terminal=false
StartupNotify=true
EOF
  chmod +x config/includes.chroot/etc/skel/Desktop/Instalar-OneDevsOS.desktop

  # ── Polkit: Calamares sem senha ───────────────────────────────────────────
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

# ── Build ─────────────────────────────────────────────────────────────────────
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
    --bootappend-live "boot=live components quiet splash persistence persistence-label=ONDEVS username=$USERNAME hostname=$HOSTNAME" \
    --archive-areas "main contrib non-free non-free-firmware"

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
      log "Testar: qemu-system-x86_64 -m 4096 -cdrom ${ISO_NAME} -boot d -enable-kvm"
    else
      log "ISO não encontrada; verifique build-onedevsos.log"
    fi
  else
    error "Falha no build. Verifique build-onedevsos.log"
  fi
}

# ── CLI ───────────────────────────────────────────────────────────────────────
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

# ── Main ──────────────────────────────────────────────────────────────────────
log "OneDevsOS Build Script - ${CODENAME} (${DIST}) ${ARCH}"
check_dependencies
generate_livebuild_files

if [ "${ONLINE:-0}" -eq 1 ] || [ -n "${CI:-}" ]; then
  log "Modo ONLINE detectado. Preparando cache completo..."
  prepare_full_cache
  log "Cache pronto. Iniciando build em modo offline seguro."
else
  log "Modo OFFLINE: verificando cache..."
  if [ -f "${ARCHIVES_DIR}/dists/${DIST}/main/binary-${ARCH}/Packages.gz" ]; then
    log "Cache encontrado — build offline possível."
  else
    error "Cache não encontrado. Rode com internet primeiro para gerar o cache."
  fi
fi

run_build
log "Processo finalizado."
exit 0
