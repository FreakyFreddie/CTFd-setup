#!/bin/bash
#Use this script to easily set up the CTFd Platform on Ubuntu 16.04 LTS
#The script will do the following:
#-Set up the CTFd app and database container
#-install vSphere automation SDK requirements in CTFd app container
#-install bind DNS in a separate container
if [ $EUID -ne 0 ]
then
	echo "RUN THE SCRIPT AS ROOT.";
	exit 1;
fi

#--------------------------------------PARAMETER DECLARATION--------------------------------------#
INSTALLPATH="/home/ubuntu";
SCRIPT_DIRECTORY=$(dirname $(readlink -f $0));
CTFd_REPOSITORY="https://github.com/CTFd/CTFd.git";

#plugins to install
PLUGINS[0]="https://github.com/FreakyFreddie/challengevms";

#themes to install
THEMES[0]="https://github.com/ColdHeat/UnitedStates"

#CTF NETWORK SETTINGS (users connect to this interface, VLAN 15)
CTF_IFACE="ens33";
CTF_IP="10.0.7.4";
CTF_SUBNET="255.255.252.0";
CTF_GATEWAY="10.0.4.1";
CTF_NETWORK="10.0.4.0";
CTF_DNS="10.0.4.1";

#VM MANAGEMENT NETWORK SETTINGS (used to manage the VM through SSH, VLAN 10)
VM_MANAGEMENT_IFACE="ens34";
VM_MANAGEMENT_IP="192.168.2.4";
VM_MANAGEMENT_SUBNET="255.255.255.0";

#HYPERVISOR MANAGEMENT NETWORK SETTINGS (used to connect to vCenter server API, VLAN 5)
HV_MANAGEMENT_IFACE="ens32";
HV_MANAGEMENT_IP="192.168.1.254";
HV_MANAGEMENT_SUBNET="255.255.255.0";

#CURRENT INTERFACE IPS
CTF_IFACE_IP=$(ip addr show dev $CTF_IFACE | grep "inet\b" | awk '{print $2}' | cut -d/ -f1);
VM_MANAGEMENT_IFACE_IP=$(ip addr show dev $VM_MANAGEMENT_IFACE | grep "inet\b" | awk '{print $2}' | cut -d/ -f1);
HV_MANAGEMENT_IFACE_IP=$(ip addr show dev $HV_MANAGEMENT_IFACE | grep "inet\b" | awk '{print $2}' | cut -d/ -f1);

#USED TO CONFIGURE DNS CONTAINER
CTF_DNS_IP="10.0.7.4";
CTF_REVERSE_DNS=$(echo $CTF_DNS_IP | awk -F . '{print $3"."$2"."$1".in-addr.arpa"}');
#DNS RECORD
CTF_DNS_ROOT="myctf.be";
CTF_NAME="ctf";

#MARIADB CONTAINER CONFIG
MARIADB_ROOT_PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9-_!@#$%^&*()_+{}|:<>?=' | fold -w 25 | head -n 1);
MARIADB_USER="CTFd";
MARIADB_PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9-_!@#$%^&*()_+{}|:<>?=' | fold -w 25 | head -n 1);

#configuration for samba share (optional/easy way to access logs)
SAMBA_USER="";
SAMBA_PASS="";
SAMBA_CONFIG=/etc/samba/smb.conf;
FILE_SHARE="[$CTF_NAME]
path = $INSTALLPATH/$CTF_NAME
valid users = $SAMBA_USER
read only = no";

#-------------------------------------------------------------------------------------------------#
#--------------------------------------NETWORK CONFIGURATION--------------------------------------#
echo "Configuring CTF Platform network interfaces where necessary..."

if [ "$CTF_IFACE_IP" != "$CTF_IP" ]
then
	#ERASE AUTOMATIC CONFIGURATION FROM /etc/network/interfaces
	sed -i "/$CTF_IFACE/d" /etc/network/interfaces;

	ifdown $CTF_IFACE;
	#flush intefaces to prevent DHCP issues
	ip addr flush dev $CTF_IFACE;
	#WRITE NEW CONFIGURATION TO FILE
	echo "auto $CTF_IFACE" >> /etc/network/interfaces;
	echo "iface $CTF_IFACE inet static" >> /etc/network/interfaces;
	echo "address $CTF_IP" >> /etc/network/interfaces;
	echo "netmask $CTF_SUBNET" >> /etc/network/interfaces;
	echo "network $CTF_NETWORK" >> /etc/network/interfaces;
	echo "gateway $CTF_GATEWAY" >> /etc/network/interfaces;
	echo "dns-nameservers $CTF_DNS" >> /etc/network/interfaces;
	echo "" >> /etc/network/interfaces;

	echo "CTF network configured. (1/3)";
	echo "Starting CTF network interface...";

	if ! ifup $CTF_IFACE
	then
	    echo "Unable to bring up $CTF_IFACE. Exiting...";
	    exit 1;
	fi
	echo "Done.";
fi

if [ "$VM_MANAGEMENT_IFACE_IP" != "$VM_MANAGEMENT_IP" ]
then
	sed -i "/$VM_MANAGEMENT_IFACE/d" /etc/network/interfaces;
	ifdown $VM_MANAGEMENT_IFACE;
	ip addr flush dev $VM_MANAGEMENT_IFACE;
	#gateway is omitted, add if present
	echo "auto $VM_MANAGEMENT_IFACE" >> /etc/network/interfaces;
	echo "iface $VM_MANAGEMENT_IFACE inet static" >> /etc/network/interfaces;
	echo "address $VM_MANAGEMENT_IP" >> /etc/network/interfaces;
	echo "netmask $VM_MANAGEMENT_SUBNET" >> /etc/network/interfaces;
	echo "" >> /etc/network/interfaces;

	echo "VM management network configured. (2/3)";
	echo "Starting VM management interface...";

	if ! ifup $VM_MANAGEMENT_IFACE
	then
	    echo "Unable to bring up $VM_MANAGEMENT_IFACE. Exiting...";
	    exit 1;
	fi

	echo "Done.";
fi

if [ "$HV_MANAGEMENT_IFACE_IP" != "$HV_MANAGEMENT_IP" ]
then
	sed -i "/$HV_MANAGEMENT_IFACE/d" /etc/network/interfaces;
	ifdown $HV_MANAGEMENT_IFACE;
	ip addr flush dev $HV_MANAGEMENT_IFACE;
	#gateway is omitted, add if present
	echo "auto $HV_MANAGEMENT_IFACE" >> /etc/network/interfaces;
	echo "iface $HV_MANAGEMENT_IFACE inet static" >> /etc/network/interfaces;
	echo "address $HV_MANAGEMENT_IP" >> /etc/network/interfaces;
	echo "netmask $HV_MANAGEMENT_SUBNET" >> /etc/network/interfaces;
	echo "" >> /etc/network/interfaces;

	echo "Hypervisor management network configured. (3/3)";
	echo "Starting Hypervisor management interface...";

	if ! ifup $HV_MANAGEMENT_IFACE
	then
	    echo "Unable to bring up $HV_MANAGEMENT_IFACE. Exiting...";
	    exit 1;
	fi

	echo "Done.";
fi

echo "Testing network connection...";

#If machine has internet, continue
if ! ping -c 4 8.8.8.8
then
    echo "No internet access. Exiting...";
    exit 1;
fi

echo "Internet access detected.";
#--------------------------------------------------------------------------------------------------------#
#---------------------------------------------PRE INSTALLATION-------------------------------------------#
echo "Updating package list & upgrading packages...";

#UPDATES
apt-get update > /dev/null;

if ! apt-get upgrade -y > /dev/null
then
    echo "Unable to upgrade packages. Exiting...";
    exit 1;
fi

echo "Done.";

#ADD SSH ACCESS (optional)
echo "Adding SSH access...";
apt-get install openssh-server -y > /dev/null;
echo "Done.";

#ADD open-vm-tools (optional)
echo "Adding open-vm-tools...";
apt-get install open-vm-tools -y > /dev/null;
echo "Done.";

echo "Installing platform dependencies...";

#INSTALL DEPENDENCIES
apt-get install git -y > /dev/null;
#apt-get install python-pip -y;
#pip install --upgrade pip;
apt-get install docker -y > /dev/null;
apt-get install docker-compose -y > /dev/null;
apt-get install bind9utils -y > /dev/null;
apt-get install mariadb-client -y > /dev/null;

echo "Done.";
echo "Configuring Docker to start on boot...";

# Configure Docker daemon to start on boot
if ! systemctl enable docker
then
    echo "Unable to configure Docker to start on boot. Exiting...";
    exit 1;
fi

echo "Done.";

#----------------------------------------------------------------------------------------------#
#-----------------------------------DNS CONTAINER CONFIGURATION--------------------------------#
# Generate Docker file with environment variables set

echo "Generating Docker configuration for DNS container...";

#if INSTALLPATH directory does not exists, exit
if [ ! -d $INSTALLPATH ]
then
	echo "Error: User $INSTALLPATH directory not found. Create $INSTALLPATH and try again.";
   	exit 1;
fi

# if bind directory does not exists, move bind directory there
if [ ! -d $INSTALLPATH/bind ]
then
    mv $SCRIPT_DIRECTORY/bind $INSTALLPATH/bind;
fi

# GO TO HOME DIRECTORY
cd $INSTALLPATH/bind;

# generate TSIG for UPDATING RECORDS
dnssec-keygen -r /dev/urandom -a HMAC-MD5 -b 512 -n HOST $CTF_DNS_ROOT;
CTF_DNS_TSIG_KEY=$(cat ./*.key | cut -d\  -f7-);


# keyfiles no longer needed as they will be passed to containers through environment variables and bind key file
rm ./*.private;
rm ./*.key;

cd $INSTALLPATH;

# generate the bind key file (later mounted in CTFd container)
touch ./bind/update_key.key
echo "key \"update_key\" {" >> ./bind/update_key.key;
echo "	algorithm HMAC-MD5;" >> ./bind/update_key.key;
echo "	secret \"$CTF_DNS_TSIG_KEY\";" >> ./bind/update_key.key;
echo "};" >> ./bind/update_key.key;

touch ./bind/Dockerfile;
echo "FROM debian:latest" >> ./bind/Dockerfile;
echo "ENV CTF_IP=$CTF_IP" >> ./bind/Dockerfile;
echo "ENV CTF_DNS_IP=$CTF_DNS_IP" >> ./bind/Dockerfile;
echo "ENV CTF_REVERSE_DNS=$CTF_REVERSE_DNS" >> ./bind/Dockerfile;
echo "ENV CTF_DNS_TSIG_KEY=$CTF_DNS_TSIG_KEY" >> ./bind/Dockerfile;
echo "ENV CTF_DNS_ROOT=$CTF_DNS_ROOT" >> ./bind/Dockerfile;
echo "ENV CTF_NAME=$CTF_NAME" >> ./bind/Dockerfile;
echo "RUN apt-get update && apt-get upgrade -y && apt-get install -y bind9" >> ./bind/Dockerfile;
echo "COPY entrypoint.sh /sbin/entrypoint.sh" >> ./bind/Dockerfile;
echo "RUN chmod 755 /sbin/entrypoint.sh" >> ./bind/Dockerfile;
echo "EXPOSE 53" >> ./bind/Dockerfile;
echo "EXPOSE 953" >> ./bind/Dockerfile; #port 953 rndc in case of management, this port is only internally exposed
echo "ENTRYPOINT [\"/sbin/entrypoint.sh\"]" >> ./bind/Dockerfile;
echo "Done.";

#-----------------------------------------------------------------------------------------------------#
#--------------------------------------NGINX CONTAINER CONFIGURATION----------------------------------#
# Generate Docker file with environment variables set

echo "Generating Docker configuration for NGINX container...";

#if nginx directory does not exists, move nginx directory there
if [ ! -d $INSTALLPATH/nginx ]
then
    mv $SCRIPT_DIRECTORY/nginx $INSTALLPATH/nginx;
fi

#GENERATE CERTIFICATE
openssl req -x509 -nodes -days 365 -newkey rsa:4096 -keyout ./nginx/cert.key -out ./nginx/cert.crt -subj "/CN=$CTF_DNS_ROOT/O=EvilCorp LTD./C=BE";

touch ./nginx/Dockerfile;
echo "FROM nginx:latest" >> ./nginx/Dockerfile;
echo "RUN mkdir -p /var/log/nginx" >> ./nginx/Dockerfile;
echo "RUN mkdir -p /var/ctfd" >> ./nginx/Dockerfile;
echo "COPY ./entrypoint.sh /sbin/entrypoint.sh" >> ./nginx/Dockerfile;
echo "RUN chmod 755 /sbin/entrypoint.sh" >> ./nginx/Dockerfile;
echo "EXPOSE 80" >> ./nginx/Dockerfile;
echo "EXPOSE 443" >> ./nginx/Dockerfile;
echo "ENTRYPOINT [\"/sbin/entrypoint.sh\"]" >> ./nginx/Dockerfile;
echo "Done.";

#GENERATE NGINX CONFIG TEMPLATE

touch ./nginx/reverse-proxy.template;
echo "worker_processes 1;" >> ./nginx/reverse-proxy.template;
echo "" >> ./nginx/reverse-proxy.template;
echo "user nobody nogroup;" >> ./nginx/reverse-proxy.template;
echo "# 'user nobody nobody;' for systems with 'nobody' as a group instead" >> ./nginx/reverse-proxy.template;
echo "pid /tmp/nginx.pid;" >> ./nginx/reverse-proxy.template;
echo "error_log /tmp/nginx.error.log;" >> ./nginx/reverse-proxy.template;
echo "" >> ./nginx/reverse-proxy.template;
echo "events {" >> ./nginx/reverse-proxy.template;
echo "  worker_connections 1024; # increase if you have lots of clients" >> ./nginx/reverse-proxy.template;
echo "  accept_mutex off; # set to 'on' if nginx worker_processes > 1" >> ./nginx/reverse-proxy.template;
echo "}" >> ./nginx/reverse-proxy.template;
echo "" >> ./nginx/reverse-proxy.template;
echo "http {" >> ./nginx/reverse-proxy.template;
echo "  include mime.types;" >> ./nginx/reverse-proxy.template;
echo "  # fallback in case we can't determine a type" >> ./nginx/reverse-proxy.template;
echo "  default_type application/octet-stream;" >> ./nginx/reverse-proxy.template;
echo "  access_log /var/log/nginx/access.log combined;" >> ./nginx/reverse-proxy.template;
echo "  sendfile on;" >> ./nginx/reverse-proxy.template;
echo "" >> ./nginx/reverse-proxy.template;
echo "  upstream app_server {" >> ./nginx/reverse-proxy.template;
echo "    # fail_timeout=0 means we always retry an upstream even if it failed" >> ./nginx/reverse-proxy.template;
echo "    # to return a good HTTP response" >> ./nginx/reverse-proxy.template;
echo "" >> ./nginx/reverse-proxy.template;
echo "    # for UNIX domain socket setups" >> ./nginx/reverse-proxy.template;
echo "    # server unix:/tmp/gunicorn.sock fail_timeout=0;" >> ./nginx/reverse-proxy.template;
echo "" >> ./nginx/reverse-proxy.template;
echo "    # for a TCP configuration" >> ./nginx/reverse-proxy.template;
echo "    server ctfd:443 fail_timeout=0;" >> ./nginx/reverse-proxy.template;
echo "  }" >> ./nginx/reverse-proxy.template;
echo "" >> ./nginx/reverse-proxy.template;
echo "  server {" >> ./nginx/reverse-proxy.template;
echo "    # if no Host match, close the connection to prevent host spoofing" >> ./nginx/reverse-proxy.template;
echo "    listen 80 default_server;" >> ./nginx/reverse-proxy.template;
echo '    return 301 https://$host$request_uri;' >> ./nginx/reverse-proxy.template;
echo '    #rewrite ^/(.*) https://$host/$1 permanent;' >> ./nginx/reverse-proxy.template;
echo "  }" >> ./nginx/reverse-proxy.template;
echo "" >> ./nginx/reverse-proxy.template;
echo "  server {" >> ./nginx/reverse-proxy.template;
echo "    # use 'listen 80 deferred;' for Linux" >> ./nginx/reverse-proxy.template;
echo "    # use 'listen 80 accept_filter=httpready;' for FreeBSD" >> ./nginx/reverse-proxy.template;
echo "    listen 443 ssl;" >> ./nginx/reverse-proxy.template;
echo "    ssl_certificate /etc/nginx/cert.crt;" >> ./nginx/reverse-proxy.template;
echo "    ssl_certificate_key /etc/nginx/cert.key;" >> ./nginx/reverse-proxy.template;
echo "    ssl on;" >> ./nginx/reverse-proxy.template;
echo "    ssl_session_cache  builtin:1000  shared:SSL:10m;" >> ./nginx/reverse-proxy.template;
echo "    ssl_protocols  TLSv1 TLSv1.1 TLSv1.2;" >> ./nginx/reverse-proxy.template;
echo "    ssl_ciphers HIGH:!aNULL:!eNULL:!EXPORT:!CAMELLIA:!DES:!MD5:!PSK:!RC4;" >> ./nginx/reverse-proxy.template;
echo "    ssl_prefer_server_ciphers on;" >> ./nginx/reverse-proxy.template;
echo "" >> ./nginx/reverse-proxy.template;
echo "    client_max_body_size 4G;" >> ./nginx/reverse-proxy.template;
echo "" >> ./nginx/reverse-proxy.template;
echo "    # set the correct host(s) for your site" >> ./nginx/reverse-proxy.template;
echo "    # server_name example.com www.example.com;" >> ./nginx/reverse-proxy.template;
echo "" >> ./nginx/reverse-proxy.template;
echo "    keepalive_timeout 5;" >> ./nginx/reverse-proxy.template;
echo "" >> ./nginx/reverse-proxy.template;
echo "    # path for static files" >> ./nginx/reverse-proxy.template;
echo "    root /var/ctfd;" >> ./nginx/reverse-proxy.template;
echo "" >> ./nginx/reverse-proxy.template;
echo "    location / {" >> ./nginx/reverse-proxy.template;
echo "      # checks for static file, if not found proxy to app" >> ./nginx/reverse-proxy.template;
echo '      try_files $uri @proxy_to_app;' >> ./nginx/reverse-proxy.template;
echo "    }" >> ./nginx/reverse-proxy.template;
echo "" >> ./nginx/reverse-proxy.template;
echo '    location @proxy_to_app {' >> ./nginx/reverse-proxy.template;
echo '      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' >> ./nginx/reverse-proxy.template;
echo "      # enable this if and only if you use HTTPS" >> ./nginx/reverse-proxy.template;
echo "      proxy_set_header X-Forwarded-Proto https;" >> ./nginx/reverse-proxy.template;
echo '      proxy_set_header Host $http_host;' >> ./nginx/reverse-proxy.template;
echo "      # we don't want nginx trying to do something clever with" >> ./nginx/reverse-proxy.template;
echo "      # redirects, we set the Host: header above already." >> ./nginx/reverse-proxy.template;
echo "      proxy_redirect off;" >> ./nginx/reverse-proxy.template;
echo "      proxy_pass https://ctfd;" >> ./nginx/reverse-proxy.template;
echo "    }" >> ./nginx/reverse-proxy.template;
echo "" >> ./nginx/reverse-proxy.template;
echo "    #error_page 500 502 503 504 /500.html;" >> ./nginx/reverse-proxy.template;
echo "    # location = /500.html {" >> ./nginx/reverse-proxy.template;
echo "      # root /path/to/app/current/public;" >> ./nginx/reverse-proxy.template;
echo "    #}" >> ./nginx/reverse-proxy.template;
echo "  }" >> ./nginx/reverse-proxy.template;
echo "}" >> ./nginx/reverse-proxy.template;


#-----------------------------------------------------------------------------------------------------#
#------------------------------------------CTF CONFIGURATION------------------------------------------#
echo "Cloning CTFd into $INSTALLPATH...";

if [ ! -d $INSTALLPATH/CTFd ]
then
	if ! git clone ${CTFd_REPOSITORY}
	then
		echo "git clone ${CTFd_REPOSITORY} failed. Exiting...";
	    exit 1;
	fi
fi

echo "Done.";
echo "Regenerating CTFd Docker configuration to use the latest Debian Python image with Python 3 and install dnsutils (nsupdate)...";

#Python image used for container
echo "FROM python:3" > ./CTFd/Dockerfile;
echo "" >> ./CTFd/Dockerfile;
echo "RUN apt-get update && apt-get upgrade -y" >> ./CTFd/Dockerfile;
echo "RUN apt-get install python3 python3-dev mysql-client libffi-dev gcc make musl-dev python3-pip dnsutils -y" >> ./CTFd/Dockerfile;
echo "" >> ./CTFd/Dockerfile;
echo "RUN mkdir -p /opt/CTFd" >> ./CTFd/Dockerfile;
echo "" >> ./CTFd/Dockerfile;
echo "COPY . /opt/CTFd" >> ./CTFd/Dockerfile;
echo "WORKDIR /opt/CTFd" >> ./CTFd/Dockerfile;
echo "" >> ./CTFd/Dockerfile;
echo "VOLUME [\"/opt/CTFd\"]" >> ./CTFd/Dockerfile;
echo "" >> ./CTFd/Dockerfile;
echo "RUN pip3 install -r requirements.txt" >> ./CTFd/Dockerfile; #also install vsphere API dependencies# --extra-index-url /opt/vsphere-automation-sdk-python/lib"
echo "" >> ./CTFd/Dockerfile;
echo "RUN chmod +x /opt/CTFd/docker-entrypoint.sh" >> ./CTFd/Dockerfile;
echo "" >> ./CTFd/Dockerfile;
echo "EXPOSE 443" >> ./CTFd/Dockerfile;
echo "" >> ./CTFd/Dockerfile;
echo "ENTRYPOINT [\"/opt/CTFd/docker-entrypoint.sh\"]" >> ./CTFd/Dockerfile;

echo "Done.";
echo "Generating self-signed certificate for connection between CTFd and Nginx";

cd $INSTALLPATH/CTFd;
openssl req -x509 -nodes -newkey rsa:4096  -keyout key.pem -out cert.pem -days 365 -subj "/CN=$CTF_DNS_ROOT/O=EvilCorp LTD./C=BE";

echo "Done.";

echo "Adding new parameters to gunicorn launch...";
cd $INSTALLPATH;
sed -i '/gunicorn/d' ./CTFd/docker-entrypoint.sh;
echo "gunicorn --bind 0.0.0.0:443 -w 1 'CTFd:create_app()' --access-logfile '/opt/CTFd/CTFd/logs/access.log' --error-logfile '/opt/CTFd/CTFd/logs/error.log' --keyfile '/opt/CTFd/key.pem' --certfile '/opt/CTFd/cert.pem'" >> ./CTFd/docker-entrypoint.sh; # --log-level debug

echo "Done.";
echo "Cloning plugins...";

cd $INSTALLPATH/CTFd/CTFd/plugins;

#clone plugins to plugin folder
for i in "${PLUGINS[@]}"
do
   	if ! git clone $i
	then
		echo "git clone $i failed. Exiting..."
	    exit 1;
	fi
   	echo "Cloned $i.";
done

echo "Done.";
echo "Cloning themes...";

cd $INSTALLPATH/CTFd/CTFd/themes;

#clone themes to theme folder
for i in "${THEMES[@]}"
do
   	if ! git clone $i
	then
		echo "git clone $i failed. Exiting..."
	    exit 1;
	fi
   	echo "Cloned $i.";
done

echo "Done.";
echo "Recreating docker-compose.yml with new configuration...";

cd $INSTALLPATH;

echo "version: '2'" > ./CTFd/docker-compose.yml;
echo "" >> ./CTFd/docker-compose.yml;
echo "services:" >> ./CTFd/docker-compose.yml;
echo "  ctfd:" >> ./CTFd/docker-compose.yml;
echo "    build: ." >> ./CTFd/docker-compose.yml;
echo "    restart: always" >> ./CTFd/docker-compose.yml;
echo "    environment:" >> ./CTFd/docker-compose.yml;
echo "      - DATABASE_URL=mysql+pymysql://root:$MARIADB_ROOT_PASS@db/ctfd" >> ./CTFd/docker-compose.yml;
echo "    volumes:" >> ./CTFd/docker-compose.yml;
echo "      - .data/CTFd/logs:/opt/CTFd/CTFd/logs" >> ./CTFd/docker-compose.yml;
echo "      - .data/CTFd/uploads:/opt/CTFd/CTFd/uploads" >> ./CTFd/docker-compose.yml;
echo "      - $INSTALLPATH/bind/update_key.key:/opt/CTFd/update_key.key" >> ./CTFd/docker-compose.yml;
echo "    depends_on:" >> ./CTFd/docker-compose.yml;
echo "      - db" >> ./CTFd/docker-compose.yml;
echo "" >> ./CTFd/docker-compose.yml;

echo "Added CTFd service (1/4).";

echo "  db:" >> ./CTFd/docker-compose.yml;
echo "    image: mariadb:latest" >> ./CTFd/docker-compose.yml;
echo "    restart: always" >> ./CTFd/docker-compose.yml;
echo "    environment:" >> ./CTFd/docker-compose.yml;
echo "      - MYSQL_ROOT_PASSWORD=$MARIADB_ROOT_PASS" >> ./CTFd/docker-compose.yml;
echo "      - MYSQL_USER=$MARIADB_USER" >> ./CTFd/docker-compose.yml;
echo "      - MYSQL_PASSWORD=$MARIADB_PASS" >> ./CTFd/docker-compose.yml;
echo "    volumes:" >> ./CTFd/docker-compose.yml;
echo "      - .data/mysql:/var/lib/mysql" >> ./CTFd/docker-compose.yml;
echo "" >> ./CTFd/docker-compose.yml;

echo "Added db service (2/4).";

echo "  bind:" >> ./CTFd/docker-compose.yml;
echo "    build: $INSTALLPATH/bind/" >> ./CTFd/docker-compose.yml;
echo "    restart: always" >> ./CTFd/docker-compose.yml;
echo "    ports:" >> ./CTFd/docker-compose.yml;
echo "      - \"53:53/udp\"" >> ./CTFd/docker-compose.yml;
echo "      - \"53:53/tcp\"" >> ./CTFd/docker-compose.yml;
echo "    environment:" >> ./CTFd/docker-compose.yml;
echo "      - CTF_DNS_TSIG_KEY=$CTF_DNS_TSIG_KEY" >> ./CTFd/docker-compose.yml;
echo "    volumes:" >> ./CTFd/docker-compose.yml;
echo "      - .data/bind:/var/log/bind9" >> ./CTFd/docker-compose.yml;
echo "" >> ./CTFd/docker-compose.yml;

echo "Added bind service (3/4).";

echo "  nginx:" >> ./CTFd/docker-compose.yml;
echo "    build: $INSTALLPATH/nginx/" >> ./CTFd/docker-compose.yml;
echo "    restart: always" >> ./CTFd/docker-compose.yml;
echo "    ports:" >> ./CTFd/docker-compose.yml;
echo "      - \"80:80\"" >> ./CTFd/docker-compose.yml;
echo "      - \"443:443\"" >> ./CTFd/docker-compose.yml;
echo "    volumes:" >> ./CTFd/docker-compose.yml;
echo "      - .data/nginx:/var/log/nginx" >> ./CTFd/docker-compose.yml;
echo "      - ../nginx/reverse-proxy.template:/etc/nginx/reverse-proxy.template" >> ./CTFd/docker-compose.yml;
echo "      - ../nginx/cert.crt:/etc/nginx/cert.crt" >> ./CTFd/docker-compose.yml;
echo "      - ../nginx/cert.key:/etc/nginx/cert.key" >> ./CTFd/docker-compose.yml;
echo "    depends_on:" >> ./CTFd/docker-compose.yml;
echo "      - ctfd" >> ./CTFd/docker-compose.yml;
echo "" >> ./CTFd/docker-compose.yml;

echo "Added NGINX service as reverse proxy (4/4).";

echo "Launching platform...";

# cd $INSTALLPATH

#DEV - CREATE SAMBA SHARE FOR DIRECTORY CTFd (easy log access)
#apt-get install samba -y;
#echo "$FILE_SHARE" >> "$SAMBA_CONFIG";
#fill in password & confirm for the smbpasswd command
#echo -ne "$SAMBA_PASS\n$SAMBA_PASS\n" | smbpasswd -a -s $SAMBA_USER;
#service smbd restart;

#cleanup apt
apt-get clean

#cleanup shell history
history -w
history -c

cd $INSTALLPATH/CTFd

#LAUNCH PLATFORM IN DOCKER CONTAINER WITH GUNICORN
if ! docker-compose up
then
    echo "Unable to launch containers. Exiting...";
    exit 1;
fi


echo "The platform can be reached on https://$CTF_IP.";
#------------------------------------------------------------------------------------------------------------------#