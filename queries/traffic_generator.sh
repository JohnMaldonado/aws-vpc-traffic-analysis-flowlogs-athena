#!/bin/bash
# =============================================================================
# traffic_generator.sh – Run on the PUBLIC EC2 instance to generate
# diverse VPC traffic captured by Flow Logs
#
# Usage: chmod +x traffic_generator.sh && ./traffic_generator.sh <PRIVATE_IP>
# =============================================================================
set -euo pipefail

PRIVATE_IP="${1:-10.15.2.100}"  # Pass private instance IP as argument
LOG_FILE="traffic_gen_$(date +%Y%m%d_%H%M%S).log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "============================================================"
log "VPC Traffic Generation – Assignment 15"
log "Target private IP: $PRIVATE_IP"
log "============================================================"

# ── 1. ICMP (ping) to private instance ──────────────────────────────────────
log "--- [1/4] ICMP: Pinging private instance ($PRIVATE_IP) ---"
ping -c 30 "$PRIVATE_IP" | tee -a "$LOG_FILE" || true
log "ICMP done – generates protocol=1 ACCEPT records in flow logs"

# ── 2. SSH (TCP/22) connection attempt ──────────────────────────────────────
log "--- [2/4] TCP/22: Testing SSH port on private instance ---"
# nc exits non-zero if refused, hence || true
nc -zv -w 5 "$PRIVATE_IP" 22 2>&1 | tee -a "$LOG_FILE" || true
log "SSH check done – generates dstport=22 TCP records"

# ── 3. HTTP/HTTPS (wget) to external sites ──────────────────────────────────
log "--- [3/4] HTTP/HTTPS: wget external websites ---"
SITES=("https://www.google.com" "https://www.amazon.com" "https://checkip.amazonaws.com")
for site in "${SITES[@]}"; do
    log "  Fetching: $site"
    wget -q -O /dev/null --timeout=15 "$site" && log "  ✓ Success" || log "  ✗ Failed"
done
log "External traffic done – egress through NAT Gateway captured as ACCEPT"

# ── 4. Blocked port connection attempt (generates REJECT) ────────────────────
log "--- [4/4] BLOCKED PORT: Attempting disallowed port on private instance ---"
# Port 443 is NOT in the private instance security group → should REJECT
log "  Trying TCP/443 on $PRIVATE_IP (expected: REJECT by SG)"
nc -zv -w 5 "$PRIVATE_IP" 443 2>&1 | tee -a "$LOG_FILE" || true

log "  Trying TCP/3306 on $PRIVATE_IP (expected: REJECT by SG)"
nc -zv -w 5 "$PRIVATE_IP" 3306 2>&1 | tee -a "$LOG_FILE" || true

log "  Trying TCP/8080 on $PRIVATE_IP (expected: REJECT by SG)"
nc -zv -w 5 "$PRIVATE_IP" 8080 2>&1 | tee -a "$LOG_FILE" || true

log "Blocked port tests done – generates REJECT records in flow logs"

# ── Summary ───────────────────────────────────────────────────────────────────
log "============================================================"
log "Traffic generation complete. Results saved to: $LOG_FILE"
log ""
log "Flow Logs delivery timeline:"
log "  - Published to S3 within 10 minutes (near-real-time)"
log "  - Partition path: AWSLogs/<account>/vpcflowlogs/<region>/YYYY/MM/DD/HH/"
log ""
log "Check S3 with:"
log "  aws s3 ls s3://jhon-a15-flow-logs-866934333672/AWSLogs/ --recursive | head -30"
log "============================================================"
