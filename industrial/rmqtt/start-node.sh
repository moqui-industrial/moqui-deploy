#!/bin/sh
# Starts one RMQTT node: start-node.sh <node id 1..3>
#
# Node 1 creates the Raft cluster on the very first start. Nodes 2 and 3 must not start before a leader exists:
# a node that starts without finding one panics, and nodes that crash and restart while they join leave the cluster
# without quorum for good. So they wait until another node reports itself running with a leader. This also holds
# when node 1 is down for good: a restarting node 2 joins the leader found on node 3.
set -u
ID="$1"
API=/app/rmqtt/rmqtt-plugins/rmqtt-http-api.toml
TOKEN="$(sed -n 's/^http_bearer_token *= *"\(.*\)"/\1/p' "$API")"

if [ "$ID" != 1 ]; then
  echo "[start-node] node $ID waits for a node with a leader"
  while :; do
    for peer in 1 2 3; do
      [ "$peer" = "$ID" ] && continue
      out="$(wget -q -T 3 -O - --header "Authorization: Bearer $TOKEN" "http://rmqtt$peer:6060/api/v1/health/check/$peer" 2>/dev/null)"
      case "$out" in
        *'"running":true'*'"leader_id":'[1-9]*) echo "[start-node] node $peer has a leader: starting node $ID"; break 2 ;;
      esac
    done
    sleep 2
  done
fi
exec /app/rmqtt/rmqtt-bin/rmqttd -f /app/rmqtt/rmqtt.toml --id "$ID"
