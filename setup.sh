#!/bin/bash
set -e
echo "=== Creazione webblock .deb ==="
rm -rf /tmp/webblock-build
mkdir -p /tmp/webblock-build/webblock-1.0/DEBIAN
mkdir -p /tmp/webblock-build/webblock-1.0/usr/local/bin
mkdir -p /tmp/webblock-build/webblock-1.0/etc/webblock
mkdir -p /tmp/webblock-build/webblock-1.0/etc/systemd/system

cat > /tmp/webblock-build/webblock-1.0/DEBIAN/control << 'BLOCK'
Package: webblock
Version: 1.0
Section: utils
Priority: optional
Architecture: all
Depends: systemd
Maintainer: giannicbe-create <noreply@github.com>
Description: Parental control basato su /etc/hosts
 Blocca siti web durante la settimana e li sblocca nel weekend.
 Configurazione letta da /dev/shm/lista.txt durante l'installazione.
BLOCK

cat > /tmp/webblock-build/webblock-1.0/DEBIAN/postinst << 'BLOCK'
#!/bin/bash
set -e
CONFIG_DIR="/etc/webblock"
SITES_FILE="$CONFIG_DIR/sites.conf"
SCHEDULE_FILE="$CONFIG_DIR/schedule.conf"
SOURCE="/dev/shm/lista.txt"
mkdir -p "$CONFIG_DIR"
if [ ! -f "$SOURCE" ]; then
    echo "ERRORE: /dev/shm/lista.txt non trovato!"
    exit 1
fi
grep -v '^\s*#' "$SOURCE" | grep -v '^\s*$' | grep -v '=' > "$SITES_FILE" || true
BLOCCO_INIZIO=$(grep '^BLOCCO_INIZIO=' "$SOURCE" | cut -d= -f2 | tr -d '[:space:]')
BLOCCO_FINE=$(grep '^BLOCCO_FINE=' "$SOURCE" | cut -d= -f2 | tr -d '[:space:]')
WEEKEND_LIBERO=$(grep '^WEEKEND_LIBERO=' "$SOURCE" | cut -d= -f2 | tr -d '[:space:]')
BLOCCO_INIZIO="${BLOCCO_INIZIO:-07:00}"
BLOCCO_FINE="${BLOCCO_FINE:-22:00}"
WEEKEND_LIBERO="${WEEKEND_LIBERO:-true}"
cat > "$SCHEDULE_FILE" << CONF
BLOCCO_INIZIO=$BLOCCO_INIZIO
BLOCCO_FINE=$BLOCCO_FINE
WEEKEND_LIBERO=$WEEKEND_LIBERO
CONF
systemctl daemon-reload
systemctl enable webblock.timer
systemctl start webblock.timer
/usr/local/bin/webblock
echo "webblock installato e attivo!"
BLOCK

cat > /tmp/webblock-build/webblock-1.0/DEBIAN/prerm << 'BLOCK'
#!/bin/bash
set -e
sed -i '/# webblock-start/,/# webblock-end/d' /etc/hosts
systemctl stop webblock.timer 2>/dev/null || true
systemctl disable webblock.timer 2>/dev/null || true
systemctl daemon-reload
echo "webblock disattivato e siti sbloccati."
BLOCK

cat > /tmp/webblock-build/webblock-1.0/usr/local/bin/webblock << 'BLOCK'
#!/bin/bash
CONFIG_DIR="/etc/webblock"
SITES_FILE="$CONFIG_DIR/sites.conf"
SCHEDULE_FILE="$CONFIG_DIR/schedule.conf"
HOSTS="/etc/hosts"
MARKER_START="# webblock-start"
MARKER_END="# webblock-end"
if [ ! -f "$SCHEDULE_FILE" ] || [ ! -f "$SITES_FILE" ]; then
    echo "webblock: configurazione mancante."
    exit 1
fi
source "$SCHEDULE_FILE"
DOW=$(date +%u)
ORA_ATTUALE=$(date +%H:%M)
time_to_min() {
    local h=$(echo "$1" | cut -d: -f1 | sed 's/^0*//')
    local m=$(echo "$1" | cut -d: -f2 | sed 's/^0*//')
    h=${h:-0}
    m=${m:-0}
    echo $(( h * 60 + m ))
}
MIN_ATTUALE=$(time_to_min "$ORA_ATTUALE")
MIN_INIZIO=$(time_to_min "$BLOCCO_INIZIO")
MIN_FINE=$(time_to_min "$BLOCCO_FINE")
BLOCCA=false
if [ "$DOW" -ge 1 ] && [ "$DOW" -le 5 ]; then
    [ "$MIN_ATTUALE" -ge "$MIN_INIZIO" ] && [ "$MIN_ATTUALE" -lt "$MIN_FINE" ] && BLOCCA=true
elif [ "$DOW" -ge 6 ] && [ "$WEEKEND_LIBERO" != "true" ]; then
    [ "$MIN_ATTUALE" -ge "$MIN_INIZIO" ] && [ "$MIN_ATTUALE" -lt "$MIN_FINE" ] && BLOCCA=true
fi
sed -i "/$MARKER_START/,/$MARKER_END/d" "$HOSTS"
if [ "$BLOCCA" = "true" ]; then
    { echo "$MARKER_START"; while IFS= read -r s; do [ -n "$s" ] && echo "127.0.0.1  $s"; done < "$SITES_FILE"; echo "$MARKER_END"; } >> "$HOSTS"
    logger "webblock: siti BLOCCATI (${ORA_ATTUALE}, giorno ${DOW})"
else
    logger "webblock: siti SBLOCCATI (${ORA_ATTUALE}, giorno ${DOW})"
fi
BLOCK

cat > /tmp/webblock-build/webblock-1.0/etc/systemd/system/webblock.service << 'BLOCK'
[Unit]
Description=WebBlock - aggiorna blocco siti web
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/webblock
BLOCK

cat > /tmp/webblock-build/webblock-1.0/etc/systemd/system/webblock.timer << 'BLOCK'
[Unit]
Description=WebBlock timer - controlla ogni minuto

[Timer]
OnBootSec=30sec
OnUnitActiveSec=1min
Unit=webblock.service

[Install]
WantedBy=timers.target
BLOCK

chmod 755 /tmp/webblock-build/webblock-1.0/DEBIAN/postinst
chmod 755 /tmp/webblock-build/webblock-1.0/DEBIAN/prerm
chmod 755 /tmp/webblock-build/webblock-1.0/usr/local/bin/webblock

cd /tmp/webblock-build
dpkg-deb --build webblock-1.0

cp /tmp/webblock-build/webblock-1.0.deb ~/Scrivania/webblock-1.0.deb 2>/dev/null || \
cp /tmp/webblock-build/webblock-1.0.deb ~/Desktop/webblock-1.0.deb 2>/dev/null || \
cp /tmp/webblock-build/webblock-1.0.deb ~/webblock-1.0.deb

echo ""
echo "=== FATTO! ==="
echo "Il file webblock-1.0.deb e stato copiato sul Desktop (o nella home)!"
echo "Prima di installarlo, crea /dev/shm/lista.txt con i siti da bloccare."