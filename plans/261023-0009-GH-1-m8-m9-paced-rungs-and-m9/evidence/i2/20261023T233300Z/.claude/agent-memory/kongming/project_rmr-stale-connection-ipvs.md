---
name: rmr-stale-connection-ipvs
description: On the L testbed (VM oran-kvm-2404) kube-proxy is IPVS mode; RMR SI95 senders keep dead TCP endpoints after an xApp pod/Service replacement (rtmgr ruling 6, a1mediator L finding 4)
metadata:
  type: project
---
On VM oran-kvm-2404 (k8s 1.33, kube-proxy `mode: ipvs`, `ipvs.tcpTimeout: 0s` = 900 s idle expiry), an RMR SI95 sender (RMR 4.9.x, no SO_KEEPALIVE / TCP_USER_TIMEOUT, endpoint fd cached across route tables) silently loses messages after the receiving xApp's pod or Service is replaced. The case where the Service was deleted was observed 2026-10-23 (gate i2 run 3): the black hole lasted about 15.5 min, until `tcp_retries2=15` aborted the socket. RMR logs "message sent" and `succ++` throughout.

**Why:** IPVS frees an idle conn after 900 s, so the old pod's FIN is never reverse-NATed. A deleted ClusterIP leaves `kube-ipvs0` and is routed off the VM. With the Service kept and an idle conn, the next segment is predicted (not observed) to get a local RST instead, losing one message.

**How to apply:** when an xApp is replaced, every long-lived RMR sender towards it (rtmgr, a1mediator) must be restarted afterwards: a pod delete, in the order a1mediator → rtmgr. Never trust RMR send success as delivery; check the sender's /proc/net/tcp (tx_queue, retrnsmt) and `/proc/net/ip_vs_conn`. Report: plans/reports/kongming-261024-0840-GH-1-p5-i2-a1mediator-stale-ts-connection.md. Related: [[ruling-6-rtmgr-restart]].
