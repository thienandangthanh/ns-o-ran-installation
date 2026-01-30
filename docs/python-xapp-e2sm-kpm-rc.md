## Python xApp (Bronze) with E2SM-KPM subscribe + E2SM-RC control

This doc describes the **real near-RT RIC xApp mode** for traffic steering:
- ns-3 emits **E2SM-KPM** indications over **E2AP**
- xApp sends **E2SM-RC** control (handover) over **E2AP**
- the xApp policy is implemented in **Python**, running inside the Bronze stack as a container.

### Components in this repo

- **xApp container image** (new):
  - Dockerfile: `colosseum-near-rt-ric/setup/ts-xapp/Dockerfile`
  - Policy server: `colosseum-near-rt-ric/setup/ts-xapp/policy_server.py`
  - Entrypoint: `colosseum-near-rt-ric/setup/ts-xapp/run_ts_xapp.sh`
- **Connector** (C++):
  - Source: `colosseum-near-rt-ric/setup/ts-xapp-connector/src/`
  - It uses RMR for transport and builds E2AP PDUs + E2SM-RC payloads.
- **Setup script**:
  - `colosseum-near-rt-ric/setup-scripts/setup-ts-xapp.sh`

### Run order (on the VM)

#### 1) Start Bronze near-RT RIC

```bash
cd ~/ns-O-RAN-installation/colosseum-near-rt-ric/setup-scripts
./setup-ric-bronze.sh
```

#### 2) Start the TS xApp container

```bash
cd ~/ns-O-RAN-installation/colosseum-near-rt-ric/setup-scripts
./setup-ts-xapp.sh
```

This builds the `ts-xapp` image (first time) and runs it on the `ric` Docker network using `XAPP_IP` from `setup-lib.sh`.

#### 3) Run ns-3 toward the RIC (E2 mode)

In a separate terminal:

```bash
cd ~/ns-O-RAN-installation/ns-3-mmwave-oran

./ns3 run scratch/scenario-one.cc -- \
  --enableE2FileLogging=false \
  --e2TermIp=10.0.2.10 \
  --useSemaphores=false
```

Notes:
- `enableE2FileLogging=false` is required so ns-3 actually talks E2AP/E2SM to the RIC.
- `useSemaphores` is a Gym-mode mechanism; you typically disable it in xApp mode.

### What “works” means (minimum verification)

- xApp sends `RIC_SUB_REQ` for KPM and receives `RIC_INDICATION` messages.
- xApp sends `RIC_CONTROL_REQ` with E2SM-RC control header/message.
- ns-3 logs show `ControlMessageReceivedCallback` on the LTE eNB and performs HO for the decoded IMSI.

### Current status

The connector implements:
- E2SM-RC encoding for handover control (Format1 control header + control message)
- E2AP encode/decode for:
  - subscription request (KPM)
  - control request (RC)
  - indication message extraction

The Python policy is still a **demo policy** (not PPO/CQL/REM). Next iterations will:
- decode KPM contents into a structured observation,
- implement a real policy inference path (load SB3 model),
- add proper evaluation KPIs in xApp mode.

