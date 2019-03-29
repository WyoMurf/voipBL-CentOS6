# voipBL for CentOS6 and more generally, for LINUX
The voipBL website has a list of errors in their instructions on how to install voipBL on a linux server. Fixed here!

On their website, they have instructions at http://www.voipbl.org. I have copied the text to this readme, and have updated the instructions. The core OS I'm writing for is CentOS6, which has several shortcomings because of its "conservativism". Other releases such as ubuntu and others will not have some of the problems, and the scripts will annotate what can be done.

Here we go:

# Step 1 You must install Fail2ban on your server. 
You can refer to the Fail2ban website for detailed instructions and advanced configurations.

   (no argument)

# Step 2 Create the /etc/cron.d/voipbl file to update rules each 4 hours

0 */4 * * *  root /usr/local/bin/voipbl.sh

     (they had an extra * in the list, which gives an error, and the script is not called.)

# Step 3 The voipbl.sh Script
If you are using iptables then save the content in /usr/local/bin/voipbl.sh to automatically block offending IP Addresses, Subnet or Netblock. You must also do a chmod 700 on this file.

(I removed the pure IPTABLES alternative. It will not work. Don't even being to think that you can build a chain of over 70,000 netblocks. It would take all day to load into IPTABLES, but don't worry, it won't, iptables can't handle that big a chain.)

Alternatively, if your system support ipset, you can use the following script: (thanks to Graham Barnett for his contribution)

Here I step in and provide the a set of files to download the voipbl and update the ipsets. 

But before anything else, Let me suggest a "better way". IPsets are built on top of IPtables. IPtables arranges things such that incoming packets from the outside world will all be funneled into the "filter" table, the INPUT chain. In my world, that chain is very simple, it looks like this:

target     prot opt source               destination         
ACCEPT     all  --  0.0.0.0/0            0.0.0.0/0           state RELATED,ESTABLISHED 
drop-rules-INPUT  all  --  0.0.0.0/0            0.0.0.0/0           

The first rule takes advantage of the connection tracking mechanism to determine if the incoming packet is part of a established connection, or a related one, and immediately ACCEPTS the packet if so. You don't want to check the voipBL for every incoming RTP and SIP packet, do you? Really????

The second line jumps into the drop-rules-INPUT chain, and there it checks for blacklist entries and fail2ban bans.

On a typical server, the drop-rules-INPUT chain might look like this:

Chain drop-rules-INPUT (1 references)
target     prot opt source               destination         
voipBL     all  --  0.0.0.0/0            0.0.0.0/0           match-set voipbl3 src 
voipBL     all  --  0.0.0.0/0            0.0.0.0/0           match-set voipbl2 src 
voipBL     all  --  0.0.0.0/0            0.0.0.0/0           match-set voipbl src 
fail2ban-FTP  tcp  --  0.0.0.0/0            0.0.0.0/0           multiport dports 21 match-set fail2ban-FTP src 
fail2ban-apache-auth  tcp  --  0.0.0.0/0            0.0.0.0/0           multiport dports 80 match-set fail2ban-apache-auth src 
fail2ban-SIP  all  --  0.0.0.0/0            0.0.0.0/0           match-set fail2ban-SIP src 
fail2ban-SSH  tcp  --  0.0.0.0/0            0.0.0.0/0           multiport dports 22 match-set fail2ban-SSH src 
fail2ban-recidive  all  --  0.0.0.0/0            0.0.0.0/0           match-set fail2ban-recidive src 

You will note that all these rules are match-set rules, and if a match is made, you will jump to the indicated chain, which is basically just a log & drop operation:

Chain fail2ban-SIP (1 references)
target     prot opt source               destination         
LOG        all  --  0.0.0.0/0            0.0.0.0/0           limit: avg 1/sec burst 5 LOG flags 6 level 4 prefix `fail2ban-SIP: ' 
DROP       all  --  0.0.0.0/0            0.0.0.0/0           

See the voipbl.sh script included in this repo. You will see that it builds the above structure, if it is not already present.
I may add other versions of voipbl.sh for other OS's that are not subject to the limitations of CentOS6.

Also, I take a somewhat major departure from Graham Barnett's approach, by running a program to convert the /tmp/voipbl.txt file into the "save/restore" format of ipset, which explodes the entries that have a CIDR less than 32 into a list of entries that have a CIDR of 32. Once this file is formed, it is fed into an "ipset restore" command. I did this, because using "ipset add" for each voipbl entry is fairly slow-- the entire list takes 1.5 to 2 MINUTES to load the ipsets. Using the "ipset restore" only takes 2 SECONDS!!! I wrote the converter in "GO", which seems pretty random, but converting with a bash script takes about a half hour, and "GO" can be compiled on an Ubuntu system, and will run fine on CentOS6, with no "GO" installation on the server at all.

# Step 4 Add a new action to your asterisk Jail
Please NOTE that steps 4 and 5 send feedback about the ban you are instating back to voipbl. If you choose not to participate, then you skip steps 4 and 5, but... the world will not be a better place for this lack.

Please note that the feedback mechanism back into voipbl for a local ban, will spread it all over the world, and back to you in another 4 hours (or whatever you set the update interval to). If you accidentally block one of your own IP's (and it happens every now and then) You should have some sort of local whitelisting mechanism to unban all your servers. This banned address will have to removed from all your own fail2bans, and added to your fail2ban ignoreip list, and the address also removed from the ipset for voipbl, and the unban sent up to voipbl. Hopefully it will be removed soon. Providing this whitelisting mechanism will NOT be covered in any detail here. At least not now/yet. It gets kind of ... complicated

In your /etc/fail2ban/jail.conf or jail.local (or whatever!):

[asterisk-iptables]
action   = iptables-allports[name=ASTERISK, protocol=all]
           voipbl[serial=XXXXXXXXXX]


# Step 5 Now define the VoIP Blacklist actions for Fail2ban

Create the file /etc/fail2ban/action.d/voipbl.conf, copy the text below into it:

[Definition]

actionban   = <getcmd> "<url>/ban/?serial=<serial>&ip=<ip>&count=<failures>"
actionunban = <getcmd> "<url>/unban/?serial=<serial>&ip=<ip>&count=<failures>"

[Init]

getcmd = wget --no-verbose --tries=3 --waitretry=10 --connect-timeout=10 \
              --read-timeout=60 --retry-connrefused --output-document=- \
	      --user-agent=Fail2Ban

url = http://www.voipbl.org



# Step 6 Now you can restart the Fail2ban daemon to get protected agains VoIP Fraud!
