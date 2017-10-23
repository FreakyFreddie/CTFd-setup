#!/bin/bash
# script to configure and lauch BIND DNS

echo "options {" > /etc/bind/named.conf.options;
echo "        listen-on { $CTF_DNS_IP; };" >> /etc/bind/named.conf.options;
echo "        listen-on-v6 { none; };" >> /etc/bind/named.conf.options;
echo "        directory \"/var/cache/bind\";" >> /etc/bind/named.conf.options;
echo "        auth-nxdomain no;" >> /etc/bind/named.conf.options;
echo "        forwarders {" >> /etc/bind/named.conf.options;
echo "                8.8.8.8;" >> /etc/bind/named.conf.options;
echo "                8.8.4.4;" >> /etc/bind/named.conf.options;
echo "        };" >> /etc/bind/named.conf.options;
echo "};" >> /etc/bind/named.conf.options;
echo "" >> /etc/bind/named.conf.options;

#lower levels will not be logged, only info and above
#log will be kept at /var/log/bind9
#time will be printed
#severity will be printed
mkdir /etc/bind/zones/
chown root:bind /var/log/bind9/
touch /var/log/bind9/default.log
chown root:bind /var/log/bind9/default.log

echo "logging {" >> /etc/bind/named.conf.options;
echo "    channel default_log {" >> /etc/bind/named.conf.options;
echo "        file \"/var/log/bind9/default.log\" versions 3 size 1m;" >> /etc/bind/named.conf.options;
echo "        severity info;" >> /etc/bind/named.conf.options;
echo "        print-time yes;" >> /etc/bind/named.conf.options;
echo "    };" >> /etc/bind/named.conf.options;
echo "    category queries {" >> /etc/bind/named.conf.options;
echo "      default_log;" >> /etc/bind/named.conf.options;
echo "    };" >> /etc/bind/named.conf.options;
echo "};" >> /etc/bind/named.conf.options;

mkdir /etc/bind/zones/
chown root:bind /etc/bind/zones/

#named.conf.local
echo "zone \"$CTF_DNS_ROOT\" {" > /etc/bind/named.conf.local;
echo "    type master;" >> /etc/bind/named.conf.local;
echo "    file \"/etc/bind/zones/$CTF_DNS_ROOT\";" >> /etc/bind/named.conf.local;
echo "};" >> /etc/bind/named.conf.local;

mkdir /etc/bind/zones/reverse
chown root:bind /etc/bind/zones/reverse

echo "zone \"$CTF_REVERSE_DNS\" {" >> /etc/bind/named.conf.local;
echo "     type master;" >> /etc/bind/named.conf.local;
echo "     file \"/etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS\";" >> /etc/bind/named.conf.local;
echo "};" >> /etc/bind/named.conf.local;

#create zones
touch /etc/bind/zones/$CTF_DNS_ROOT
chown root:bind /etc/bind/zones/$CTF_DNS_ROOT

echo '$TTL 1d' >> /etc/bind/zones/$CTF_DNS_ROOT;
echo "@       IN      SOA     ns1.$CTF_DNS_ROOT. admin.$CTF_DNS_ROOT. (" >> /etc/bind/zones/$CTF_DNS_ROOT;
echo "                        1       ; SERIAL = version of zone file, needs to be incremented every time file is changed" >> /etc/bind/zones/$CTF_DNS_ROOT;
echo "                        3h      ; Refresh" >> /etc/bind/zones/$CTF_DNS_ROOT;
echo "                        1h      ; Retry" >> /etc/bind/zones/$CTF_DNS_ROOT;
echo "                        1w      ; Expire" >> /etc/bind/zones/$CTF_DNS_ROOT;
echo "                        1h )    ; Minimum" >> /etc/bind/zones/$CTF_DNS_ROOT;
echo "";
echo "@       IN      NS      ns1.$CTF_DNS_ROOT. ;2 ns record just in case ns1 couldnt resolve" >> /etc/bind/zones/$CTF_DNS_ROOT;
echo "@       IN      NS      ns2.$CTF_DNS_ROOT." >> /etc/bind/zones/$CTF_DNS_ROOT;
echo "";
echo "$CTF_DNS_ROOT.      	IN      A       $CTF_IP" >> /etc/bind/zones/$CTF_DNS_ROOT;
echo "ns1                     IN      A       $CTF_DNS_IP" >> /etc/bind/zones/$CTF_DNS_ROOT;
echo "ns2                     IN      A       $CTF_DNS_IP" >> /etc/bind/zones/$CTF_DNS_ROOT;
echo "www                     IN      CNAME   http://$CTF_DNS_ROOT." >> /etc/bind/zones/$CTF_DNS_ROOT;
echo "$CTF_NAME           			IN    	CNAME   	http://$CTF_DNS_ROOT." >> /etc/bind/zones/$CTF_DNS_ROOT;

touch /etc/bind/zones/reverse/rev.101.34.192
chown root:bind /etc/bind/zones/reverse/rev.101.34.192

echo '$TTL 604800' >> /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS;
echo "@       IN      SOA     ns1.$CTF_DNS_ROOT. admin.$CTF_DNS_ROOT. (" >> /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS;
echo "                                1       ; Serial" >> /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS;
echo "                                3h      ; Refresh" >> /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS;
echo "                                1h      ; Retry" >> /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS;
echo "                                1w      ; Expire" >> /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS;
echo "                                1h )    ; Minimum" >> /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS;
echo "" >> /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS;
echo "@       IN      NS      ns1.$CTF_DNS_ROOT." >> /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS;
echo "@       IN      NS      ns2.$CTF_DNS_ROOT." >> /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS;
echo "" >> /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS;
echo "38      IN      PTR     $CTF_DNS_ROOT. ; needed for rdns, 38 = host octet" >> /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS;

/etc/init.d/bind9 restart

#cleanup apt
apt-get clean

#cleanup shell history
history -w
history -c
