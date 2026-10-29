#!/usr/bin/env bash
# Latence CDC de bout en bout : insère N commandes horodatées dans Postgres (local), puis mesure le délai
# jusqu'à leur apparition dans DCP_POC.FOURNIL_PUBLIC.ORDERS (merge Openflow toutes les minutes).
export LC_NUMERIC=C
set -uo pipefail
cd "$(dirname "$0")/.."
source .env
N=${1:-100}
OUT=bench/results/$(date +%Y%m%d_%H%M%S)_cdc_latency.txt
base=$(docker compose -f local/docker-compose.yml exec -T postgres psql -U fournil_admin -d fournil -Atc "select max(order_id) from orders")
t0=$(date +%s.%N)
docker compose -f local/docker-compose.yml exec -T postgres psql -U fournil_admin -d fournil -q -c \
  "insert into orders select $base + i, 1 + (i % 10000), 1 + (i % 10), 1, 1.30, now() from generate_series(1, $N) i"
echo "$(date +%T) $N commandes insérées (order_id > $base)" | tee "$OUT"
while :; do
    n=$(snow sql -c "$SNOWFLAKE_CONNECTION" --role ACCOUNTADMIN --format json \
        -q "select count(*) n from DCP_POC.FOURNIL_PUBLIC.ORDERS where order_id > $base" 2>/dev/null \
        | python3 -c 'import json,sys
try: print(json.load(sys.stdin)[0]["N"])
except Exception: print(0)')
    dt=$(echo "$(date +%s.%N) - $t0" | bc)
    printf '%s t=%.0fs visibles=%s/%s\n' "$(date +%T)" "$dt" "$n" "$N" | tee -a "$OUT"
    [ "$n" -ge "$N" ] && break
    [ "${dt%.*}" -gt ${MAX_S:-600} ] && { echo "abandon après 10 min" | tee -a "$OUT"; break; }
    sleep 5
done
