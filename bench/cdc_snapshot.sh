#!/usr/bin/env bash
# Démarre le connecteur Openflow PG_FOURNIL et chronomètre le snapshot initial :
# nombre de lignes de DCP_POC.FOURNIL_PUBLIC.ORDERS toutes les 15 s, plus les compteurs de l'agent DCP.
set -uo pipefail
cd "$(dirname "$0")/.."
source .env
CONN=$SNOWFLAKE_CONNECTION
OUT=bench/results/$(date +%Y%m%d_%H%M%S)_cdc_snapshot.csv
TARGET=${1:-1000000}
q() { snow sql -c "$CONN" --role OPENFLOW_ADMIN --format json -q "$1" 2>/dev/null; }

echo "t_s,heure,statut,lignes_orders,agent_conn_ok,octets_chiffres_vers_snowflake" > "$OUT"
t0=$(date +%s)
q "alter openflow connector DCP_OPENFLOW.INFRA.PG_FOURNIL start" > /dev/null
echo "Connecteur démarré à $(date +%T)"
while :; do
    st=$(q "show openflow connectors like 'PG_FOURNIL' in schema DCP_OPENFLOW.INFRA" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["status"])')
    n=$(snow sql -c "$CONN" --role ACCOUNTADMIN --format json -q "select count(*) n from DCP_POC.FOURNIL_PUBLIC.ORDERS" 2>/dev/null \
        | python3 -c 'import json,sys
try: print(json.load(sys.stdin)[0]["N"])
except Exception: print(0)')
    m=$(curl -s localhost:9092/metrics)
    ok=$(echo "$m" | awk '/^agent_connections_total\{status="ok"/ {print $2}')
    rx=$(echo "$m" | awk '/^tunnel_relay_bytes_total\{direction="encrypt",framing="reliable"/ {print $2}')
    t=$(( $(date +%s) - t0 ))
    echo "$t,$(date +%T),$st,$n,$ok,$rx" | tee -a "$OUT"
    [ "$n" -ge "$TARGET" ] && break
    [ "$t" -gt 3600 ] && { echo "abandon après 1 h"; break; }
    sleep 15
done
echo "-> $OUT"
