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