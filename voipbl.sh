#!/bin/bash

# Original code contributed to voipBL by Graham Barnett
# Then embellished and tweaked by Steve Murphy

# Removed this fork, just isn't practical for 70,000+ entries. Ipset or Nothing!
# Check if chain exists and create one if required
# if [ `iptables -L | grep -c "Chain BLACKLIST-INPUT"` -lt 1 ]; then
#   /sbin/iptables -N BLACKLIST-INPUT
#   /sbin/iptables -I drop-rules-INPUT 1 -j BLACKLIST-INPUT
# fi
# 	
# Empty the chain
# /sbin/iptables -F BLACKLIST-INPUT
# wget -qO - http://www.voipbl.org/update/?wn[]=ripe&wn[]=arin |\
#   awk '{print "if [ ! -z \""$1"\" -a \""$1"\" !=  \"#\" ]; then /sbin/iptables -A BLACKLIST-INPUT -s \""$1"\" -j DROP;fi;"}' | sh


#
# When invoked from crontab, all the output is sent to /dev/null... It's nice to have some debug, tho, when run by hand

function setup_ipset () {
   ## $1 is the filename
   ## $2 is the ipset name
   echo "============================= $1 ========================= $2 ==============="
   echo "Generate the save set for this chunk of the voipbl!"
   date
   ./voipbl-convert $1 $2
   date
   echo "Done. Destroy voipbl_temp, if already exists.."
   ipset destroy voipbl_temp > /dev/null 2>&1 || true
   echo "Done. create ipset voipbl_temp from the save-format of the data just created..."
   date
   ipset restore < $1.t
   date
   echo "Done. Wasn't that quick? Normally it'd take 90+ seconds via individual 'ipset add' commands! Cleanse the IP's that are in the whitelist from the blacklist..."

   touch /etc/fail2ban/voipbl-whitelist  ## probably not right to mix the configs in /etc/fail2ban, but... they are related
   WL=`cat /etc/fail2ban/voipbl-whitelist`
   for i in $WL; do
      echo "deleting $i ..."
      ipset -exist del voipbl_temp $i || true
   done

   date
   echo "Done. Swapping voipbl_temp and $2" 
   ipset swap voipbl_temp $2
   echo "Done. destroy voipbl_temp (which, from swapping, is the old ipset)" 
   ipset destroy voipbl_temp || true
   date 
   echo "Done!" 
   date
}

URL="http://www.voipbl.org/update/"

# Check if chain exists and create one if required
if [ `iptables -L -n | grep -c "Chain voipBL"` -lt 1 ]; then
  echo "Adding voipBL log-drop Chain"
  /sbin/iptables -N voipBL
  /sbin/iptables -A voipBL -m limit --limit 60/minute -j LOG --log-prefix "voipBL: " --log-tcp-options --log-ip-options
  /sbin/iptables -A voipBL -j DROP
fi

if [ `iptables -L -n | grep -c "Chain drop-rules-INPUT"` -lt 1 ]; then
  echo "Set up drop-rules-INPUT, jump there from INPUT after RELATED, ESTABLISHED acceptance"
  /sbin/iptables -N drop-rules-INPUT
  /sbin/iptables -I INPUT 1  -m state --state RELATED,ESTABLISHED -j ACCEPT
  /sbin/iptables -I INPUT 2 -p all -j drop-rules-INPUT
fi

set -e
echo "Downloading rules from VoIP Blacklist"
wget -qO - $URL -O /tmp/voipbl.txt
date
NUM_IPS=`wc -l /tmp/voipbl.txt | cut -f 1 -d ' '`
NUM_SETS=$(( $NUM_IPS < 35000 ? 1 : ($NUM_IPS < 70000 ? 2 : ($NUM_IPS < 105000 ? 3 : 4)) ))
echo "Done. There are $NUM_IPS lines in the voipbl.txt file, we need $NUM_SETS ipsets to store them! Create ipset voipbl, if not already existing..."
# Check if rule set exists and create one if required
if ! $(/usr/sbin/ipset list voipbl > /dev/null 2>&1) ; then
  time ipset -N voipbl iphash
  echo "Created voipbl ipset"
fi
if [ $NUM_SETS -gt 1 ] ; then
  echo "num sets is greater than 1"
  if ! $(/usr/sbin/ipset list voipbl2 > /dev/null 2>&1); then
    time ipset -N voipbl2 iphash
    echo "Created voipbl2 ipset"
  fi
fi
echo "Done with voipbl2"
if [ $NUM_SETS -gt 2 ] ; then
  if ! $(/usr/sbin/ipset list voipbl3 > /dev/null 2>&1); then
    time ipset -N voipbl3 iphash
    echo "Created voipbl3 ipset"
  fi
fi
echo "Done with voipbl3"
if [ $NUM_SETS -gt 3 ] ; then
  if ! $(/usr/sbin/ipset list voipbl4 > /dev/null 2>&1); then
    time ipset -N voipbl4 iphash
    echo "Created voipbl4 ipset"
  fi
fi

echo "Done. create match-set iptables rule, if not already existing..."
 
declare -i MS1=`iptables -n -L drop-rules-INPUT | grep -c 'voipbl src'`
declare -i MS3=`iptables -n -L drop-rules-INPUT | grep -c 'voipbl3 src'`
declare -i MS4=`iptables -n -L drop-rules-INPUT | grep -c 'voipbl4 src'`
declare -i MS2=`iptables -n -L drop-rules-INPUT | grep -c 'voipbl2 src'`


#Check if rule in iptables
if [ $MS1 -lt 1 ] ; then
 /sbin/iptables -I drop-rules-INPUT 1 -m set --match-set voipbl src -j voipBL
 echo "Created match-set rule for voipbl"
fi

if [ $NUM_SETS -gt 1 ] ; then
  if [ $MS2 -lt 1 ] ; then
    /sbin/iptables -I drop-rules-INPUT 2 -m set --match-set voipbl2 src -j voipBL
    echo "Created match-set rule for voipbl2"
  fi
fi

if [ $NUM_SETS -gt 2 ] ; then
  if [ $MS3 -lt 1 ] ; then
    /sbin/iptables -I drop-rules-INPUT 3 -m set --match-set voipbl3 src -j voipBL
    echo "Created match-set rule for voipbl3"
  fi
fi

if [ $NUM_SETS -gt 3 ] ; then
  if [ $MS4 -lt 1 ] ; then
    /sbin/iptables -I drop-rules-INPUT 4 -m set --match-set voipbl4 src -j voipBL
    echo "Created match-set rule for voipbl4"
  fi
fi

split --numeric-suffixes --suffix-length=1 --lines=35000   /tmp/voipbl.txt /tmp/voipbl
echo "Split the /tmp/voipbl.txt into 35,000 line chunks"

setup_ipset  /tmp/voipbl0  voipbl
if [ $NUM_SETS -gt 1 ] ; then
   setup_ipset /tmp/voipbl1 voipbl2
fi
if [ $NUM_SETS -gt 2 ] ; then
   setup_ipset /tmp/voipbl2 voipbl3
fi
if [ $NUM_SETS -gt 3 ] ; then
   setup_ipset /tmp/voipbl3 voipbl4
fi


