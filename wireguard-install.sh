#!/bin/bash

# Secure WireGuard server installer
# https://github.com/W01v3n/wireguard-install

RED='\033[0;31m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

function isRoot() {
    if [ "${EUID}" -ne 0 ]; then
        echo "You need to run this script as root"
        exit 1
    fi
}

function checkVirt() {
    if [ "$(systemd-detect-virt)" == "openvz" ]; then
        echo "OpenVZ is not supported"
        exit 1
    fi

    if [ "$(systemd-detect-virt)" == "lxc" ]; then
        echo "LXC is not supported (yet)."
        echo "WireGuard can technically run in an LXC container,"
        echo "but the kernel module has to be installed on the host,"
        echo "the container has to be run with some specific parameters"
        echo "and only the tools need to be installed in the container."
        exit 1
    fi
}

function checkOS() {
    source /etc/os-release
    OS="${ID}"
    if [[ ${OS} == "debian" || ${OS} == "raspbian" ]]; then
        if [[ ${VERSION_ID} -lt 10 ]]; then
            echo "Your version of Debian (${VERSION_ID}) is not supported. Please use Debian 10 Buster or later"
            exit 1
        fi
        OS=debian # overwrite if raspbian
    elif [[ ${OS} == "ubuntu" ]]; then
        RELEASE_YEAR=$(echo "${VERSION_ID}" | cut -d'.' -f1)
        if [[ ${RELEASE_YEAR} -lt 18 ]]; then
            echo "Your version of Ubuntu (${VERSION_ID}) is not supported. Please use Ubuntu 18.04 or later"
            exit 1
        fi
    elif [[ ${OS} == "fedora" ]]; then
        if [[ ${VERSION_ID} -lt 32 ]]; then
            echo "Your version of Fedora (${VERSION_ID}) is not supported. Please use Fedora 32 or later"
            exit 1
        fi
    elif [[ ${OS} == 'centos' ]] || [[ ${OS} == 'almalinux' ]] || [[ ${OS} == 'rocky' ]]; then
        if [[ ${VERSION_ID} == 7* ]]; then
            echo "Your version of CentOS (${VERSION_ID}) is not supported. Please use CentOS 8 or later"
            exit 1
        fi
    elif [[ -e /etc/oracle-release ]]; then
        source /etc/os-release
        OS=oracle
    elif [[ -e /etc/arch-release ]]; then
        OS=arch
    else
        echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, AlmaLinux, Oracle or Arch Linux system"
        exit 1
    fi
}

function getHomeDirForClient() {
    local CLIENT_NAME=$1

    if [ -z "${CLIENT_NAME}" ]; then
        echo "Error: getHomeDirForClient() requires a client name as argument"
        exit 1
    fi

    echo "/etc/wireguard/clients"
}

function initialCheck() {
    isRoot
    checkVirt
    checkOS
}

function autoInstall() {
    # Detect public IPv4 or IPv6 address
    SERVER_PUB_IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | awk '{print $1}' | head -1)
    if [[ -z ${SERVER_PUB_IP} ]]; then
        SERVER_PUB_IP=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)
    fi
    SERVER_NIC="$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)"
    SERVER_PUB_NIC="${SERVER_NIC}"
    SERVER_WG_NIC="wg0"
    SERVER_WG_IPV4="10.66.66.1"
    SERVER_WG_IPV6="fd42:42:42::1"
    RANDOM_PORT=$(shuf -i49152-65535 -n1)
    SERVER_PORT="${RANDOM_PORT}"
    CLIENT_DNS_1="1.1.1.1"
    CLIENT_DNS_2="1.0.0.1"
    ALLOWED_IPS="0.0.0.0/0,::/0"

    installWireGuard
}

function installWireGuard() {
    # Install WireGuard tools and module
    if [[ ${OS} == 'ubuntu' ]] || [[ ${OS} == 'debian' && ${VERSION_ID} -gt 10 ]]; then
        apt-get update
        apt-get install -y wireguard iptables resolvconf qrencode
    elif [[ ${OS} == 'debian' ]]; then
        if ! grep -rqs "^deb .* buster-backports" /etc/apt/; then
            echo "deb http://deb.debian.org/debian buster-backports main" >/etc/apt/sources.list.d/backports.list
            apt-get update
        fi
        apt update
        apt-get install -y iptables resolvconf qrencode
        apt-get install -y -t buster-backports wireguard
    elif [[ ${OS} == 'fedora' ]]; then
        if [[ ${VERSION_ID} -lt 32 ]]; then
            dnf install -y dnf-plugins-core
            dnf copr enable -y jdoss/wireguard
            dnf install -y wireguard-dkms
        fi
        dnf install -y wireguard-tools iptables qrencode
    elif [[ ${OS} == 'centos' ]] || [[ ${OS} == 'almalinux' ]] || [[ ${OS} == 'rocky' ]]; then
        if [[ ${VERSION_ID} == 8* ]]; then
            yum install -y epel-release elrepo-release
            yum install -y kmod-wireguard
            yum install -y qrencode # not available on release 9
        fi
        yum install -y wireguard-tools iptables
    elif [[ ${OS} == 'oracle' ]]; then
        dnf install -y oraclelinux-developer-release-el8
        dnf config-manager --disable -y ol8_developer
        dnf config-manager --enable -y ol8_developer_UEKR6
        dnf config-manager --save -y --setopt=ol8_developer_UEKR6.includepkgs='wireguard-tools*'
        dnf install -y wireguard-tools qrencode iptables
    elif [[ ${OS} == 'arch' ]]; then
        pacman -S --needed --noconfirm wireguard-tools qrencode
    fi

    # Make sure the directory exists
    mkdir -p /etc/wireguard/clients >/dev/null 2>&1

    chmod 600 -R /etc/wireguard/

    SERVER_PRIV_KEY=$(wg genkey)
    SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | wg pubkey)

    # Save WireGuard settings
    echo "SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=${SERVER_WG_NIC}
SERVER_WG_IPV4=${SERVER_WG_IPV4}
SERVER_WG_IPV6=${SERVER_WG_IPV6}
SERVER_PORT=${SERVER_PORT}
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}
ALLOWED_IPS=${ALLOWED_IPS}" >/etc/wireguard/params

    # Add server interface
echo "[Interface]
Address = ${SERVER_WG_IPV4}/24,${SERVER_WG_IPV6}/64
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}
PostUp = iptables -A FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; iptables -A FORWARD -o ${SERVER_WG_NIC} -j ACCEPT; iptables -t nat -A POSTROUTING -s ${SERVER_WG_IPV4}/24 -o ${SERVER_PUB_NIC} -j MASQUERADE; ip6tables -A FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; ip6tables -A FORWARD -o ${SERVER_WG_NIC} -j ACCEPT; ip6tables -t nat -A POSTROUTING -s ${SERVER_WG_IPV6}/64 -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; iptables -D FORWARD -o ${SERVER_WG_NIC} -j ACCEPT; iptables -t nat -D POSTROUTING -s ${SERVER_WG_IPV4}/24 -o ${SERVER_PUB_NIC} -j MASQUERADE; ip6tables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; ip6tables -D FORWARD -o ${SERVER_WG_NIC} -j ACCEPT; ip6tables -t nat -D POSTROUTING -s ${SERVER_WG_IPV6}/64 -o ${SERVER_PUB_NIC} -j MASQUERADE" >"/etc/wireguard/${SERVER_WG_NIC}.conf"

    # Enable routing on the server
    echo "net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1" > /etc/sysctl.d/wg.conf

    sysctl --system

    systemctl start "wg-quick@${SERVER_WG_NIC}"
    systemctl enable "wg-quick@${SERVER_WG_NIC}"

    newClient
    echo -e "${GREEN}If you want to add more clients, you simply need to run this script another time!${NC}"

    # Check if WireGuard is running
    systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}"
    WG_RUNNING=$?

    # WireGuard might not work if we updated the kernel. Tell the user to reboot
    if [[ ${WG_RUNNING} -ne 0 ]]; then
        echo -e "\n${RED}WARNING: WireGuard does not seem to be running.${NC}"
        echo -e "${ORANGE}You can check if WireGuard is running with: systemctl status wg-quick@${SERVER_WG_NIC}${NC}"
        echo -e "${ORANGE}If you get something like \"Cannot find device ${SERVER_WG_NIC}\", please reboot!${NC}"
    else # WireGuard is running
        echo -e "\n${GREEN}WireGuard is running.${NC}"
        echo -e "${GREEN}You can check the status of WireGuard with: systemctl status wg-quick@${SERVER_WG_NIC}\n\n${NC}"
        echo -e "${ORANGE}If you don't have internet connectivity from your client, try to reboot the server.${NC}"
    fi
}

function newClient() {
    # If SERVER_PUB_IP is IPv6, add brackets if missing
    if [[ ${SERVER_PUB_IP} =~ .*:.* ]]; then
        if [[ ${SERVER_PUB_IP} != *"["* ]] || [[ ${SERVER_PUB_IP} != *"]"* ]]; then
            SERVER_PUB_IP="[${SERVER_PUB_IP}]"
        fi
    fi
    ENDPOINT="${SERVER_PUB_IP}:${SERVER_PORT}"

    # Auto generate client name based on hostname
    HOSTNAME=$(hostname | tr '[:upper:]' '[:lower:]')
    NUMBER_OF_CLIENTS=$(grep -c -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf")
    CLIENT_NAME="${HOSTNAME}-wg0-client-user$((NUMBER_OF_CLIENTS + 1))"

    for DOT_IP in {2..254}; do
        DOT_EXISTS=$(grep -c "${SERVER_WG_IPV4::-1}${DOT_IP}" "/etc/wireguard/${SERVER_WG_NIC}.conf")
        if [[ ${DOT_EXISTS} == '0' ]]; then
            break
        fi
    done

    if [[ ${DOT_EXISTS} == '1' ]]; then
        echo ""
        echo "The subnet configured supports only 253 clients."
        exit 1
    fi

    BASE_IP=$(echo "$SERVER_WG_IPV4" | awk -F '.' '{ print $1"."$2"."$3 }')
    CLIENT_WG_IPV4="${BASE_IP}.${DOT_IP}"

    BASE_IP=$(echo "$SERVER_WG_IPV6" | awk -F '::' '{ print $1 }')
    CLIENT_WG_IPV6="${BASE_IP}::${DOT_IP}"

    # Generate key pair for the client
    CLIENT_PRIV_KEY=$(wg genkey)
    CLIENT_PUB_KEY=$(echo "${CLIENT_PRIV_KEY}" | wg pubkey)
    CLIENT_PRE_SHARED_KEY=$(wg genpsk)

    HOME_DIR=$(getHomeDirForClient "${CLIENT_NAME}")

    # Create client file and add the server as a peer
    echo "[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_WG_IPV4}/32,${CLIENT_WG_IPV6}/128
DNS = ${CLIENT_DNS_1},${CLIENT_DNS_2}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
Endpoint = ${ENDPOINT}
AllowedIPs = ${ALLOWED_IPS}" >"${HOME_DIR}/${CLIENT_NAME}.conf"

    # Add the client as a peer to the server
    echo -e "\n### Client ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}/32,${CLIENT_WG_IPV6}/128" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"

    wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}")

    # Generate QR code if qrencode is installed
    if command -v qrencode &>/dev/null; then
        echo -e "${GREEN}\nHere is your client config file as a QR Code:\n${NC}"
        qrencode -t ansiutf8 -l L <"${HOME_DIR}/${CLIENT_NAME}.conf"
        echo ""
    fi

    echo -e "${GREEN}Your client config file is in ${HOME_DIR}/${CLIENT_NAME}.conf${NC}"
}

function listClients() {
    NUMBER_OF_CLIENTS=$(grep -c -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf")
    if [[ ${NUMBER_OF_CLIENTS} -eq 0 ]]; then
        echo ""
        echo "You have no existing clients!"
        exit 1
    fi

    grep -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf" | cut -d ' ' -f 3 | nl -s ') '
}

function revokeClient() {
    NUMBER_OF_CLIENTS=$(grep -c -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf")
    if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
        echo ""
        echo "You have no existing clients!"
        exit 1
    fi

    echo ""
    echo "Select the existing client you want to revoke"
    grep -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf" | cut -d ' ' -f 3 | nl -s ') '
    until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
        if [[ ${CLIENT_NUMBER} == '1' ]]; then
            read -rp "Select one client [1]: " CLIENT_NUMBER
        else
            read -rp "Select one client [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
        fi
    done

    # match the selected number to a client name
    CLIENT_NAME=$(grep -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)

    # remove [Peer] block matching $CLIENT_NAME
    sed -i "/^### Client ${CLIENT_NAME}\$/,/^$/d" "/etc/wireguard/${SERVER_WG_NIC}.conf"

    # remove generated client file
    HOME_DIR=$(getHomeDirForClient "${CLIENT_NAME}")
    rm -f "${HOME_DIR}/${CLIENT_NAME}.conf"

    # restart wireguard to apply changes
    wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}")
}

function uninstallWg() {
    echo ""
    echo -e "\n${RED}WARNING: This will uninstall WireGuard and remove all the configuration files!${NC}"
    echo -e "${ORANGE}Please backup the /etc/wireguard directory if you want to keep your configuration files.\n${NC}"
    read -rp "Do you really want to remove WireGuard? [y/n]: " -e REMOVE
    REMOVE=${REMOVE:-n}
    if [[ $REMOVE == 'y' ]]; then
        checkOS

        systemctl stop "wg-quick@${SERVER_WG_NIC}"
        systemctl disable "wg-quick@${SERVER_WG_NIC}"

        if [[ ${OS} == 'ubuntu' ]]; then
            apt-get remove -y wireguard wireguard-tools qrencode
        elif [[ ${OS} == 'debian' ]]; then
            apt-get remove -y wireguard wireguard-tools qrencode
        elif [[ ${OS} == 'fedora' ]]; then
            dnf remove -y --noautoremove wireguard-tools qrencode
            if [[ ${VERSION_ID} -lt 32 ]]; then
                dnf remove -y --noautoremove wireguard-dkms
                dnf copr disable -y jdoss/wireguard
            fi
        elif [[ ${OS} == 'centos' ]] || [[ ${OS} == 'almalinux' ]] || [[ ${OS} == 'rocky' ]]; then
            yum remove -y --noautoremove wireguard-tools
            if [[ ${VERSION_ID} == 8* ]]; then
                yum remove --noautoremove kmod-wireguard qrencode
            fi
        elif [[ ${OS} == 'oracle' ]]; then
            yum remove --noautoremove wireguard-tools qrencode
        elif [[ ${OS} == 'arch' ]]; then
            pacman -Rs --noconfirm wireguard-tools qrencode
        fi

        rm -rf /etc/wireguard
        rm -f /etc/sysctl.d/wg.conf

        # Remove WireGuard service file
        systemctl disable wg-quick@wg0.service
        systemctl stop wg-quick@wg0.service
        rm -f /etc/systemd/system/wg-quick@wg0.service

        # Reload systemd
        systemctl daemon-reload

        # Reload sysctl
        sysctl --system

        # Check if WireGuard is running
        systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}"
        WG_RUNNING=$?

        if [[ ${WG_RUNNING} -eq 0 ]]; then
            echo "WireGuard failed to uninstall properly."
            exit 1
        else
            echo "WireGuard uninstalled successfully."
            exit 0
        fi
    else
        echo ""
        echo "Removal aborted!"
    fi
}

function manageMenu() {
    echo "Welcome to WireGuard-install!"
    echo "The git repository is available at: https://github.com/W01v3n/wireguard-install"
    echo ""
    echo "It looks like WireGuard is already installed."
    echo ""
    echo "What do you want to do?"
    echo "   1) Add a new user"
    echo "   2) List all users"
    echo "   3) Revoke existing user"
    echo "   4) Uninstall WireGuard"
    echo "   5) Exit"
    until [[ ${MENU_OPTION} =~ ^[1-5]$ ]]; do
        read -rp "Select an option [1-5]: " MENU_OPTION
    done
    case "${MENU_OPTION}" in
    1)
        newClient
        ;;
    2)
        listClients
        ;;
    3)
        revokeClient
        ;;
    4)
        uninstallWg
        ;;
    5)
        exit 0
        ;;
    esac
}

# Check for root, virt, OS...
initialCheck

# Check if WireGuard is already installed and load params
if [[ -e /etc/wireguard/params ]]; then
    source /etc/wireguard/params
    manageMenu
else
    autoInstall
fi
