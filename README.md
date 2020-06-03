# Safechain

Safechain is a wrapper to load `iptables` chain rules in a safe, atomic, idempotent way.  Any syntax errors are caught before the updated chain is taken live, so a mistake does not take down a running firewall setup.

As Safechain is a wrapper around `iptables`, converting a manual `iptables` setup to Safechain is mostly a matter of replacing `iptables -A` with `sc_add_rule`.

## Example

In this brief example, files will be placed in `/etc/safechain` to protect the INPUT chain of the filter table, using a new chain called host_ingress.

### host.sh

This is where the bulk of the logic will go.  `host.sh` runs are idempotent and zero-downtime.  If any errors occur while running `host.sh`, the previous rules for host_ingress will remain live until the problem is fixed.

In this example, only host_ingress is created (and only IPv4; see below about IPv6 support), but in a more complete implementation, it would be expected this file would cover both host_ingress and host_egress, IPv4 and IPv6, etc.

```bash
#!/bin/sh

set -e

. /etc/safechain/safechain.sh

# host_ingress chain preprocessing
sc_preprocess host_ingress

# Allow ICMP
sc_add_rule host_ingress -p icmp -j ACCEPT

# Allow all inbound traffic from the LAN
sc_add_rule host_ingress -i eth1 -j ACCEPT

# Allow certain services
sc_add_rule host_ingress -p tcp --dport 80 -j ACCEPT
sc_add_rule host_ingress -p tcp --dport 443 -j ACCEPT

# Allow SSH from trusted host
sc_add_rule host_ingress -s 10.2.8.3 -p tcp --dport 22 -j ACCEPT

# Drop all other traffic
sc_add_rule host_ingress -j LOG --log-prefix "BAD-host-in: "
sc_add_rule host_ingress -j DROP

# host_ingress chain postprocessing
# Goes live here if all went well
sc_postprocess host_ingress
```

### firewall.sh

This file contains the prep needed for the host_ingress chain.  It should have as little logic in it as possible, so there is less to change over time and therefore less to go wrong.  As much as possible should instead be in `host.sh`.  `firewall.sh` is designed to be idempotent but not zero-downtime, as it will flush everything.

```bash
#!/bin/sh

set -e

# Temporarily set default policy to accept
iptables -w -P INPUT ACCEPT

# Flush all standard chains
iptables -w -F INPUT

# Allow everything to localhost
iptables -w -A INPUT -i lo -j ACCEPT

# Allow established connections
iptables -w -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# Set default policy to drop
iptables -w -P INPUT DROP

# Host traffic
iptables -w -N host_ingress 2>/dev/null || iptables -w -F host_ingress
iptables -w -A INPUT -j host_ingress

# Log uncaught stuff
iptables -w -A INPUT -j LOG --log-prefix "BAD-in: "
iptables -w -A INPUT -j DROP
```

### firewall-wrapper.sh

This file will be used to call `firewall.sh`, which does the initial setup, then `host.sh` which has the INPUT rules.  It is designed to be idempotent but not zero-downtime (as `firewall.sh` will flush everything).

```bash
#!/bin/sh

set -e

/etc/safechain/firewall.sh
/etc/safechain/host.sh
```

### Running

Manually running host.sh produces output similar to:
```
$ sudo /etc/safechain/host.sh
[11:22:32.258135899] host_ingress (v4): Running sanity checks
[11:22:32.268278052] host_ingress (v4): Creating new chain
[11:22:32.288724263] host_ingress: Populating new chain....... 44 rules added
[11:22:32.446200284] host_ingress (v4): Making new chain live
[11:22:32.456034349] host_ingress (v4): Removing old chain
[11:22:32.464661618] host_ingress (v4): Done!
```

An example `safechain-firewall.service` systemd service is also provided which could be used to run `firewall-wrapper.sh` upon boot.

## IPv6 support

Safechain has full support for IPv6 using `ip6tables`.  The `sc_preprocess`, `sc_postprocess` and `sc_add_rule` commands have IPv6 equivalents, `sc6_preprocess`, `sc6_postprocess` and `sc6_add_rule`.

For situations where the IPv4 and IPv6 commands are otherwise the same, there are `sc46_preprocess`, `sc46_postprocess` and `sc46_add_rule` commands.  `sc46_add_rule` itself is of limited use, as it can only be used for rules which do not reference addresses/networks.

## About

Copyright (C) 2013-2020 Canonical Ltd., Ryan Finnie

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this program.  If not, see
<https://www.gnu.org/licenses/>.
