#!/bin/bash
# cloud-run-usage.sh — Xem Cloud Run free tier usage tháng này
# Usage: ./scripts/cloud-run-usage.sh

set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────
SERVICE="notch-portal-api"
REGION="asia-southeast1"

# Free tier limits (request-based billing)
FREE_REQUESTS=2000000
FREE_VCPU_SECONDS=180000
FREE_MEMORY_GIB_SECONDS=360000

# Container config
CONTAINER_VCPU=1.0
CONTAINER_MEMORY_GIB=0.5   # 512Mi = 0.5 GiB
AVG_LATENCY_SEC=0.1         # ~100ms avg từ logs

# ─── Colors ───────────────────────────────────────────────────────────────────
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
RESET="\033[0m"

# ─── Helpers ──────────────────────────────────────────────────────────────────
bar() {
  local pct=$1
  local width=30
  local filled=$(echo "$pct $width" | awk '{printf "%d", ($1/100)*$2}')
  local empty=$((width - filled))
  local color="$GREEN"
  if (( $(echo "$pct > 70" | bc -l) )); then color="$YELLOW"; fi
  if (( $(echo "$pct > 90" | bc -l) )); then color="$RED"; fi
  printf "${color}["
  printf '%0.s█' $(seq 1 $filled 2>/dev/null) 2>/dev/null || printf '%*s' "$filled" | tr ' ' '█'
  printf '%*s' "$empty" | tr ' ' '░'
  printf "]${RESET}"
}

pct() {
  echo "$1 $2" | awk '{printf "%.2f", ($1/$2)*100}'
}

# ─── Header ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}☁  Cloud Run Free Tier Usage — $(date '+%B %Y')${RESET}"
echo -e "${CYAN}   Service: ${SERVICE} (${REGION})${RESET}"
echo "───────────────────────────────────────────────────────"

# ─── Lấy ngày đầu tháng hiện tại ─────────────────────────────────────────────
FIRST_DAY=$(date '+%Y-%m-01T00:00:00Z')
NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

echo -e "\n📡 Đang lấy dữ liệu từ GCP Logging..."
echo -e "   Từ: ${FIRST_DAY} → ${NOW}\n"

# ─── Đếm request trong tháng ─────────────────────────────────────────────────
REQUEST_COUNT=$(gcloud logging read \
  "resource.type=\"cloud_run_revision\" \
   AND resource.labels.service_name=\"${SERVICE}\" \
   AND timestamp>=\"${FIRST_DAY}\"" \
  --freshness=720h \
  --format="value(timestamp)" \
  2>/dev/null | wc -l | tr -d ' ')

# ─── Tính CPU & Memory seconds ────────────────────────────────────────────────
VCPU_SECONDS=$(echo "$REQUEST_COUNT $AVG_LATENCY_SEC $CONTAINER_VCPU" | \
  awk '{printf "%.1f", $1 * $2 * $3}')

MEMORY_GIB_SECONDS=$(echo "$REQUEST_COUNT $AVG_LATENCY_SEC $CONTAINER_MEMORY_GIB" | \
  awk '{printf "%.1f", $1 * $2 * $3}')

# ─── Tính % ───────────────────────────────────────────────────────────────────
REQ_PCT=$(pct "$REQUEST_COUNT" "$FREE_REQUESTS")
VCPU_PCT=$(pct "$VCPU_SECONDS" "$FREE_VCPU_SECONDS")
MEM_PCT=$(pct "$MEMORY_GIB_SECONDS" "$FREE_MEMORY_GIB_SECONDS")

# ─── Hiển thị ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}  Requests${RESET}"
printf "  $(bar "$REQ_PCT") %6.2f%%  (%s / %s)\n" \
  "$REQ_PCT" \
  "$(printf "%'d" $REQUEST_COUNT)" \
  "$(printf "%'d" $FREE_REQUESTS)"

echo ""
echo -e "${BOLD}  vCPU-seconds${RESET} ${YELLOW}(ước tính)${RESET}"
printf "  $(bar "$VCPU_PCT") %6.2f%%  (%.1f / %s)\n" \
  "$VCPU_PCT" \
  "$VCPU_SECONDS" \
  "$(printf "%'d" $FREE_VCPU_SECONDS)"

echo ""
echo -e "${BOLD}  Memory GiB-seconds${RESET} ${YELLOW}(ước tính)${RESET}"
printf "  $(bar "$MEM_PCT") %6.2f%%  (%.1f / %s)\n" \
  "$MEM_PCT" \
  "$MEMORY_GIB_SECONDS" \
  "$(printf "%'d" $FREE_MEMORY_GIB_SECONDS)"

echo ""
echo "───────────────────────────────────────────────────────"

# ─── Status ───────────────────────────────────────────────────────────────────
MAX_PCT=$(echo "$REQ_PCT $VCPU_PCT $MEM_PCT" | awk '{m=$1; for(i=2;i<=NF;i++) if($i>m) m=$i; print m}')

if (( $(echo "$MAX_PCT < 50" | bc -l) )); then
  echo -e "  ${GREEN}${BOLD}✅ Trạng thái: AN TOÀN — Còn rất xa giới hạn free tier${RESET}"
elif (( $(echo "$MAX_PCT < 80" | bc -l) )); then
  echo -e "  ${YELLOW}${BOLD}⚠️  Trạng thái: CHÚ Ý — Nên monitor thêm${RESET}"
else
  echo -e "  ${RED}${BOLD}🚨 Trạng thái: NGUY HIỂM — Sắp vượt free tier!${RESET}"
fi

echo ""
echo -e "  ${CYAN}💡 Lưu ý: vCPU & Memory là ước tính dựa trên avg latency ${AVG_LATENCY_SEC}s${RESET}"
echo -e "  ${CYAN}   Để xem chính xác: console.cloud.google.com/billing${RESET}"
echo ""
