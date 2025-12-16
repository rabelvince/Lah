#!/bin/bash

LOGFILE="/var/log/pro_install.log"

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
NC="\033[0m"

set +e
START_TIME=$(date +%s)

echo "===== Script indult: $(date) =====" >> "$LOGFILE"

trap 'echo -e "${RED}Hiba történt a script futása közben!${NC}"; echo "HIBA $(date)" >> "$LOGFILE"' ERR

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Root jogosultság szükséges!${NC}"
    exit 1
fi

log() {
    echo "$(date '+%F %T') - $1" >> "$LOGFILE"
}

ask_yes_no() {
    while true; do
        read -rp "$1 (i/n): " yn
        case $yn in
            [iI]*) return 0 ;;
            [nN]*) return 1 ;;
            *) echo "Csak i vagy n válasz megengedett!" ;;
        esac
    done
}

declare -A RESULTS

set_result() {
    RESULTS["$1"]="$2"
}

check_service() {
    systemctl is-active --quiet "$1"
    if [[ $? -eq 0 ]]; then
        set_result "$2" "SIKERES"
    else
        set_result "$2" "HIBA"
    fi
}

install_apache() {
    echo -e "${GREEN}Apache telepítése...${NC}"
    log "Apache telepítés"
    apt install -y apache2 libapache2-mod-php >> "$LOGFILE" 2>&1
    systemctl enable apache2
    systemctl start apache2
}

install_php() {
    echo -e "${GREEN}PHP telepítése...${NC}"
    log "PHP telepítés"
    apt install -y php php-mbstring php-zip php-gd php-json php-curl php-mysql >> "$LOGFILE" 2>&1
}

install_ssh() {
    echo -e "${GREEN}SSH telepítése...${NC}"
    log "SSH telepítés"
    apt install -y openssh-server >> "$LOGFILE" 2>&1
    systemctl enable ssh
    systemctl start ssh
}

install_mosquitto() {
    echo -e "${GREEN}Mosquitto telepítése...${NC}"
    log "Mosquitto telepítés"
    apt install -y mosquitto mosquitto-clients >> "$LOGFILE" 2>&1
    systemctl enable mosquitto
    systemctl start mosquitto
}

install_mariadb() {
    echo -e "${GREEN}MariaDB telepítése...${NC}"
    log "MariaDB telepítés"
    apt install -y mariadb-server >> "$LOGFILE" 2>&1
    systemctl enable mariadb
    systemctl start mariadb

    echo "Adatbázis beállítása:"
    read -rp "Felhasználónév: " DB_USER
    read -rsp "Jelszó: " DB_PASS
    echo
    read -rp "Adatbázis neve: " DB_NAME

    mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
    mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
}

install_node_red() {
    echo -e "${GREEN}Node-RED telepítése...${NC}"
    log "Node-RED telepítés"

    apt install -y curl >> "$LOGFILE" 2>&1

    curl -fsSL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered | bash

    systemctl enable nodered.service
    systemctl start nodered.service
}

install_phpmyadmin() {
    echo -e "${GREEN}phpMyAdmin telepítése...${NC}"
    log "phpMyAdmin telepítés"
    apt install -y phpmyadmin >> "$LOGFILE" 2>&1
}

# 🎧 Zene letöltése és lejátszása (csak ha minden jó)
download_and_play_music() {
    MUSIC_URL="https://www.youtube.com/watch?v=M9aq3hzRYP0"
    MUSIC_FILE="/tmp/install_music.mp3"

    echo -e "${YELLOW}Zene letöltése és lejátszása...${NC}"
    log "Zene letöltése"

    apt install -y yt-dlp mpg123 >> "$LOGFILE" 2>&1

    yt-dlp -x --audio-format mp3 --audio-quality 0 \
        -o "$MUSIC_FILE" "$MUSIC_URL" >> "$LOGFILE" 2>&1

    if [[ -f "$MUSIC_FILE" ]]; then
        echo -e "${GREEN}🎶 Zene lejátszása...${NC}"
        mpg123 "$MUSIC_FILE"
    else
        echo -e "${RED}Zene letöltése sikertelen!${NC}"
        log "Zene hiba"
    fi
}

clear
echo "======================================"
echo "        DEBIAN TELEPÍTŐ MENÜ"
echo "======================================"
echo "1) Node-RED"
echo "2) Apache + PHP"
echo "3) Mosquitto MQTT"
echo "4) SSH"
echo "5) phpMyAdmin"
echo "0) Kilépés"
echo "======================================"

read -rp "Választás: " choice

case $choice in
    1)
        ask_yes_no "Apache + PHP szükséges lehet. Telepíted?" && install_apache && install_php
        ask_yes_no "Mosquitto szükséges lehet. Telepíted?" && install_mosquitto
        ask_yes_no "SSH szükséges lehet. Telepíted?" && install_ssh
        install_node_red
        ;;
    2)
        install_apache
        install_php
        ask_yes_no "MariaDB is kell?" && install_mariadb
        ;;
    3)
        install_mosquitto
        ;;
    4)
        install_ssh
        ;;
    5)
        ask_yes_no "Apache + PHP szükséges. Telepíted?" && install_apache && install_php
        ask_yes_no "MariaDB szükséges. Telepíted?" && install_mariadb
        install_phpmyadmin
        ;;
    0)
        exit 0
        ;;
    *)
        echo -e "${RED}Érvénytelen választás!${NC}"
        exit 1
        ;;
esac

# ===============================
# Szolgáltatások ellenőrzése
# ===============================
check_service apache2 "Apache2"
check_service ssh "SSH"
check_service mosquitto "Mosquitto"
check_service nodered.service "Node-RED"
check_service mariadb "MariaDB"

# ===============================
# 🟢 Csak ha minden sikeres
# ===============================
ALL_OK=true
for key in "${!RESULTS[@]}"; do
    if [[ "${RESULTS[$key]}" != "SIKERES" ]]; then
        ALL_OK=false
        break
    fi
done

if $ALL_OK; then
    download_and_play_music
else
    echo -e "${RED}Nem minden szolgáltatás fut sikeresen => zene NEM szól!${NC}"
    log "Zene nem játszódott le (hiba)"
fi

clear
echo "======================================"
echo "       TELEPÍTÉSI EREDMÉNYEK"
echo "======================================"

for key in "${!RESULTS[@]}"; do
    echo "$key : ${RESULTS[$key]}"
done

END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))

echo
echo -e "${GREEN}Script futási ideje: ${RUNTIME} másodperc${NC}"
echo
uname -a
uptime
echo
echo -e "${YELLOW}Megjegyzés:${NC} Nyitott szolgáltatások esetén tűzfal használata ajánlott."

log "Script sikeresen lefutott"

echo -e "${BLUE}
██╗   ██╗███████╗ █████╗ ████████╗
╚██╗ ██╔╝██╔════╝██╔══██╗╚══██╔══╝
 ╚████╔╝ █████╗  ███████║   ██║   
  ╚██╔╝  ██╔══╝  ██╔══██║   ██║   
   ██║   ███████╗██║  ██║   ██║   
   ╚═╝   ╚══════╝╚═╝  ╚═╝   ╚═╝   
${NC}"
