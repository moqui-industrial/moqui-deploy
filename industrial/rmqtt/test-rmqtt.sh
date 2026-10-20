#!/usr/bin/env bash
# Acceptance test of the RMQTT cluster (Compose or Swarm). It starts throw-away mosquitto client containers on the
# broker network and kills and restarts broker nodes: run it only on a cluster you can disturb.
#
#   Compose:  docker compose -f rmqtt-compose.yml up -d
#             rmqtt/test-rmqtt.sh compose
#   Swarm:    docker stack deploy -c rmqtt-stack.yml moqui-rmqtt   (see rmqtt-stack.yml)
#             rmqtt/test-rmqtt.sh swarm
#
# Environment: NETWORK (default moqui-rmqtt_brokernet), STACK (swarm stack name, default moqui-rmqtt),
#              MQTT_USER / MQTT_PASSWORD (default artemis / artemis), API_TOKEN (default moqui-rmqtt),
#              CLIENT_IMAGE (default eclipse-mosquitto:2).
# Run it where the docker CLI talks to the engine that runs the cluster (for Swarm, on a manager node).
set -uo pipefail

MODE="${1:-compose}"
NETWORK="${NETWORK:-moqui-rmqtt_brokernet}"
STACK="${STACK:-moqui-rmqtt}"
MQTT_USER="${MQTT_USER:-artemis}"
MQTT_PASSWORD="${MQTT_PASSWORD:-artemis}"
API_TOKEN="${API_TOKEN:-moqui-rmqtt}"
CLIENT_IMAGE="${CLIENT_IMAGE:-eclipse-mosquitto:2}"
RUN_ID="$(date +%s)"

pass=0; fail=0
ok()   { pass=$((pass + 1)); printf '  PASS  %s\n' "$*"; }
bad()  { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
section() { printf '\n== %s\n' "$*"; }

# container id of broker node N (1..3)
node_container() {
  if [[ "$MODE" == swarm ]]; then docker ps -q -f "name=${STACK}_rmqtt$1\." | head -1
  else docker ps -q -f "name=^moqui-rmqtt$1\$" | head -1; fi
}
# a mosquitto client command on the broker network; host is the first argument
mq() { docker run --rm --network "$NETWORK" "$CLIENT_IMAGE" "$@"; }
pub() { local host="$1"; shift; mq mosquitto_pub -h "$host" -u "$MQTT_USER" -P "$MQTT_PASSWORD" "$@"; }
sub() { local host="$1"; shift; mq mosquitto_sub -h "$host" -u "$MQTT_USER" -P "$MQTT_PASSWORD" "$@"; }
api() { docker exec "$(node_container "${2:-1}")" wget -q -O - --header "Authorization: Bearer $API_TOKEN" "http://127.0.0.1:6060$1" 2>/dev/null; }

nodes_running() { # number of nodes the cluster reports as running (asked to node $1)
  api /api/v1/health/check "${1:-1}" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(sum(1 for n in d["nodes"] if n["running"]))' 2>/dev/null || echo 0
}
wait_nodes() { # wait until the cluster has $1 running nodes
  local want="$1" i
  for i in $(seq 1 60); do [[ "$(nodes_running 1)" == "$want" || "$(nodes_running 2)" == "$want" ]] && return 0; sleep 2; done
  return 1
}
wait_node_container() { local i; for i in $(seq 1 60); do [[ -n "$(node_container "$1")" ]] && return 0; sleep 2; done; return 1; }
wait_broker() { # wait until $1 accepts an authenticated connection
  local i; for i in $(seq 1 60); do pub "$1" -t "test/$RUN_ID/ping" -m ping -q 1 >/dev/null 2>&1 && return 0; sleep 2; done; return 1
}
stop_node()  { if [[ "$MODE" == swarm ]]; then docker kill "$(node_container "$1")" >/dev/null; else docker stop -t 2 "$(node_container "$1")" >/dev/null; fi; }
start_node() { if [[ "$MODE" == swarm ]]; then wait_node_container "$1"; else docker start "moqui-rmqtt$1" >/dev/null; fi; }
restart_node() { stop_node "$1"; start_node "$1"; }

section "Cluster"
check "three nodes running" wait_nodes 3
check "API refuses a request without the token" bash -c "! docker exec $(node_container 1) wget -q -O - http://127.0.0.1:6060/api/v1/health/check >/dev/null 2>&1"
for n in 1 2 3; do wait_broker "rmqtt$n"; done

section "Authentication"
check "anonymous connection refused" bash -c "! docker run --rm --network $NETWORK $CLIENT_IMAGE mosquitto_pub -h rmqtt1 -t test/anon -m x -q 1 -W 5 >/dev/null 2>&1"
check "wrong password refused" bash -c "! docker run --rm --network $NETWORK $CLIENT_IMAGE mosquitto_pub -h rmqtt1 -u $MQTT_USER -P wrong-$RUN_ID -t test/bad -m x -q 1 >/dev/null 2>&1"
check "valid user accepted (MQTT 3.1.1)" pub rmqtt1 -t "test/$RUN_ID/auth" -m ok -q 1
check "valid user accepted (MQTT 5)" pub rmqtt2 -V mqttv5 -t "test/$RUN_ID/auth5" -m ok -q 1

section "Routing across nodes"
T="test/$RUN_ID/route"
out="$(mktemp)"; sub rmqtt3 -t "$T" -q 1 -C 1 -W 20 > "$out" 2>&1 &
sp=$!; sleep 3; pub rmqtt1 -t "$T" -m from-node1 -q 1; wait "$sp"
check "published on node 1, received on node 3" grep -qx from-node1 "$out"
out="$(mktemp)"; sub moqui-rmqtt -t "$T/lb" -q 1 -C 1 -W 20 > "$out" 2>&1 &
sp=$!; sleep 3; pub moqui-rmqtt -t "$T/lb" -m through-balancer -q 1; wait "$sp"
check "publish and subscribe through the balancer" grep -qx through-balancer "$out"
out="$(mktemp)"; sub rmqtt2 -t '$share/g1/test/'"$RUN_ID"'/shared' -q 1 -C 1 -W 20 > "$out" 2>&1 &
sp=$!; sleep 3; pub rmqtt1 -t "test/$RUN_ID/shared" -m shared-ok -q 1; wait "$sp"
check "shared subscription" grep -qx shared-ok "$out"

section "Persistent session survives a node restart"
CID="persist-$RUN_ID"; T="test/$RUN_ID/persist"
sub rmqtt2 -i "$CID" -c -t "$T" -q 1 -C 1 -W 3 >/dev/null 2>&1   # create the session and the subscription, then go offline
for i in 1 2 3; do pub rmqtt1 -t "$T" -m "offline-$i" -q 1; done
# sled writes the session store to disk periodically: a node stopped less than a second after the last message may
# lose it even after a graceful stop (see "limits" in rmqtt/README.md), so the test waits before the restart
sleep 3
restart_node 2; wait_nodes 3; wait_broker rmqtt2
out="$(mktemp)"; sub rmqtt2 -i "$CID" -c -t "$T" -q 1 -C 3 -W 20 > "$out" 2>&1
check "offline QoS 1 messages delivered after the node restarted" test "$(grep -c '^offline-' "$out")" -eq 3
[[ "$(grep -c '^offline-' "$out")" -eq 3 ]] || { echo "        received: $(tr '\n' ' ' < "$out")"; }

section "Retained messages"
T="test/$RUN_ID/retained"
pub rmqtt1 -t "$T" -m retained-value -q 1 -r
out="$(mktemp)"; sub rmqtt3 -t "$T" -C 1 -W 10 > "$out" 2>&1
check "retained message read on another node" grep -qx retained-value "$out"
stop_node 1; wait_nodes 2
out="$(mktemp)"; sub moqui-rmqtt -t "$T" -C 1 -W 20 > "$out" 2>&1
check "retained message still served with node 1 down" grep -qx retained-value "$out"

section "One node down"
check "cluster reports two running nodes" test "$(nodes_running 2)" -eq 2
T="test/$RUN_ID/degraded"
out="$(mktemp)"; sub moqui-rmqtt -t "$T" -q 1 -C 1 -W 25 > "$out" 2>&1 &
sp=$!; sleep 3; pub moqui-rmqtt -t "$T" -m with-two-nodes -q 1; wait "$sp"
check "publish and subscribe through the balancer with one node down" grep -qx with-two-nodes "$out"
start_node 1; check "node 1 rejoins the cluster" wait_nodes 3; wait_broker rmqtt1

section "Whole cluster restart"
T="test/$RUN_ID/after-restart"; CID="persist2-$RUN_ID"
pub rmqtt3 -t "$T/retained" -m kept-over-restart -q 1 -r
sub rmqtt2 -i "$CID" -c -t "$T/session" -q 1 -C 1 -W 3 >/dev/null 2>&1
pub rmqtt3 -t "$T/session" -m offline-before-restart -q 1
for n in 1 2 3; do stop_node "$n"; done
for n in 1 2 3; do start_node "$n"; done
check "three nodes running again" wait_nodes 3
for n in 1 2 3; do wait_broker "rmqtt$n"; done
out="$(mktemp)"; sub moqui-rmqtt -t "$T/retained" -C 1 -W 20 > "$out" 2>&1
check "retained message survived" grep -qx kept-over-restart "$out"
out="$(mktemp)"; sub rmqtt2 -i "$CID" -c -t "$T/session" -q 1 -C 1 -W 20 > "$out" 2>&1
check "offline message of a persistent session survived" grep -qx offline-before-restart "$out"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
exit $(( fail > 0 ? 1 : 0 ))
