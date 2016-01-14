#!/bin/bash

curl='/usr/bin/curl'
ipset='/usr/sbin/ipset'
ipt='/sbin/iptables'

ips_url='https://www.hide-my-ip.com/block-full.cgi'
set_ips='block_ips'
set_subnets='block_subnets'
temp_file='/tmp/block_ips.txt'

# remove misconfigured iptables rules
ipt_config_rule_remove()
{
  local set_name=$1
  local rule_number=$2
  local ipt_chain=$3
  local ipset_direction=$4

#  local ipt_regex="^[0-9]+\ +DROP.+?match-set.*?$set_name.+?src\,dst\ *$"
  local ipt_regex="^[0-9]+\ +DROP.+?match-set.*?$set_name.+?$ipset_direction\ *$"

  local ipt_array=()
  while read ipt_id
  do
    ipt_array+=($ipt_id)
  done <<< $($ipt -L $ipt_chain -n --line | \
             grep -iP "$ipt_regex" | awk '{print $1}')

  # do something if we have more than 0 rules for the set
  if [[ ${#ipt_array[@]} -gt 0 ]]; then
    # reversed array: delete rules from last line to first line
    for (( idx=${#ipt_array[@]}-1; idx>=0; idx-- ))
    do
      local id=${ipt_array[idx]}
      # delete rule if it is not in the right place
      if [[ $id -ne $rule_number ]]; then
        $ipt -D $ipt_chain $id
        if [[ $? -ne 0 ]]; then
          exit 1
        fi
      fi
    done
  fi
}

# add iptables rules
ipt_config_rule_add()
{
  local set_name=$1
  local rule_number=$2
  local ipt_chain=$3
  local ipset_direction=$4

#  local ipt_regex="^[0-9]+\ +DROP.+?match-set.*?$set_name.+?src\,dst\ *$"
  local ipt_regex="^[0-9]+\ +DROP.+?match-set.*?$set_name.+?$ipset_direction\ *$"

  local ipt_array=()
  while read ipt_id
  do
    ipt_array+=($ipt_id)
  done <<< $($ipt -L $ipt_chain -n --line | \
             grep -iP "$ipt_regex" | awk '{print $1}')

  # add rule if we don't have any
  if   [[ ${#ipt_array[@]} -eq 0 ]]; then
    $ipt -I $ipt_chain $rule_number -m set --match-set $set_name $ipset_direction -j DROP
    if [[ $? -ne 0 ]]; then
      echo "ERROR: iptables configuration error!"
      exit 1
    fi
  # if we have a rule and it is in the right place then do nothing
  elif [[ ${#ipt_array[@]} -eq 1 ]] && \
       [[ ${ipt_array[0]} -eq $rule_number ]]; then
    :
  # if we still have multple rules or the rule is not in the right place
  # then rise an error
  elif [[ ${#ipt_array[@]} -gt 1 ]] || \
       [[ ${ipt_array[0]} -ne $rule_number ]]; then
    echo "ERROR: iptables configuration error!"
    exit 1
  fi
}

# check if ipset is installed
if [ ! -x $ipset ]; then
  echo "ERROR: ipset is not installed!"
  exit 1
fi

# remove temp file first
if [ -f $temp_file ]; then
  rm -f $temp_file
fi

# create ipset set for ip addresses if it doesn't exist
$ipset list $set_ips >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  $ipset create $set_ips hash:ip maxelem 8388608
fi

# create ipset set for subnets if it doesn't exist
$ipset list $set_subnets >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  $ipset create $set_subnets hash:net
fi

# create iptables rules if they do not exist
ipt_config_rule_remove $set_ips 1 'FORWARD' 'src,dst'
ipt_config_rule_add $set_ips 1 'FORWARD' 'src,dst'

ipt_config_rule_remove $set_subnets 2 'FORWARD' 'src,dst'
ipt_config_rule_add $set_subnets 2 'FORWARD' 'src,dst'

ipt_config_rule_remove $set_ips 1 'OUTPUT' 'dst'
ipt_config_rule_add $set_ips 1 'OUTPUT' 'dst'

ipt_config_rule_remove $set_subnets 2 'OUTPUT' 'dst'
ipt_config_rule_add $set_subnets 2 'OUTPUT' 'dst'

# get ips and save them to a temp file
# (we do not save ips to array due to the lack of free ram on the server)
$curl -s $ips_url | grep -iP '^[0-9]+(\.[0-9]+){3}' > $temp_file
if [[ $? -ne 0 ]]; then
  echo "ERROR: error getting ips from url"
  exit 1
fi

# Flush ip sets if we have more then 0 items in result
# if we don't then just exit
ips_head=`head $temp_file | wc -l`
if [[ $ips_head -gt 0 ]]; then
  $ipset flush $set_ips
  $ipset flush $set_subnets
else
  exit 0
fi

## Add IPs to ipset
cat $temp_file | while read ip_item
do
  # add ip
  if   [[ $ip_item =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    $ipset -exist add $set_ips $ip_item

  # add ip range
  elif [[ $ip_item =~ ^[0-9]+(\.[0-9]+){3}\-[0-9]+(\.[0-9]+){3}$ ]]; then
    $ipset -exist add $set_ips $ip_item

  # add subnet
  elif [[ $ip_item =~ ^[0-9]+(\.[0-9]+){3}\/[0-9]+$ ]]; then
    $ipset -exist add $set_subnets $ip_item
  fi
done

# remove temp file
if [ -f $temp_file ]; then
  rm -f $temp_file
fi
