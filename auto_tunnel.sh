#!/bin/bash
SERVER_IP="85.215.77.88"
SERVICE_USER="apsys_tunneler"
DEPLOY_USER="burrow"
# CHANGE THIS URL to where you hosted the file
PASSWORD_FILE_URL="https://raw.githubusercontent.com/AccessAstronomy/wormgat/refs/heads/main/lost-found.tmp" 

echo "=== Zero-Touch Wormgat Tunnel Setup ==="
if ! command -v sshpass &> /dev/null; then sudo apt-get update -qq && sudo apt-get install -y -qq sshpass openssl; fi

curl -s -o lost-found.tmp "$PASSWORD_FILE_URL"
read -s -p "[?] Enter Installation Secret: " SECRET
echo ""
BURROW_PASS=$(cat lost-found.tmp | openssl enc -aes-256-cbc -pbkdf2 -a -d -salt -pass pass:"$SECRET" 2>/dev/null)
rm lost-found.tmp

if [ -z "$BURROW_PASS" ]; then echo "[!] Incorrect Secret."; exit 1; fi

LOCAL_USER=$(whoami)
if [ ! -f ~/.ssh/id_ed25519 ]; then ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q; fi
PUB_KEY=$(cat ~/.ssh/id_ed25519.pub)

echo "[+] Registering on server..."
REMOTE_CMD="sudo -u $SERVICE_USER /usr/local/bin/register_wormgat.sh \"$PUB_KEY\" \"$LOCAL_USER\""
ASSIGNED_PORT=$(sshpass -p "$BURROW_PASS" ssh -o StrictHostKeyChecking=accept-new -q "$DEPLOY_USER@$SERVER_IP" "$REMOTE_CMD")
MQQT_PORT=$((ASSIGNED_PORT + 20000))

if ! [[ "$ASSIGNED_PORT" =~ ^[0-9]+$ ]]; then echo "[!] Error: $ASSIGNED_PORT"; exit 1; fi
echo "[v] Port Assigned: $ASSIGNED_PORT"
echo "[v] Plug Port: $MQQT_PORT"

sudo bash -c "cat > /etc/systemd/system/apsys-tunnel.service" <<EOF
[Unit]
Description=Wormgat Tunnel (Port $ASSIGNED_PORT)
After=network-online.target
Wants=network-online.target
[Service]
User=$LOCAL_USER
ExecStart=/usr/bin/ssh -N -T -i /home/$LOCAL_USER/.ssh/id_ed25519 -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" -o "ExitOnForwardFailure yes" -o "ConnectTimeout 10" -o "StrictHostKeyChecking=accept-new" -R 0.0.0.0:$ASSIGNED_PORT:localhost:22 -R 0.0.0.0:$MQQT_PORT:localhost:1883 $SERVICE_USER@$SERVER_IP
Restart=always
RestartSec=10
StartLimitIntervalSec=0
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload && sudo systemctl enable apsys-tunnel.service && sudo systemctl restart apsys-tunnel.service
echo "[SUCCESS] Tunnel Active on Port $ASSIGNED_PORT"
