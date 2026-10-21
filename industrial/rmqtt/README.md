# RMQTT: redundant MQTT broker for Compose and Swarm

A replacement for the Artemis broker of `activemq-compose.yml` and `activemq-stack.yml` for the clients that speak
MQTT (the device gateway and the PLC firmware use `paho-mqtt5` / MQTT 5 on port 1883 only).
[RMQTT](https://github.com/rmqtt/rmqtt) is an MQTT 3.1.1 and 5 broker written in Rust.

| File | Use |
|---|---|
| `../rmqtt-compose.yml` | Docker Compose: three broker nodes, authentication service, HAProxy |
| `../rmqtt-stack.yml` | Docker Swarm stack, same components, one broker node per labelled host |
| `rmqtt.toml`, `rmqtt-*.toml` | Broker configuration (derived from the files of the image `rmqtt/rmqtt:0.24.0`) |
| `haproxy.cfg` | One endpoint in front of the nodes |
| `start-node.sh` | Starts a node; nodes 2 and 3 wait until another node has a leader |
| `auth/auth-server.py`, `auth/users.json` | Login and topic permissions (`rmqtt-auth-http` plugin) |
| `test-rmqtt.sh` | Acceptance test: routing, login, persistence, failures (Compose and Swarm) |

## Run

```sh
cd industrial
docker compose -f rmqtt-compose.yml up -d          # stop the Artemis compose first: both want port 1883
docker compose -f rmqtt-compose.yml ps
rmqtt/test-rmqtt.sh compose                         # optional, restarts nodes: use a cluster you can disturb
```

Swarm: label the nodes, create the configs and the secret, deploy (the exact commands are in the header of
`rmqtt-stack.yml`). Clients use `tcp://moqui-rmqtt:1883` on the network `moqui-rmqtt_brokernet`; the alias
`moqui-broker1` is kept, so clients configured for the Artemis broker (`tcp://moqui-broker1:1883`) only need to join
that network.

Default user: `artemis` / `artemis` (the same as Artemis, so no client has to change). **Change it** in
`auth/users.json` (Compose: the file is read again when it changes; Swarm: create a new secret version) and the API
token in `rmqtt-http-api.toml` (`http_bearer_token`) before exposing the broker.

## What Artemis gave and what this does

| Artemis (`activemq-*.yml`) | RMQTT here |
|---|---|
| MQTT 3.1, 3.1.1 and 5 on 1883 | MQTT 3.1.1 and 5 on 1883, through HAProxy |
| Journal on disk with `journal-datasync` (fsync before the acknowledgement), sessions and messages survive a restart | `rmqtt-session-storage` with `sled` on a volume per node: sessions, subscriptions, offline and in-flight messages come back after a restart; retained messages in `sled` too (`rmqtt-retainer`) |
| Session and message expiry of 2 days | `session_expiry_interval`, `max_session_expiry_interval`, `message_expiry_interval` = 2 days |
| Primary and backup with replication (`ha-policy`), automatic failover | Three nodes in a Raft cluster (`rmqtt-cluster-raft`): routing, subscriptions and retained messages are replicated, the cluster serves while two of three nodes are up; HAProxy sends clients to a live node |
| Login `artemis`, role `amq` with every permission | `rmqtt-auth-http` with `auth/auth-server.py`: users, superusers, publish and subscribe filters per user; anonymous login off; the built-in ACL ends with `deny all` |
| Large messages | packet size up to 10 MB |
| Shared subscriptions (`$share/...`) | `rmqtt-shared-subscription` |
| Console and metrics (8161, Jolokia) | HTTP API and dashboard on 6060 (`/dashboard/`), Prometheus at `/api/v1/metrics/prometheus` |
| Dead letter and expiry queues | not available |
| JMS/CORE (61616), AMQP (5672), STOMP, OpenWire | not supported: RMQTT speaks MQTT only. Nothing in moqui-deploy uses them; check your own clients before switching |

## How redundancy and persistence work, and their limits

- **Persistence is per node.** The session store lives on the node that holds the client's connection, in the
  volume of that node. After a restart of that node (or of the whole cluster) the sessions come back. RMQTT does not
  document moving a persistent session to another node: if a node stays down, its clients can reconnect through
  HAProxy to another node and continue with a new session there, without the offline messages that waited on the
  failed node. Keep the node volumes on reliable storage and bring a failed node back (Swarm restarts it; pin it to
  its host with the labels, or use a volume driver that follows the task).
- **Disk writes are periodic, not before the acknowledgement.** Artemis is configured with `journal-datasync`; the
  `sled` store of RMQTT is flushed in the background. In the test, a QoS 1 message that was published to an offline
  persistent session and acknowledged was lost in 3 of 6 trials when the node was stopped immediately after, even with a
  graceful stop (`docker stop`), and never when the stop came 2 seconds later. Plan for a window of about a second:
  data that must not be lost has to be written by the sender again when no confirmation of the processing arrives (the
  device gateway stores to the database; MQTT QoS 1 only confirms that the broker took the message).
- **HAProxy keeps a client on the same node** (source address hash) while that node is up, so a persistent session finds
  its stored state again.
- **The cluster needs two of three nodes.** With two nodes down the remaining one cannot elect a leader.
- **Node 1 creates the cluster** (`leader_id = 1` in `rmqtt-cluster-raft.toml`). Nodes 2 and 3 do not start
  before another node reports a leader (`start-node.sh`: a node that starts without finding a leader panics, and nodes
  that crash and restart while joining leave the cluster without quorum for good; this showed up in Swarm, where all
  services start together). A node that starts while a leader exists always joins it as follower, so restarting node 1
  later is safe. With `leader_id = 0` a cold start of three nodes together can end with two leaders.
- **No TLS yet.** The image ships a certificate whose private key is public, so the TLS, WebSocket and QUIC listeners
  were removed from `rmqtt.toml`. To add TLS, mount your own certificate and key and add `listener.tls.external.*`
  keys (see the comments of the image's `rmqtt.toml`), also for the connections between HAProxy and the nodes if needed.
- **Raft and gRPC ports** (6003, 5363) are used inside the broker network only: do not publish them.
- **Message storage** (`rmqtt-message-storage`, which keeps published messages for later subscribers) is off: it needs
  Redis for persistence and Artemis did not do this either. Enable it with a Redis service if you need it.

## Tests

```sh
python3 -m unittest industrial/rmqtt/auth/test_auth_server.py     # the authentication service
rmqtt/test-rmqtt.sh compose                                        # the cluster, see the script header
```

`test-rmqtt.sh` checks: three nodes running; the API refuses a request without token; anonymous and wrong-password
connections are refused, MQTT 3.1.1 and 5 logins work; a message published on node 1 reaches a subscriber on node 3,
through HAProxy, and through a shared subscription; QoS 1 messages published while a persistent session is offline
are delivered after the node of that session is restarted; a retained message is read on another node and is still
served with node 1 down; publish and subscribe work through HAProxy with one node down and the node rejoins; after
stopping and starting the whole cluster the retained message and the offline message of a persistent session are still there.
