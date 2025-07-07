#!/bin/bash
set -e

# === Basic Configuration ===
BASE_CONTAINER_NAME="nexus-node"
IMAGE_NAME="nexus-node:latest"
LOG_DIR="${HOME}/nexus_logs"
SCRIPT_DIR_MAIN_CALL="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# === Colors and Styling ===
BOLD='\033[1m'
HGREEN='\033[1;32m'
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RESET='\033[0m'

function show_header() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo -e "${BOLD}${HGREEN}"
    echo "███╗   ███╗██████╗        ██╗  ██╗"
    echo "████╗ ████║██╔══██╗       ╚██╗██╔╝"
    echo "██╔████╔██║██████╔╝        ╚███╔╝ "
    echo "██║╚██╔╝██║██╔══██╗        ██╔██╗ "
    echo "██║ ╚═╝ ██║██║  ██║██╗    ██╔╝ ██╗"
    echo "╚═╝     ╚═╝╚═╝  ╚═╝╚═╝    ╚═╝  ╚═╝"

    echo "                 Github: http://github.com/iamxlord"
    echo -e "                 Twitter: http://x.com/iamxlord${RESET}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

function check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${YELLOW}Docker not found. Installing Docker...${RESET}"
        sudo apt update
        sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt update
        sudo apt install -y docker-ce
        sudo systemctl enable docker
        sudo systemctl start docker
        echo -e "${GREEN}Docker installed and started.${RESET}"
    fi
}

function check_cron() {
    if ! command -v cron >/dev/null 2>&1; then
        echo -e "${YELLOW}Cron not found. Installing cron...${RESET}"
        sudo apt update
        sudo apt install -y cron
        sudo systemctl enable cron
        sudo systemctl start cron
        echo -e "${GREEN}Cron installed and started.${RESET}"
    fi
}

function build_image() {
    echo -e "${YELLOW}Building Docker image for Nexus node...${RESET}"
    WORKDIR=$(mktemp -d)
    cd "$WORKDIR"

    cat > Dockerfile <<EOF
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PROVER_ID_FILE=/root/.nexus/node-id

RUN apt-get update && apt-get install -y \\
    curl \\
    screen \\
    bash \\
    && rm -rf /var/lib/apt/lists/*

RUN curl -sSL https://cli.nexus.xyz/ | NONINTERACTIVE=1 sh \\
    && ln -sf /root/.nexus/bin/nexus-network /usr/local/bin/nexus-network

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
EOF

    cat > entrypoint.sh <<EOF
#!/bin/bash
set -e
PROVER_ID_FILE="/root/.nexus/node-id"
if [ -z "\$NODE_ID" ]; then
    echo "NODE_ID is not set. Exiting."
    exit 1
fi
echo "\$NODE_ID" > "\$PROVER_ID_FILE"
screen -S nexus -X quit >/dev/null 2>&1 || true
screen -dmS nexus bash -c "nexus-network start --node-id \$NODE_ID &>> /root/nexus.log"
sleep 3
if screen -list | grep -q "nexus"; then
    echo "Node is running in the background."
else
    echo "Failed to start node. Check logs below for details."
    cat /root/nexus.log
    exit 1
fi
tail -f /root/nexus.log
EOF

    sudo docker build -t "$IMAGE_NAME" .
    cd -
    rm -rf "$WORKDIR"
    echo -e "${GREEN}Docker image '${IMAGE_NAME}' built successfully.${RESET}"
}

function run_container() {
    local node_id=$1
    local container_name="${BASE_CONTAINER_NAME}-${node_id}"
    local log_file="${LOG_DIR}/nexus-${node_id}.log"

    echo -e "${YELLOW}Starting Nexus node with ID: ${node_id}...${RESET}"

    sudo docker rm -f "$container_name" 2>/dev/null || true
    mkdir -p "$LOG_DIR"
    touch "$log_file"
    chmod 644 "$log_file"

    sudo docker run -d --name "$container_name" -v "$log_file":/root/nexus.log -e NODE_ID="$node_id" "$IMAGE_NAME"

    check_cron
    echo "0 0 * * * rm -f $log_file" | sudo tee "/etc/cron.d/nexus-log-cleanup-${node_id}" > /dev/null
    echo -e "${GREEN}Nexus node '${node_id}' started in container '${container_name}'. Logs at ${log_file}${RESET}"
}

function uninstall_node() {
    local node_id=$1
    local cname="${BASE_CONTAINER_NAME}-${node_id}"
    echo -e "${YELLOW}Attempting to stop and remove node '${node_id}'...${RESET}"
    sudo docker rm -f "$cname" 2>/dev/null || true
    rm -f "${LOG_DIR}/nexus-${node_id}.log"
    sudo rm -f "/etc/cron.d/nexus-log-cleanup-${node_id}"
    echo -e "${GREEN}Node '${node_id}' has been uninstalled.${RESET}"
}

function get_all_nodes() {
    sudo docker ps -a --format "{{.Names}}" | grep "^${BASE_CONTAINER_NAME}-" | sed "s/${BASE_CONTAINER_NAME}-//"
}

function list_nodes() {
    show_header
    echo -e "${CYAN}📊 Registered Node List:${RESET}"
    echo "--------------------------------------------------------------"
    printf "%-5s %-20s %-12s %-15s %-15s\n" "No" "Node ID" "Status" "CPU" "Memory"
    echo "--------------------------------------------------------------"
    local all_nodes=($(get_all_nodes))
    local failed_nodes=()
    if [ ${#all_nodes[@]} -eq 0 ]; then
        echo "No Nexus nodes found."
    else
        for i in "${!all_nodes[@]}"; do
            local node_id=${all_nodes[$i]}
            local container="${BASE_CONTAINER_NAME}-${node_id}"
            local cpu="N/A"
            local mem="N/A"
            local status="Inactive" # Default status
            if sudo docker inspect "$container" &>/dev/null; then
                status=$(sudo docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
                if [[ "$status" == "running" ]]; then
                    stats=$(sudo docker stats --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}" "$container" 2>/dev/null)
                    cpu=$(echo "$stats" | cut -d'|' -f1)
                    mem=$(echo "$stats" | cut -d'|' -f2 | cut -d'/' -f1 | xargs)
                elif [[ "$status" == "exited" ]]; then
                    failed_nodes+=("$node_id")
                fi
            fi
            printf "%-5s %-20s %-12s %-15s %-15s\n" "$((i+1))" "$node_id" "$status" "$cpu" "$mem"
        done
    fi
    echo "--------------------------------------------------------------"
    if [ ${#failed_nodes[@]} -gt 0 ]; then
        echo -e "${RED}⚠ Failed (exited) nodes:${RESET}"
        for id in "${failed_nodes[@]}"; do
            echo "- $id"
        done
    fi
    read -p "Press Enter to return to the menu..."
}

function view_logs() {
    local all_nodes=($(get_all_nodes))
    if [ ${#all_nodes[@]} -eq 0 ]; then
        echo -e "${YELLOW}No Nexus nodes found to view logs for.${RESET}"
        read -p "Press Enter to return to the menu..."
        return
    fi # <--- Corrected from '}'

    echo -e "${CYAN}Select a node to view logs:${RESET}"
    for i in "${!all_nodes[@]}"; do
        echo "$((i+1)). ${all_nodes[$i]}"
    done
    read -rp "Enter the number: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice > 0 && choice <= ${#all_nodes[@]} )); then
        local selected=${all_nodes[$((choice-1))]}
        echo -e "${YELLOW}Displaying logs for node: ${selected}${RESET}"
        sudo docker logs -f "${BASE_CONTAINER_NAME}-${selected}"
    else
        echo -e "${RED}Invalid choice. Please enter a valid number.${RESET}"
    fi
    read -p "Press Enter to return to the menu..."
}

function batch_uninstall_nodes() {
    local all_nodes=($(get_all_nodes))
    if [ ${#all_nodes[@]} -eq 0 ]; then
        echo -e "${YELLOW}No Nexus nodes found to uninstall.${RESET}"
        read -p "Press Enter to return to the menu..."
        return
    fi # <--- Corrected from '}'

    echo -e "${CYAN}Enter the numbers of the nodes you want to uninstall (separate with spaces):${RESET}"
    for i in "${!all_nodes[@]}"; do
        echo "$((i+1)). ${all_nodes[$i]}"
    done
    read -rp "Numbers: " input
    for num in $input; do
        if [[ "$num" =~ ^[0-9]+$ ]] && (( num > 0 && num <= ${#all_nodes[@]} )); then
            uninstall_node "${all_nodes[$((num-1))]}"
        else
            echo -e "${YELLOW}Skipping invalid input: ${num}${RESET}"
        fi
    done
    read -p "Press Enter to return to the menu..."
}

function uninstall_all_nodes() {
    local all_nodes=($(get_all_nodes))
    if [ ${#all_nodes[@]} -eq 0 ]; then
        echo -e "${YELLOW}No Nexus nodes found to uninstall.${RESET}"
        read -p "Press Enter to return to the menu..."
        return
    fi # <--- Corrected from '}'

    echo -e "${RED}Are you sure you want to uninstall ALL Nexus nodes? (y/n)${RESET}"
    read -rp "Confirm: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        for node in "${all_nodes[@]}"; do
            uninstall_node "$node"
        done
        echo -e "${GREEN}All Nexus nodes have been uninstalled.${RESET}"
    else
        echo -e "${YELLOW}Uninstallation cancelled.${RESET}"
    fi
    read -p "Press Enter to return to the menu..."
}

function monitor_and_restart_nodes() {
    echo "$(date): Running node health check..."
    local all_nodes=($(get_all_nodes))
    if [ ${#all_nodes[@]} -eq 0 ]; then
        echo "$(date): No Nexus nodes found to monitor."
        return
    fi # <--- Corrected from '}'

    for node_id in "${all_nodes[@]}"; do
        local container_name="${BASE_CONTAINER_NAME}-${node_id}"
        if sudo docker inspect "$container_name" &>/dev/null; then
            local status=$(sudo docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
            if [[ "$status" == "running" ]]; then
                echo "$(date): Node ${node_id} is running (Status: ${status})."
            else
                echo "$(date): Node ${node_id} is NOT running (Status: ${status}). Attempting restart..."
                if sudo docker start "$container_name" &>/dev/null; then
                    echo "$(date): Node ${node_id} restarted successfully."
                else
                    echo "$(date): Failed to restart node ${node_id}. Deleting and re-running..."
                    uninstall_node "$node_id"
                    run_container "$node_id"
                    echo "$(date): Node ${node_id} re-provisioned successfully."
                fi
            fi
        else
            echo "$(date): Node ${node_id} container '${container_name}' does not exist. Removing lingering cron/log entries."
            rm -f "${LOG_DIR}/nexus-${node_id}.log"
            sudo rm -f "/etc/cron.d/nexus-log-cleanup-${node_id}"
            sudo rm -f "/etc/cron.d/nexus-monitor-${node_id}"
        fi
    done
    echo "$(date): Node health check complete."
}

function setup_monitor_cron() {
    check_cron

    local MONITOR_SCRIPT_PATH="${SCRIPT_DIR_MAIN_CALL}/nexus_monitor.sh"
    local CRON_FILE="/etc/cron.d/nexus-monitor-global"

    local EXPECTED_CRON_ENTRY="*/5 * * * * ${USER} ${MONITOR_SCRIPT_PATH}"
    if [ ! -f "$CRON_FILE" ] || ! sudo grep -qxF "${EXPECTED_CRON_ENTRY}" "$CRON_FILE"; then
        echo -e "${YELLOW}Setting up global Nexus node monitoring via cron...${RESET}"

        cat > "$MONITOR_SCRIPT_PATH" <<EOF
#!/bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

SCRIPT_DIR_MONITOR="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "\$SCRIPT_DIR_MONITOR/nexus.sh" # Source the main script

monitor_and_restart_nodes >> "${LOG_DIR}/nexus_monitor.log" 2>&1
EOF
        chmod +x "$MONITOR_SCRIPT_PATH"

        echo "$EXPECTED_CRON_ENTRY" | sudo tee "$CRON_FILE" > /dev/null
        echo -e "${GREEN}Global Nexus node monitoring activated via cron (runs every 5 minutes). Logs at ${LOG_DIR}/nexus_monitor.log${RESET}"
    else
        echo -e "${YELLOW}Global Nexus node monitoring is already active and up-to-date.${RESET}"
    fi
}

setup_monitor_cron

while true; do
    show_header
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "        NEXUS - 'stable' X"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${GREEN} 1.${RESET} ➕ Install & Run Node"
    echo -e "${GREEN} 2.${RESET} 📊 View All Node Status"
    echo -e "${GREEN} 3.${RESET} ❌ Uninstall Specific Node(s)"
    echo -e "${GREEN} 4.${RESET} 🧾 View Node Logs"
    echo -e "${GREEN} 5.${RESET} 💥 Uninstall All Nodes"
    echo -e "${GREEN} 6.${RESET} 🚪 Exit"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    read -rp "Select an option (1-6): " choice

    case $choice in
        1)
            check_docker
            read -rp "Enter NODE_ID: " NODE_ID
            if [ -z "$NODE_ID" ]; then
                echo -e "${RED}NODE_ID cannot be empty. Please try again.${RESET}"
                read -p "Press Enter to continue..."
                continue
            fi
            build_image
            run_container "$NODE_ID"
            echo -e "${GREEN}Node installation process initiated. Check status in option 2.${RESET}"
            read -p "Press Enter to continue..."
            ;;
        2) list_nodes ;;
        3) batch_uninstall_nodes ;;
        4) view_logs ;;
        5) uninstall_all_nodes ;;
        6) echo "Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid option. Please enter a number between 1 and 6.${RESET}"; read -p "Press Enter to continue..." ;;
    esac
done
