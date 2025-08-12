#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================
#  Docker Installation für Ubuntu 24.x (noble)
#  - Fügt Docker APT-Repo inkl. GPG-Key hinzu
#  - Installiert docker-ce, docker-ce-cli, containerd.io,
#    docker-buildx-plugin, docker-compose-plugin
#  - Aktiviert & startet den Dienst
#  - Fügt den aktiven Benutzer der "docker"-Gruppe hinzu
#  - Idempotent und mit klaren Ausgaben
# =============================================================

# ---------- Hilfsfunktionen ----------
info()  { echo -e "\e[34m[INFO]\e[0m  $*"; }
success(){ echo -e "\e[32m[OK]\e[0m    $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*" 1>&2; }
trap 'error "Ein unerwarteter Fehler ist aufgetreten. Abbruch."' ERR

# ---------- Root-/sudo-Check ----------
if [[ $EUID -ne 0 ]]; then
  error "Bitte mit root-Rechten ausführen (z. B. via sudo)."
  exit 1
fi

# ---------- OS-Check ----------
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  error "/etc/os-release nicht gefunden. Kann Distribution nicht ermitteln."
  exit 1
fi

if [[ "${ID:-}" != "ubuntu" ]]; then
  error "Dieses Skript ist für Ubuntu 24.x. Gefunden: ${ID:-unbekannt}"
  exit 1
fi

# Ubuntu 24.x heißt noble. Wir prüfen grob die Hauptversion
UBUNTU_MAJOR=${VERSION_ID%%.*}
if [[ -z "${UBUNTU_MAJOR}" || "${UBUNTU_MAJOR}" -lt 24 ]]; then
  error "Gefundene Ubuntu-Version: ${VERSION_ID:-unbekannt}. Benötigt wird 24.x oder neuer."
  exit 1
fi

CODENAME=${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}
if [[ -z "${CODENAME}" ]]; then
  # Fallback, falls Variablen fehlen
  if command -v lsb_release >/dev/null 2>&1; then
    CODENAME=$(lsb_release -cs)
  else
    error "Konnte den Ubuntu-Codename nicht ermitteln. Bitte lsb-release installieren oder UBUNTU_CODENAME setzen."
    exit 1
  fi
fi

info "Distribution: Ubuntu ${VERSION_ID:-?} (${CODENAME})"

# ---------- APT vorbereiten ----------
export DEBIAN_FRONTEND=noninteractive

info "Paketquellen aktualisieren & Voraussetzungen installieren …"
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl

# Optional, aber oft hilfreich
apt-get install -y --no-install-recommends gnupg gnupg2 lsb-release nano apt-transport-https

# ---------- Docker GPG-Key einrichten ----------
info "Docker GPG-Key und Repository einrichten …"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# ---------- Docker APT-Repo hinzufügen ----------
ARCH=$(dpkg --print-architecture)
cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable
EOF

info "APT-Index aktualisieren …"
apt-get update -y

# ---------- Docker installieren ----------
PACKAGES=(
  docker-ce
  docker-ce-cli
  containerd.io
  docker-buildx-plugin
  docker-compose-plugin
)

info "Installiere Pakete: ${PACKAGES[*]} …"
apt-get install -y "${PACKAGES[@]}"

# ---------- Dienst aktivieren & starten ----------
info "Dienst docker aktivieren & starten …"
systemctl enable --now docker

# ---------- Benutzer der docker-Gruppe hinzufügen ----------
# Ermittelt den Benutzer, der dem 'docker'-Team hinzugefügt werden soll.
# Falls das Skript mit sudo läuft, wird der ursprüngliche Benutzer (SUDO_USER) genommen, sonst $USER.
TARGET_USER=${SUDO_USER:-${USER}}
# Prüft, ob der Benutzer existiert (id -u liefert UID)
if id -u "$TARGET_USER" >/dev/null 2>&1; then
  # Prüft, ob es die Gruppe 'docker' gibt (getent group)
  if getent group docker >/dev/null 2>&1; then
    # Prüft, ob der Benutzer schon Mitglied der Gruppe 'docker' ist
    if id -nG "$TARGET_USER" | grep -qw docker; then
      info "Benutzer $TARGET_USER ist bereits in der Gruppe 'docker'."
    else
      # Fügt den Benutzer zur docker-Gruppe hinzu (usermod -aG)
      usermod -aG docker "$TARGET_USER"
      success "Benutzer $TARGET_USER zur Gruppe 'docker' hinzugefügt. (Neu anmelden, damit es aktiv wird.)"
    fi
  else
    warn "Gruppe 'docker' existiert nicht (unerwartet). Wurde Docker korrekt installiert?"
  fi
else
  warn "Konnte Zielbenutzer nicht ermitteln. Überspringe Gruppenanpassung."
fi
