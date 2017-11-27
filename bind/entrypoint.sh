#!/bin/bash
# script to configure and lauch BIND DNS
chown root:bind /etc/bind/rndc.key;
chmod 640 /etc/bind/rndc.key;

/etc/init.d/bind9 stop

if [ ! -d /var/log/bind9 ]; then
    mkdir /var/log/bind9/;
    chown root:bind /var/log/bind9/;

    if [ ! -f /var/log/bind9/default.log ]; then
        touch /var/log/bind9/default.log;
        chown root:bind /var/log/bind9/default.log;
    fi
fi

if [ ! -d /etc/bind/zones ]; then
    mkdir /etc/bind/zones/;
    chown root:bind /etc/bind/zones/;

    if [ ! -f /etc/bind/zones/$CTF_DNS_ROOT ]; then
        #create zones
        touch /etc/bind/zones/$CTF_DNS_ROOT;
        chown root:bind /etc/bind/zones/$CTF_DNS_ROOT;

        #Only write DNS records on first run, else new records may be overwritten
        echo '$TTL 1d' > /etc/bind/zones/$CTF_DNS_ROOT;
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
        echo "$CTF_DNS_ROOT.        IN      A       $CTF_IP" >> /etc/bind/zones/$CTF_DNS_ROOT;
        echo "ns1                     IN      A       $CTF_DNS_IP" >> /etc/bind/zones/$CTF_DNS_ROOT;
        echo "ns2                     IN      A       $CTF_DNS_IP" >> /etc/bind/zones/$CTF_DNS_ROOT;
        echo "www                     IN      CNAME   $CTF_DNS_ROOT." >> /etc/bind/zones/$CTF_DNS_ROOT;
        echo "$CTF_NAME                     IN      CNAME       $CTF_DNS_ROOT." >> /etc/bind/zones/$CTF_DNS_ROOT;
    fi

    if [ ! -d /etc/bind/zones/reverse ]; then
        mkdir /etc/bind/zones/reverse;
        chown root:bind /etc/bind/zones/reverse;

        if [ ! -f /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS ]; then
            #create reverse zones
            touch /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS;
            chown root:bind /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS;

            #Only write DNS records on first run, else new records may be overwritten
            echo '$TTL 604800' > /etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS;
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
        fi
    fi
fi

echo "options {" > /etc/bind/named.conf.options;
echo "        listen-on { any; };" >> /etc/bind/named.conf.options;
echo "        listen-on-v6 { none; };" >> /etc/bind/named.conf.options;
echo "        forwarders {" >> /etc/bind/named.conf.options;
echo "                8.8.8.8;" >> /etc/bind/named.conf.options;
echo "                8.8.4.4;" >> /etc/bind/named.conf.options;
echo "        };" >> /etc/bind/named.conf.options;
echo "};" >> /etc/bind/named.conf.options;
echo "" >> /etc/bind/named.conf.options;

#lower levels will not be logged, only info and above
#log will be kept at /var/log/bind9/default.log
#time will be printed
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

#named.conf.local
#key to update zone
echo "key \"$CTF_DNS_ROOT.\" {" > /etc/bind/named.conf.local;
echo "  algorithm hmac-md5;" >> /etc/bind/named.conf.local;
echo "  secret \"$CTF_DNS_TSIG_KEY\";" >> /etc/bind/named.conf.local;
echo "};" >> /etc/bind/named.conf.local;

echo "zone \"$CTF_DNS_ROOT\" {" > /etc/bind/named.conf.local;
echo "    type master;" >> /etc/bind/named.conf.local;
echo "    file \"/etc/bind/zones/$CTF_DNS_ROOT\";" >> /etc/bind/named.conf.local;
echo "};" >> /etc/bind/named.conf.local;

echo "zone \"$CTF_REVERSE_DNS\" {" >> /etc/bind/named.conf.local;
echo "     type master;" >> /etc/bind/named.conf.local;
echo "     file \"/etc/bind/zones/reverse/rev.$CTF_REVERSE_DNS\";" >> /etc/bind/named.conf.local;
echo "};" >> /etc/bind/named.conf.local;

#launch named on foreground (bind DNS daemon)
/usr/sbin/named -f