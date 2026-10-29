#!/usr/bin/env bash
# Scénarios de coupure du POC DCP : make scenario S=<nom>
#   agent-stop  arrêt propre de l'agent (SIGTERM, drain) pendant un appel long
#   agent-kill  arrêt brutal (SIGKILL) pendant un appel long, puis redémarrage
#   net-cut     coupure du lien Internet de l'agent pendant 90 s (le réseau local reste joignable)
#   netem       200 ms de latence et 5 % de pertes sur l'agent, puis mesure NET_PING
#   pg-stop     base Postgres arrêtée, agent sain
# Chaque scénario journalise, horodaté : l'appel Snowflake (durée, erreur) et l'état du proxy (DESCRIBE).
set -uo pipefail
cd "$(dirname "$0")/../.."
source .env
CONN=$SNOWFLAKE_CONNECTION
DCP=${DCP_NAME:-DCP_LOCAL}
AGENT=dcp-lab-dcp-agent-1
S=${1:?scénario manquant}
LOG=bench/results/$(date +%Y%m%d_%H%M%S)_scenario_${S}.log
mkdir -p bench/results

log() { echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }

# État du proxy : agent_health / agent_status / data_path_status
status() {
    snow sql -c "$CONN" --role ACCOUNTADMIN --format json -q "describe data connectivity proxy $DCP" 2>/dev/null |
        python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; print(r["agent_health"], r["agent_status"], r["data_path_status"], r["last_heartbeat_at"])'
}

# Appel Snowflake chronométré, en arrière-plan : sql, étiquette
call_bg() {
    ( t0=$(date +%s.%N)
      out=$(snow sql -c "$CONN" --role DCP_TESTER --warehouse WH_DCP -q "$1" 2>&1 | tr '\n' ' ' | tr -s ' ' | tail -c 400)
      log "[$2] fin après $(printf '%.1f' "$(echo "$(date +%s.%N) - $t0" | bc)") s : $out" ) &
}

# Surveille l'état du proxy pendant n secondes (pas de 10 s)
watch_status() {
    local end=$(( $(date +%s) + $1 ))
    while [ "$(date +%s)" -lt "$end" ]; do log "proxy: $(status)"; sleep 10; done
}

# Conteneur outil partageant le réseau de l'agent (iptables, tc) : l'image de l'agent n'en a pas
netshoot() { docker run --rm --net "container:$AGENT" --cap-add NET_ADMIN nicolaka/netshoot:v0.13 sh -c "$1"; }

# Sous-réseau Docker du labo : reste joignable pendant la coupure Internet
LAB_NET=$(docker network inspect dcp-lab_lab -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
CUT="OUTPUT -o eth0 ! -d $LAB_NET -j DROP"

SLOW="select DCP_POC.APPS.API_GET('/slow?ms=60000')"
NEW_CALL="select DCP_POC.APPS.API_GET('/health')"

log "=== scénario $S ; état initial : $(status)"
case "$S" in
agent-stop|agent-kill)
    call_bg "$SLOW" "appel long 60 s"
    sleep 15
    if [ "$S" = agent-stop ]; then
        log "docker stop (SIGTERM, drain 300 s max)"; t=$(date +%s); docker stop -t 300 "$AGENT" >/dev/null
        log "agent arrêté après $(( $(date +%s) - t )) s"
    else
        log "docker kill (SIGKILL)"; docker kill "$AGENT" >/dev/null
    fi
    call_bg "$NEW_CALL" "nouvel appel, agent arrêté"
    wait
    watch_status 30
    log "redémarrage de l'agent"; t=$(date +%s); docker start "$AGENT" >/dev/null
    until status | grep -q '^HEALTHY'; do sleep 5; done
    log "HEALTHY $(( $(date +%s) - t )) s après le redémarrage"
    call_bg "$NEW_CALL" "appel après reprise"; wait
    ;;
net-cut)
    call_bg "$SLOW" "appel long 60 s"
    sleep 15
    log "coupure Internet de l'agent (réseau local conservé)"
    netshoot "iptables -I $CUT"
    call_bg "$NEW_CALL" "nouvel appel, lien coupé"
    watch_status 90
    log "rétablissement du lien"; t=$(date +%s)
    netshoot "iptables -D $CUT"
    wait
    until status | grep -q '^HEALTHY'; do sleep 5; done
    log "HEALTHY $(( $(date +%s) - t )) s après le rétablissement"
    call_bg "$NEW_CALL" "appel après reprise"; wait
    ;;
netem)
    log "netem : 200 ms de latence, 5 % de pertes"
    netshoot "tc qdisc add dev eth0 root netem delay 200ms loss 5%"
    call_bg "call DCP_POC.APPS.NET_PING(20)" "NET_PING sous netem"; wait
    netshoot "tc qdisc del dev eth0 root"
    log "netem retiré"
    ;;
pg-stop)
    docker compose -f local/docker-compose.yml stop postgres >/dev/null; log "postgres arrêté"
    call_bg "call DCP_POC.APPS.PG_QUERY('select 1')" "PG_QUERY, base arrêtée"; wait
    log "proxy: $(status)"
    docker compose -f local/docker-compose.yml start postgres >/dev/null; log "postgres redémarré"
    ;;
*) echo "scénario inconnu : $S"; exit 1 ;;
esac
log "=== fin ; état final : $(status)"
