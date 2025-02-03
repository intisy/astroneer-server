#!/bin/bash

# Preset Default Values (can be overridden by environment variables or command-line arguments)
DEFAULT_OWNER_NAME="AstroServerAdmin"
DEFAULT_SERVER_NAME="MyAstroServer"
DEFAULT_PASSWORD="MyAstroPassword"
DEFAULT_SERVER_PORT=8777
DEFAULT_MAX_FPS=60
DEFAULT_INSTALL_PATH="$(pwd)"
DEFAULT_AUTO_REBOOT=false
DEFAULT_NO_WAIT=false
DEFAULT_NO_SERVER_PASSWORD=false
DEFAULT_NO_ASTRO_LAUNCHER=false
DEFAULT_NO_SERVICE=false
DEFAULT_NO_NSSM=true

# Set values from environment variables or use defaults
OWNER_NAME="${OWNER_NAME:-$DEFAULT_OWNER_NAME}"
SERVER_NAME="${SERVER_NAME:-$DEFAULT_SERVER_NAME}"
SERVER_PASSWORD="${SERVER_PASSWORD:-$DEFAULT_PASSWORD}"
SERVER_PORT="${SERVER_PORT:-$DEFAULT_SERVER_PORT}"
MAX_FPS="${MAX_FPS:-$DEFAULT_MAX_FPS}"
INSTALL_PATH="${INSTALL_PATH:-$DEFAULT_INSTALL_PATH}"
AUTO_REBOOT="${AUTO_REBOOT:-$DEFAULT_AUTO_REBOOT}"
NO_WAIT="${NO_WAIT:-$DEFAULT_NO_WAIT}"
NO_SERVER_PASSWORD="${NO_SERVER_PASSWORD:-$DEFAULT_NO_SERVER_PASSWORD}"
NO_ASTRO_LAUNCHER="${NO_ASTRO_LAUNCHER:-$DEFAULT_NO_ASTRO_LAUNCHER}"
NO_SERVICE="${NO_SERVICE:-$DEFAULT_NO_SERVICE}"

# Service-related defaults
NSSM_BUILD="nssm-2.24-101-g897c7ad"
NSSM_URL="https://nssm.cc/ci/$NSSM_BUILD.zip"

# Logging setup
LOG_FILE="AstroInstaller.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Check for admin privileges
if ! net session >/dev/null 2>&1; then
    echo "Please run this script as Administrator"
    exit 1
fi

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ownerName) OWNER_NAME="$2"; shift ;;
        --serverName) SERVER_NAME="$2"; shift ;;
        --serverPassword) SERVER_PASSWORD="$2"; shift ;;
        --serverPort) SERVER_PORT="$2"; shift ;;
        --maxFPS) MAX_FPS="$2"; shift ;;
        --installPath) INSTALL_PATH="$2"; shift ;;
        --autoReboot) AUTO_REBOOT=true ;;
        --noWait) NO_WAIT=true ;;
        --noServerPassword) NO_SERVER_PASSWORD=true ;;
        --noAstroLauncher) NO_ASTRO_LAUNCHER=true ;;
        --noService) NO_SERVICE=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Configuration summary
echo "=== Astro Server Installation ==="
echo "Using configuration:"
echo " - Owner Name:      $OWNER_NAME"
echo " - Server Name:     $SERVER_NAME"
echo " - Server Port:     $SERVER_PORT"
echo " - Max FPS:         $MAX_FPS"
echo " - Install Path:    $INSTALL_PATH"
echo " - Auto Reboot:     $AUTO_REBOOT"
echo " - No Wait:         $NO_WAIT"
echo " - No Password:     $NO_SERVER_PASSWORD"
echo " - No AstroLauncher:$NO_ASTRO_LAUNCHER"
echo " - No Service:      $NO_SERVICE"
echo "================================"

# Install .NET Framework
# echo "Installing .NET Framework..."
# dism /online /enable-feature /featurename:NetFx3 /all /quiet

# Install SteamCMD
echo "Installing SteamCMD..."
mkdir -p "$INSTALL_PATH/SteamCMD"
curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -o "$INSTALL_PATH/SteamCMD/steamcmd.zip"
unzip -qo "$INSTALL_PATH/SteamCMD/steamcmd.zip" -d "$INSTALL_PATH/SteamCMD"

# Install Astroneer Server
echo "Installing Astroneer Dedicated Server..."
mkdir -p "$INSTALL_PATH/Astroneer"
"$INSTALL_PATH/SteamCMD/steamcmd.exe" +force_install_dir "$INSTALL_PATH/Astroneer" +login anonymous +app_update 728470 +quit

# Configure firewall
echo "Configuring firewall..."
netsh advfirewall firewall add rule name="AstroServer" dir=in action=allow program="$INSTALL_PATH/Astroneer/AstroServer.exe"
netsh advfirewall firewall add rule name="AstroServer" dir=in action=allow protocol=UDP localport=$SERVER_PORT

# Configure server files
CONFIG_FILE="$INSTALL_PATH/Astroneer/Astro/Saved/Config/WindowsServer/AstroServerSettings.ini"
ENGINE_FILE="$INSTALL_PATH/Astroneer/Astro/Saved/Config/WindowsServer/Engine.ini"

PUBLIC_IP=$(curl -s http://ifconfig.me/ip)

# Update configuration files
sed -i "/PublicIP=/d" "$CONFIG_FILE"
sed -i "/MaxServerFramerate=/d" "$CONFIG_FILE"
sed -i "/ServerName=/d" "$CONFIG_FILE"
sed -i "/OwnerName=/d" "$CONFIG_FILE"

echo "PublicIP=$PUBLIC_IP" >> "$CONFIG_FILE"
echo "MaxServerFramerate=$MAX_FPS.000000" >> "$CONFIG_FILE"
echo "ServerName=$SERVER_NAME" >> "$CONFIG_FILE"
echo "OwnerName=$OWNER_NAME" >> "$CONFIG_FILE"

# Update engine configuration
sed -i "/^Port=/d" "$ENGINE_FILE"
echo "[URL]" > "$ENGINE_FILE"
echo "Port=$SERVER_PORT" >> "$ENGINE_FILE"

if [[ "$NO_ASTRO_LAUNCHER" == "false" ]]; then
    echo "Installing AstroLauncher..."
    curl -L -o "$(pwd)/Astroneer/AstroLauncher.exe" https://github.com/ricky-davis/AstroLauncher/releases/latest/download/AstroLauncher.exe
fi

install_service() {
    echo "Installing NSSM service..."
    curl -sqL "$NSSM_URL" -o "$INSTALL_PATH/nssm.zip"
    unzip -qo "$INSTALL_PATH/nssm.zip" -d "$INSTALL_PATH"
    
    local service_name executable_path
    if [[ "$NO_ASTRO_LAUNCHER" == "true" ]]; then
        service_name="AstroServer"
        executable_path="$INSTALL_PATH/Astroneer/AstroServer.exe"
    else
        service_name="AstroLauncher"
        executable_path="$INSTALL_PATH/Astroneer/AstroLauncher.exe"
    fi

    "$INSTALL_PATH/$NSSM_BUILD/win64/nssm.exe" install "$service_name" "$executable_path"
    "$INSTALL_PATH/$NSSM_BUILD/win64/nssm.exe" start "$service_name"
}

run_directly() {
    echo "Checking for existing services..."
    
    stop_service() {
        local service_name=$1
        echo " - Checking $service_name..."
        if sc query "$service_name" >/dev/null 2>&1; then
            echo "   → Found running $service_name, stopping..."
            sc stop "$service_name" >/dev/null 2>&1
            sc delete "$service_name" >/dev/null 2>&1
            sleep 2
        fi
    }

    stop_service "AstroServer"
    stop_service "AstroLauncher"
    
    echo "Starting server directly..."
    if [[ "$NO_ASTRO_LAUNCHER" == "true" ]]; then
        "$INSTALL_PATH/Astroneer/AstroServer.exe"
    else
        "$INSTALL_PATH/Astroneer/AstroLauncher.exe"
    fi
}

if [[ "$NO_SERVICE" == "true" ]]; then
    run_directly
else
    install_service
fi

# Final messages
echo "Installation completed!"
if [[ "$NO_WAIT" == "false" ]]; then
    echo "This window will close in 2 minutes..."
    sleep 120
fi