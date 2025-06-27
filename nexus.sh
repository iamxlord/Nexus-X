#!/bin/bash
set -e

# === Basic Configuration ===

BASE_CONTAINER_NAME="nexus-node"
IMAGE_NAME="nexus-node:latest"
LOG_DIR="/root/nexus_logs"

# === Colors and Styling ===
BOLD='\033[1m'
HGREEN='\033[1;32m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

function show_header() {
    clear # Clears the terminal screen
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
        # Update package lists
        sudo apt update
        # Install necessary packages for Docker
        sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        # Add Docker APT repository
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        # Update package lists again after adding repo
        sudo apt update
        # Install Docker CE (Community Edition)
        sudo apt install -y docker-ce
        # Enable and start the Docker service
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
    # Create a temporary directory for Dockerfile and entrypoint script
    WORKDIR=$(mktemp -d)
    cd "$WORKDIR"

    # Create Dockerfile
    cat > Dockerfile <<EOF
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PROVER_ID_FILE=/root/.nexus/node-id

RUN apt-get update && apt-get install -y \\
    curl \\
    screen \\
    bash \\
    && rm -rf /var/lib/apt/lists/*

# Download and install Nexus CLI, then create a symlink for easy access
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
# Start the nexus-network command in a detached screen session
screen -dmS nexus bash -c "nexus-network start --node-id \$NODE_ID &>> /root/nexus.log"
sleep 3 # Give a moment for the screen session to start
if screen -list | grep -q "nexus"; then
    echo "Node is running in the background."
else
    echo "Failed to start node. Check logs below for details."
    cat /root/nexus.log
    exit 1
fi
# Keep the container running by tailing the log file
tail -f /root/nexus.log
EOF

    # Build the Docker image
    docker build -t "$IMAGE_NAME" .
    cd - # Go back to the previous directory
    rm -rf "$WORKDIR" # Clean up the temporary directory
    echo -e "${GREEN}Docker image '${IMAGE_NAME}' built successfully.${RESET}"
}

## run_container
# Runs a Docker container for a Nexus node with a given NODE_ID.
function run_container() {
    local node_id=$1
    local container_name="${BASE_CONTAINER_NAME}-${node_id}"
    local log_file="${LOG_DIR}/nexus-${node_id}.log"

    echo -e "${YELLOW}Starting Nexus node with ID: ${node_id}...${RESET}"

    # Remove any existing container with the same name (forcefully)
    docker rm -f "$container_name" 2>/dev/null || true
    # Create the log directory if it doesn't exist
    sudo mkdir -p "$LOG_DIR"
    # Create an empty log file and set permissions
    sudo touch "$log_file"
    sudo chmod 644 "$log_file"

    # Run the Docker container in detached mode
    # -d: Run in detached mode
    # --name: Assign a name to the container
    # -v: Mount the host log file into the container
    # -e: Pass NODE_ID as an environment variable to the container
    docker run -d --name "$container_name" -v "$log_file":/root/nexus.log -e NODE_ID="$node_id" "$IMAGE_NAME"

    check_cron # Ensure cron is installed for log cleanup

    # Schedule a cron job to clean up the specific node's log file daily at midnight.
    # This prevents log files from growing indefinitely.
    echo "0 0 * * * rm -f $log_file" | sudo tee "/etc/cron.d/nexus-log-cleanup-${node_id}" > /dev/null
    echo -e "${GREEN}Nexus node '${node_id}' started in container '${container_name}'. Logs at ${log_file}${RESET}"
}

function uninstall_node() {
    local node_id=$1
    local cname="${BASE_CONTAINER_NAME}-${node_id}"
    echo -e "${YELLOW}Attempting to stop and remove node '${node_id}'...${RESET}"
    # Stop and remove the Docker container
    docker rm -f "$cname" 2>/dev/null || true
    # Remove the associated log file and cron job
    sudo rm -f "${LOG_DIR}/nexus-${node_id}.log" "/etc/cron.d/nexus-log-cleanup-${node_id}"
    echo -e "${GREEN}Node '${node_id}' has been uninstalled.${RESET}"
}

# Retrieves a list of all active Nexus node IDs by inspecting Docker container names.
function get_all_nodes() {
    docker ps -a --format "{{.Names}}" | grep "^${BASE_CONTAINER_NAME}-" | sed "s/${BASE_CONTAINER_NAME}-//"
}

# Displays a formatted list of all running Nexus nodes with their status, CPU, and memory usage.
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
            if docker inspect "$container" &>/dev/null; then
                status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
                if [[ "$status" == "running" ]]; then
                    # Get CPU and Memory usage from docker stats
                    stats=$(docker stats --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}" "$container" 2>/dev/null)
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
    fi

    echo -e "${CYAN}Select a node to view logs:${RESET}"
    for i in "${!all_nodes[@]}"; do
        echo "$((i+1)). ${all_nodes[$i]}"
    done
    read -rp "Enter the number: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice > 0 && choice <= ${#all_nodes[@]} )); then
        local selected=${all_nodes[$((choice-1))]}
        echo -e "${YELLOW}Displaying logs for node: ${selected}${RESET}"
        # Stream logs in real-time
        docker logs -f "${BASE_CONTAINER_NAME}-${selected}"
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
    fi

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
    fi

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

while true; do
    show_header
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "           NEXUS - 'stable' X
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
            # Basic validation for NODE_ID
            if [ -z "$NODE_ID" ]; then
                echo -e "${RED}NODE_ID cannot be empty. Please try again.${RESET}"
                read -p "Press Enter to continue..."
                continue # Go back to the main menu
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
        6) echo "Exiting..."; exit 0 ;; # Exit the script
        *) echo -e "${RED}Invalid option. Please enter a number between 1 and 6.${RESET}"; read -p "Press Enter to continue..." ;;
    esac
done
