#!/bin/bash
# Enkel lösenordsgenerator med whiptail-meny

set -Eeuo pipefail

require_whiptail() {
    if ! command -v whiptail >/dev/null 2>&1; then
        echo "whiptail saknas. Installera med:"
        echo "  sudo apt install whiptail"
        exit 1
    fi
}

require_openssl() {
    if ! command -v openssl >/dev/null 2>&1; then
        echo "openssl saknas. Installera med:"
        echo "  sudo apt install openssl"
        exit 1
    fi
}

generate_base64() {
    # Kort, starkt lösenord med base64 (≈ 12 tecken)
    openssl rand -base64 9
}

generate_hex() {
    # Lätt att skriva: 12 hex-tecken
    openssl rand -hex 6
}

generate_words() {
    # Två ord + siffra, lite mer mänskligt
    local dict="/usr/share/dict/words"
    if [[ -r "$dict" ]]; then
        local w1 w2 num
        w1=$(shuf -n1 "$dict")
        w2=$(shuf -n1 "$dict")
        num=$((RANDOM % 100))
        printf "%s-%s-%02d\n" "$w1" "$w2" "$num"
    else
        # fallback om ordlista saknas
        echo "wordlist-missing-$(openssl rand -hex 2)"
    fi
}

generate_alnum() {
    # Endast A–Z, a–z, 0–9
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12
    echo
}

generate_special() {
    # Med specialtecken
    tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom | head -c 14
    echo
}

generate_long() {
    # Längre, superstarkt
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24
    echo
}

show_password_box() {
    local pass="$1"
    # Visa i terminalen också
    echo "======================================"
    echo " Genererat lösenord:"
    echo " $pass"
    echo "======================================"
    echo

    whiptail --title "Genererat lösenord" \
        --msgbox "Ditt lösenord är:\n\n$pass\n\n(Det har också skrivits ut i terminalen.)" \
        12 70
}

main_menu() {
    while true; do
        choice=$(whiptail --title "Lösenordsgenerator" --menu "Välj typ av lösenord:" 20 70 10 \
            "1" "Base64 (kort + mycket säkert)" \
            "2" "Hex (lätt att skriva)" \
            "3" "Ord-baserat (mer minnesbart)" \
            "4" "Alfanumeriskt (A–Z, a–z, 0–9)" \
            "5" "Med specialtecken" \
            "6" "Långt superstarkt" \
            "q" "Avsluta" \
            3>&1 1>&2 2>&3) || exit 0

        local pass=""
        case "$choice" in
            "1") pass=$(generate_base64) ;;
            "2") pass=$(generate_hex) ;;
            "3") pass=$(generate_words) ;;
            "4") pass=$(generate_alnum) ;;
            "5") pass=$(generate_special) ;;
            "6") pass=$(generate_long) ;;
            "q") exit 0 ;;
        esac

        show_password_box "$pass"
    done
}

# --- Start ---
require_whiptail
require_openssl
main_menu

