#!/usr/bin/env bash
# Coupures sur le flux CDC Openflow (via DCP) : make outage S=agent-kill|net-cut [DUREE=120]
#   agent-kill  arrêt brutal de l'agent (SIGKILL), puis redémarrage après DUREE s
#   net-cut     coupure du lien Internet de l'agent pendant DUREE s (le réseau local reste joignable)
# Pendant la coupure, 1 000 commandes sont insérées dans Postgres. On mesure :
# l'état du connecteur et du proxy, le délai de retour à HEALTHY, le délai jusqu'à ce que
# toutes les lignes soient dans Snowflake, et l'absence de perte (comptage exact).
set -uo pipefail
export LC_NUMERIC=C
cd "$(dirname "$0")/../.."
source .env
CONN=$SNOWFLAKE_CONNECTION
AGENT=dcp-lab-dcp-agent-1
S=${1:?scénario manquant}
DUREE=${2:-120}
N=1000
LOG=bench/results/$(date +%Y%m%d_%H%M%S)_outage_${S}.log
PG="docker compose -f local/docker-compose.yml exec -T postgres psql -U fournil_admin -d fournil -Atq"
LAB_NET=$(docker network inspect dcp-lab_lab -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
CUT="OUTPUT -o eth0 ! -d $LAB_NET -j DROP"

log() { echo "$(date +%T) $*" | tee -a "$LOG"; }
sfq() { snow sql -c "$CONN" --role ACCOUNTADMIN --format json -q "$1" 2>/dev/null; }
proxy() { sfq "describe data connectivity proxy DCP_LOCAL" | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; print(r["agent_health"], r["data_path_status"])' 2>/dev/null || echo "?"; }
connector() { sfq "show openflow connectors like 'PG_FOURNIL' in schema DCP_OPENFLOW.INFRA" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["status"])' 2>/dev/null || echo "?"; }
visible() { sfq "select count(*) n from DCP_POC.FOURNIL_PUBLIC.ORDERS where order_id > $1" | python3 -c 'import json,sys
try: print(json.load(sys.stdin)[0]["N"])
except Exception: print(0)'; }
netshoot() { docker run --rm --net "container:$AGENT" --cap-add NET_ADMIN nicolaka/netshoot:v0.13 sh -c "$1"; }

log "=== $S ($DUREE s) ; proxy: $(proxy) ; connecteur: $(connector)"
base=$($PG -c "select max(order_id) from orders")

case "$S" in
agent-kill) docker kill "$AGENT" >/dev/null; log "agent tué (SIGKILL)" ;;
net-cut)    netshoot "iptables -I $CUT"; log "lien Internet de l'agent coupé" ;;
*) echo "scénario inconnu : $S"; exit 1 ;;
esac
t_cut=$(date +%s)

$PG -c "insert into orders select $base + i, 1 + (i % 10000), 1 + (i % 10), 1, 1.30, now() from generate_series(1, $N) i"
log "$N commandes insérées pendant la coupure (order_id > $base)"

# Pendant la coupure : ce que voit Snowflake
while [ $(( $(date +%s) - t_cut )) -lt "$DUREE" ]; do
    log "coupure +$(( $(date +%s) - t_cut ))s ; proxy: $(proxy) ; connecteur: $(connector) ; visibles: $(visible "$base")/$N"
    sleep 20
done

case "$S" in
agent-kill) docker start "$AGENT" >/dev/null; log "agent redémarré" ;;
net-cut)    netshoot "iptables -D $CUT"; log "lien rétabli" ;;
esac
t_back=$(date +%s)

healthy=""
while :; do
    p=$(proxy); v=$(visible "$base"); dt=$(( $(date +%s) - t_back ))
    [ -z "$healthy" ] && [ "${p%% *}" = HEALTHY ] && { healthy=$dt; log "proxy HEALTHY après ${dt}s"; }
    log "reprise +${dt}s ; proxy: $p ; connecteur: $(connector) ; visibles: $v/$N"
    [ "$v" -ge "$N" ] && { log "toutes les lignes visibles ${dt}s après le rétablissement"; break; }
    [ "$dt" -gt 900 ] && { log "abandon : lignes manquantes après 15 min"; break; }
    sleep 15
done
log "=== fin ; doublons éventuels : $(sfq "select count(*) - count(distinct order_id) d from DCP_POC.FOURNIL_PUBLIC.ORDERS where order_id > $base" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["D"])')"
