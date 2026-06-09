## Docker Engine

https://docs.docker.com/engine/install/ubuntu/#uninstall-docker-engine

## ns-3 prerequisites
https://www.nsnam.org/docs/installation/html/quick-start.html#prerequisites
```
sudo apt install -y cmake make
```

## tshark - Wireshark CLI

We use `tshark` (CLI) since we work in the terminal. Install Wireshark (GUI) later only when a human needs to inspect packets manually.

Ref: https://www.geeksforgeeks.org/linux-unix/how-to-install-and-use-wireshark-on-ubuntu-linux/

```bash
# 1. Install from the official Wireshark PPA (newer than Ubuntu's repo)
sudo add-apt-repository ppa:wireshark-dev/stable
sudo apt update
sudo apt install -y tshark
# When prompted "Should non-superusers be able to capture packets?" → choose <Yes>
```

```bash
# 2. Allow capture without sudo: add your user to the 'wireshark' group
sudo usermod -aG wireshark $USER
# Log out / back in (or run `newgrp wireshark`) for the group to take effect
```

```bash
# 3. Verify
tshark --version
tshark -D            # list capture interfaces (no sudo needed if step 2 worked)
```

If step 1's prompt was missed, re-run: `sudo dpkg-reconfigure wireshark-common`.

## E2SM L-release: asn1c type archive for ns-3 oran-interface (REQUIRED)

The OSC e2sim install (`libe2sim_shared.so` / `libe2sim.a` under `/usr/local/lib`)
ships the runtime (SCTP/encoding/messaging) but does **not** bundle the
asn1c-generated type definitions (`asn_DEF_*`, `asn_encode_to_new_buffer`,
`xer_fprint`, `aper_*`, …). Those symbols are `U` (undefined) in both installed
libs, so the ns-3 `oran-interface` module fails to link with hundreds of
undefined references.

Fix — compile the asn1c sources into a separate static archive once, after the
e2sim install:

```bash
cd /home/uc/osc-installation/e2-interface/e2sim/asn1c   # asn1c *.c source dir
gcc -O2 -fPIC -I. -c *.c
sudo ar rcs /usr/local/lib/libasn1c_e2.a *.o
rm -f *.o
```

`oran-interface/CMakeLists.txt` links `/usr/local/lib/libasn1c_e2.a` after
`libe2sim_shared.so` (link order matters: archive resolves the shared lib's
undefined refs). The CMake config FATAL-errors with this exact recipe if the
archive is missing.
