#cloud-config
# This file allows cloud-init to autoconfigure fw0 for a high-availability router/firewall
autoinstall:
  version: 1
  refresh-installer:
    update: no
  network:
    version: 2
    ethernets:
      # Fastboot marks all ethernet and macvlan interfaces optional and disables DHCP
      # WARNING: This will break applications that need functional interfaces at boot!
      fastboot:
        match: {name: "en*|mv*"}
        optional: true
        dhcp4: no
        dhcp6: no
      # Create pseudonyms for wan, lan, and direct connection interfaces
      wan0:
        match: {name: "enp1s0"}
        set-name: wan0
        addresses:
          - 192.168.1.19/24
        routes:
          - to: 0.0.0.0/0
            via: 192.168.1.254
        nameservers:
          addresses:
            - 1.1.1.3
            - 1.0.0.3
      lan0:
        match: {name: "enp2s0"}
        set-name: lan0
        addresses:
          - 10.0.0.3/24
      direct0:
        match: {name: "enp3s0"}
        set-name: direct0
        addresses:
          - 172.16.0.2/24
  ssh:
    install-server: yes
    allow-pw: no
  packages:
    - net-tools
    - chrony
    - keepalived
    - kea
    - radvd
    - postfix
    - conntrackd
    - ufw-
    - iptables-
  updates: security
  shutdown: reboot
  user-data:
    hostname: fw1
    disable_root: true
    users:
      - name: bhook
        gecos: "Bradley Hook"
        groups: [adm, sudo]
        passwd: $6$5Dt0QywV29Hd55gw$KKZtcp9yC9es3lg7bnGnuVk.JGqyg3/giwarwLeRGgI0fpgtanzFHzkchVHvCmTXkXfwvM1fGt8k5rRvRn9Ck0
        lock_passwd: false
        shell: /bin/bash
        ssh_import_id:
          - lp:bradley-coder7
    runcmd:
      - if [ ! -f /etc/conntrackd/primary-backup.sh ]; then cp /usr/share/doc/conntrackd/examples/sync/primary-backup.sh /etc/conntrackd/; fi
      - if [ -f /etc/nftables.conf ]; then systemctl enable nftables.service; systemctl start nftables.service; fi
      - if [ -f /etc/sysctl.d/50-custom-overrides.conf ]; then sysctl --system; fi
    write_files:
      - path: /usr/local/etc/keepalived/scripts/notify.sh
        permissions: '0744'
        content: |
          #!/bin/bash
          # Process CLI arguments
          # By default, keepalived will send us 4 arguments, in addition to anything we
          # include when invoking the script
          # The last four arguments are:
          #       <GROUP|INTERFACE>
          #       <name>
          #       <MASTER|BACKUP|FAULT|STOP|DELETED>
          #       <priority>
          if (( $# < 4 )); then
                  echo "Not enough options";
                  exit 1;
          fi
          vrrp_type="${@:$#-3:1}" # Grab the 4th-from-last argument
          vrrp_name="${@:$#-2:1}" # Grab the 3rd-from-last argument
          vrrp_state="${@:$#-1:1}" # Grab the 2nd-from-last argument
          vrrp_priority="${@:$#}" # Grab the last argument
          
          # If the interface or group name is NOT "G1", then exit
          if [[ "$vrrp_name" != "G1" ]]; then exit; fi
          
          # See if the previous_state file exists, and create it if needed
          if [ -f /tmp/keepalived.previous_state ]; then
                  vrrp_previous_state=$(</tmp/keepalived.previous_state);
                  echo "$vrrp_previous_state found as previous state"
          else
                  echo $vrrp_state > /tmp/keepalived.previous_state;
                  exit;
          fi
          
          # Write the target state
          echo $vrrp_state > /tmp/keepalived.previous_state;
          
          # Try to match for a MASTER to BACKUP transition; if found, reload
          if [[ "${vrrp_previous_state}BACKUP" == "MASTER${vrrp_state}" ]]; then
                  echo "reloading due to MASTER > BACKUP state change"
                  systemctl reload keepalived.service;
          fi
      - path: /etc/keepalived/keepalived.conf
        content: |
          global_defs {
            router_id ${_INSTANCE}
            dynamic_interfaces allow_if_changes
            vrrp_strict
            enable_script_security
            script_user root
          }
          vrrp_sync_group G1 {
            group {
              vrrpwan0
              vrrplan0
            }
            notify_master "/etc/conntrackd/primary-backup.sh primary"
            notify_backup "/etc/conntrackd/primary-backup.sh backup"
            notify_fault "/etc/conntrackd/primary-backup.sh fault"
            @fw1 notify "/usr/local/etc/keepalived/scripts/notify.sh"
          }
          vrrp_instance vrrpwan0 {
            state BACKUP
            priority 128
            advert_int .1
            version 3
            interface wan0
            virtual_router_id 1
            use_vmac vrrpwan0
            virtual_ipaddress {
              192.168.1.20/24
            }
          }
          vrrp_instance vrrplan0 {
            state BACKUP
            priority 128
            advert_int .1
            version 3
            interface lan0
            virtual_router_id 2
            use_vmac vrrplan0
            virtual_ipaddress {
              10.0.0.1/24
            }
          }
          static_routes {
            @fw0 192.168.1.19/32 dev vrrpwan0 metric 50
            @fw0 10.0.0.3/32 dev vrrplan0 metric 50
            @fw1 192.168.1.18/32 dev vrrpwan0 metric 50
            @fw1 10.0.0.2/32 dev vrrplan0 metric 50
            0.0.0.0/0 table 1000 nexthop via 192.168.1.254 dev vrrpwan0 onlink
            192.168.1.0/24 dev vrrpwan0 table 1000 metric 100
            10.0.0.0/24 dev vrrplan0 table 1000 metric 100
          }
          static_rules {
            # Use the main table for traffic from/to this machine -- should probably be in netplan
            from 192.168.1.19 table 254 priority 500
            to 192.168.1.19 table 254 priority 501
            from 10.0.0.2 table 254 priority 502
            to 10.0.0.2 table 254 priority 503
            from 172.16.0.1 table 254 priority 504
            to 172.16.0.1 table 254 priority 505
            # Use table 1000 for everything else
            from 0.0.0.0/0 table 1000 priority 1000
          }
      - path: /etc/systemd/system/kea-dhcp4-server.service.d/10-override.conf
        content: |
          [Service]
          Restart=on-failure
          RestartSec=5
      - path: /etc/kea/kea-ctrl-agent.conf
        content: |
          {
            "Control-agent": {
              "http-host": "172.16.0.2",
              "http-port": 8000,
              "control-sockets": {
                "dhcp4": {
                  "socket-type": "unix",
                  "socket-name": "/tmp/kea4-ctrl-socket"
                },
                "dhcp6": {
                  "socket-type": "unix",
                  "socket-name": "/tmp/kea-dhcp6-ctrl.sock"
                }
              }
            }
          }
      - path: /etc/kea/kea-dhcp4.conf
        content: |
          {
            "Dhcp4": {
            "authoritative": true,
              "store-extended-info": true,
              "lease-database": {
                "type": "memfile",
                "persist": true,
                "name": "/var/lib/kea/kea-leases4.csv",
                "lfc-interval": 1800,
                "max-row-errors": 100
              },
              "hooks-libraries": [
                {
                  "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_lease_cmds.so",
                  "parameters": {}
                },
                {
                  "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_ha.so",
                  "parameters": {
                    "high-availability": [{
                       "this-server-name": "fw1",
                       "mode": "hot-standby",
                       "heartbeat-delay": 1000,
                       "max-response-delay": 2000,
                       "max-ack-delay": 5000,
                       "max-unacked-clients": 0,
                       "max-rejected-lease-updates": 1,
                       "peers": [
                         {
                           "name": "fw0",
                           "url": "http://172.16.0.1:8000/",
                           "role": "primary",
                           "auto-failover": true
                         },
                         {
                           "name": "fw1",
                           "url": "http://172.16.0.2:8000/",
                           "role": "standby",
                           "auto-failover": true
                         }
                       ]
                    }]
                  }
                }
              ],
              "interfaces-config": {
                "interfaces": ["lan0"]
              },
              "control-socket": {
                "socket-type": "unix",
                "socket-name": "/tmp/kea4-ctrl-socket"
              },
              "expired-leases-processing": {
                "reclaim-timer-wait-time": 10,
                "flush-reclaimed-timer-wait-time": 25,
                "hold-reclaimed-time": 360,
                "max-reclaim-leases": 50,
                "max-reclaim-time": 250,
                "unwarned-reclaim-cycles": 5
              },
              "renew-timer": 90,
              "rebind-timer": 180,
              "valid-lifetime": 360,
              "option-data": [
                {
                  "name": "domain-name-servers",
                  "data": "1.1.1.3,1.0.0.3"
                },
                {
                  "name": "domain-search",
                  "data": "example.com"
                }
              ],
              "subnet4": [
                {
                  "id": 1,
                  "interface": "lan0",
                  "subnet": "10.0.0.0/24",
                  "pools": [ { "pool": "10.0.0.128 - 10.0.0.254" } ],
                  "option-data": [
                    {
                      "name": "routers",
                      "data": "10.0.0.1"
                    },
                    {
                      "name": "domain-name",
                      "data": "example.com"
                    }
                  ]
                }
              ],
              "loggers": [
                {
                  "name": "kea-dhcp4",
                  "output_options": [
                    {
                      "output": "syslog:kea-dhcp4"
                    }
                  ],
                  "severity": "INFO"
                }
              ]
            }
          }
      - path: /etc/kea/kea-dchp6.conf
        content: |
          #TODO
      - path: /etc/nftables.conf
        content: |
          #!/usr/sbin/nft -f
          
          add table inet filter
          delete table inet filter
          
          table inet filter {
            chain input {
              type filter hook input priority 0;
            }
            chain forward {
              type filter hook forward priority 0;
            }
            chain output {
              type filter hook output priority 0;
            }
            chain postrouting {
              type nat hook postrouting priority srcnat;
              oifname {"vrrpwan0"} ip saddr 10.0.0.0/8 masquerade
            }
          }
      - path: /etc/radvd.conf
        content: |
          interface lan0
          {
            AdvSendAdvert on;
            IgnoreIfMissing on;
            AdvHomeAgentFlag off;
            prefix ::/64
            {
              AdvOnLink on;
              AdvAutonomous on;
              AdvRouterAddr on;
            };
            RDNSS 2606:4700:4700::1113 2606:4700:4700::1003
            {
              AdvRDNSSLifetime 600;
              FlushRDNSS on;
            };
          };
      - path: /etc/conntrackd/conntrackd.conf
        content: |
          Sync {
            Mode FTFW {
            }
            Multicast {
              IPv4_address 225.0.0.50
              Group 3780
              IPv4_interface 172.16.0.2
              Interface direct0
              SndSocketBuffer 1249280
              RcvSocketBuffer 1249280
              Checksum on
            }
          }
          General {
            HashSize 32768
            HashLimit 131072
            LogFile on
            LockFile /var/lock/conntrack.lock
            UNIX {
                    Path /var/run/conntrackd.ctl
            }
            NetlinkBufferSize 2097152
            NetlinkBufferSizeMaxGrowth 8388608
            Filter From Kernelspace {
              Protocol Accept {
                TCP
                SCTP
                DCCP
                UDP
                ICMP # This requires a Linux kernel >= 2.6.31
                IPv6-ICMP # This requires a Linux kernel >= 2.6.31
              }
              Address Ignore {
                IPv4_address 127.0.0.1 # loopback
                IPv4_address 192.168.1.18 # fw0@wan0
                IPv4_address 10.0.0.2 # fw0@lan0
                IPv4_address 172.16.0.1 # fw0@direct0
                IPv4_address 192.168.1.19 # fw1@wan0
                IPv4_address 10.0.0.3 # fw1@lan0
                IPv4_address 172.16.0.2 # fw1@direct0
                IPv4_address 10.0.0.1 # gateway VIP
                IPv4_address 192.168.1.20 # NAT VIP
              }
            }
          }
      - path: /etc/sysctl.d/50-custom-overrides.conf
        content: |
          # This enalbes IPv4 forwarding
          net.ipv4.ip_forward=1
          # This enables IPv6 forwarding, which also disables SLAAC, so you must statically assign addresses or use DHCPv6 for this host
          net.ipv6.conf.all.forwarding=1
