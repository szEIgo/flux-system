#!/usr/bin/env bash
# DESCRIPTION: Display available commands and their descriptions
# USAGE: make help (or make)
# CATEGORY: info

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Flux GitOps with SOPS"
echo ""
echo "All automation logic is in scripts/"
echo ""

# Find all scripts and extract their metadata
declare -A descriptions
declare -A usages
declare -A categories

for script in "$SCRIPT_DIR"/*.sh; do
    [ -f "$script" ] || continue
    [ "$(basename "$script")" = "config.sh" ] && continue
    [ "$(basename "$script")" = "help.sh" ] && continue
    
    name=$(basename "$script" .sh)
    
    # Extract DESCRIPTION
    desc=$(grep "^# DESCRIPTION:" "$script" | head -1 | sed 's/^# DESCRIPTION: //')
    [ -n "$desc" ] && descriptions[$name]="$desc"
    
    # Extract USAGE
    usage=$(grep "^# USAGE:" "$script" | head -1 | sed 's/^# USAGE: //')
    [ -n "$usage" ] && usages[$name]="$usage"
    
    # Extract CATEGORY
    category=$(grep "^# CATEGORY:" "$script" | head -1 | sed 's/^# CATEGORY: //')
    [ -z "$category" ] && category="general"
    categories[$name]="$category"
done

# Group by category
print_category() {
    local cat="$1"
    local title="$2"
    local found=0
    
    for name in "${!descriptions[@]}"; do
        if [ "${categories[$name]}" = "$cat" ]; then
            found=1
            break
        fi
    done
    
    [ $found -eq 0 ] && return
    
    echo "$title:"
    for name in $(echo "${!descriptions[@]}" | tr ' ' '\n' | sort); do
        if [ "${categories[$name]}" = "$cat" ]; then
            printf "  %-15s  %s\n" "${usages[$name]}" "${descriptions[$name]}"
        fi
    done
    echo ""
}

# Print categories in order
print_category "setup" "Setup & Bootstrap"
print_category "secrets" "Secrets Management"
print_category "operations" "Day-to-Day Operations"
print_category "maintenance" "Maintenance"
print_category "info" "Information"

echo "Quick Start: make init -> make add-gh-pat -> make up"
echo "Configuration: scripts/config.sh"
echo ""
