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
SYSTEM_USER="d3nn1s";
SCRIPT_DIRECTORY=$(dirname $(readlink -f $0));
CTFd_REPOSITORY="https://github.com/CTFd/CTFd.git";

#plugins to install
PLUGINS[0]="https://github.com/tamuctf/ctfd-portable-challenges-plugin";
PLUGINS[1]="https://github.com/FreakyFreddie/challengevms";

#themes to install
THEMES[0]="https://github.com/ColdHeat/UnitedStates"

#CTF NETWORK SETTINGS (users connect to this interface, VLAN 15)
CTF_IFACE="ens160";
CTF_IP="10.0.7.4";
CTF_SUBNET="255.255.252.0";
CTF_GATEWAY="10.0.4.1";
CTF_NETWORK="10.0.4.0";
CTF_DNS="10.0.4.1";

#VM MANAGEMENT NETWORK SETTINGS (used to manage the VM through SSH, VLAN 10)
VM_MANAGEMENT_IFACE="ens192";
VM_MANAGEMENT_IP="192.168.2.4";
VM_MANAGEMENT_SUBNET="255.255.255.0";
VM_MANAGEMENT_GATEWAY="192.168.2.1";

#HYPERVISOR MANAGEMENT NETWORK SETTINGS (used to connect to vCenter server API, VLAN 5)
HV_MANAGEMENT_IFACE="ens224";
HV_MANAGEMENT_IP="192.168.1.254";
HV_MANAGEMENT_SUBNET="255.255.255.0";
HV_MANAGEMENT_GATEWAY="192.168.1.1";

#USED TO CONFIGURE DNS CONTAINER
CTF_DNS_IP="10.0.7.4";
CTF_REVERSE_DNS=$(echo $CTF_DNS_IP | awk -F . '{print $3"."$2"."$1".in-addr.arpa"}');
#DNS RECORD
CTF_DNS_ROOT="myctf.be";
CTF_NAME="ctf";

#MARIADB CONTAINER CONFIG
MARIADB_ROOT_PASS="CTFd";
MARIADB_USER="CTFd";
MARIADB_PASS="CTFd";

#redis URL
CACHE_REDIS_URL="redis://redis:redis@localhost:6379";

#configuration for samba share (optional/easy way to access logs)
SAMBA_USER=""
SAMBA_PASS=""
SAMBA_CONFIG=/etc/samba/smb.conf;
FILE_SHARE="[$CTF_NAME]
path = /home/$SYSTEM_USER/$CTF_NAME
valid users = $SAMBA_USER
read only = no";

#-------------------------------------------------------------------------------------------------#
#--------------------------------------NETWORK CONFIGURATION--------------------------------------#
echo "Removing automaticly configured interfaces to CTF Platform networks...";

#ERASE AUTOMATIC CONFIGURATION FROM /etc/network/interfaces
sed -i "/$CTF_IFACE/d" /etc/network/interfaces;
sed -i "/$VM_MANAGEMENT_IFACE/d" /etc/network/interfaces;
sed -i "/$HV_MANAGEMENT_IFACE/d" /etc/network/interfaces;

echo "Done.";
echo "Configuring CTF Platform network interfaces..."

#Bring down interfaces
ifdown $CTF_IFACE;
ifdown $VM_MANAGEMENT_IFACE;
ifdown $HV_MANAGEMENT_IFACE;

#flush intefaces to prevent DHCP issues
ip addr flush dev $CTF_IFACE;
ip addr flush dev $VM_MANAGEMENT_IFACE;
ip addr flush dev $HV_MANAGEMENT_IFACE;

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

#gateway is omitted, add if present
echo "auto $VM_MANAGEMENT_IFACE" >> /etc/network/interfaces;
echo "iface $VM_MANAGEMENT_IFACE inet static" >> /etc/network/interfaces;
echo "address $VM_MANAGEMENT_IP" >> /etc/network/interfaces;
echo "netmask $VM_MANAGEMENT_SUBNET" >> /etc/network/interfaces;
echo "" >> /etc/network/interfaces;

echo "VM management network configured. (2/3)";

#gateway is omitted, add if present
echo "auto $HV_MANAGEMENT_IFACE" >> /etc/network/interfaces;
echo "iface $HV_MANAGEMENT_IFACE inet static" >> /etc/network/interfaces;
echo "address $HV_MANAGEMENT_IP" >> /etc/network/interfaces;
echo "netmask $HV_MANAGEMENT_SUBNET" >> /etc/network/interfaces;
echo "" >> /etc/network/interfaces;

echo "Hypervisor management network configured. (3/3)";
echo "Starting CTF network interface...";

if ! ifup $CTF_IFACE;
then
    echo "Unable to bring up $CTF_IFACE. Exiting...";
    exit 1;
fi

echo "Done.";
echo "Starting VM management interface...";

if ! ifup $VM_MANAGEMENT_IFACE;
then
    echo "Unable to bring up $VM_MANAGEMENT_IFACE. Exiting...";
    exit 1;
fi

echo "Done.";
echo "Starting Hypervisor management interface...";

if ! ifup $HV_MANAGEMENT_IFACE;
then
    echo "Unable to bring up $HV_MANAGEMENT_IFACE. Exiting...";
    exit 1;
fi

echo "Done.";
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
apt-get update;

if ! apt-get upgrade -y;
then
    echo "Unable to upgrade packages. Exiting...";
    exit 1;
fi

echo "Done.";

#ADD SSH ACCESS (optional)
echo "Adding SSH access...";
apt-get install openssh-server -y;
echo "Done.";

echo "Installing CTFd dependencies...";

#INSTALL DEPENDENCIES
apt-get install git -y;
#apt-get install python-pip -y;
#pip install --upgrade pip;
apt-get install docker -y;
apt-get install docker-compose -y;
apt-get install bind9 -y;
apt-get install mariadb-client-10.0 -y;

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

#if system user's directory does not exists, exit
if [ ! -d /home/$SYSTEM_USER ]; then
	echo "Error: User $SYSTEM_USER home directory not found. Create /home/$SYSTEM_USER and try again.";
   	exit 1;
fi

#if bind directory does not exists, move bind directory there
if [ ! -d /home/$SYSTEM_USER/bind ]; then
    mv $SCRIPT_DIRECTORY/bind /home/$SYSTEM_USER/bind;
fi

#GO TO HOME DIRECTORY
cd /home/$SYSTEM_USER;

#generate TSIG for API
dnssec-keygen -r /dev/urandom -a HMAC-MD5 -b 512 -n HOST $CTF_DNS_ROOT;
CTF_DNS_TSIG_KEY=$(cat ./*.key | cut -d\  -f7-);

touch ./bind/Dockerfile
echo "FROM debian:latest" >> ./bind/Dockerfile;
echo "ENV CTF_IP=$CTF_IP" >> ./bind/Dockerfile;
echo "ENV CTF_DNS_IP=$CTF_DNS_IP" >> ./bind/Dockerfile;
echo "ENV CTF_REVERSE_DNS=$CTF_REVERSE_DNS" >> ./bind/Dockerfile;
echo "ENV CTF_DNS_TSIG_KEY=$CTF_DNS_TSIG_KEY" >> ./bind/Dockerfile;
echo "ENV CTF_DNS_ROOT=$CTF_DNS_ROOT" >> ./bind/Dockerfile;
echo "ENV CTF_NAME=$CTF_NAME" >> ./bind/Dockerfile;
echo "RUN apt-get update && apt-get upgrade -y && apt-get install -y bind9 && apt-get" >> ./bind/Dockerfile;
echo "COPY entrypoint.sh /sbin/entrypoint.sh" >> ./bind/Dockerfile;
echo "RUN chmod 755 /sbin/entrypoint.sh" >> ./bind/Dockerfile;
echo "EXPOSE 53" >> ./bind/Dockerfile;
echo "ENTRYPOINT [\"/sbin/entrypoint.sh\"]" >> ./bind/Dockerfile;
echo "Done.";

#-----------------------------------------------------------------------------------------------------#
#--------------------------------------NGINX CONTAINER CONFIGURATION----------------------------------#
# Generate Docker file with environment variables set

echo "Generating Docker configuration for NGINX container...";

#if nginx directory does not exists, move nginx directory there
if [ ! -d /home/$SYSTEM_USER/nginx ]; then
    mv $SCRIPT_DIRECTORY/nginx /home/$SYSTEM_USER/nginx;
fi

#GENERATE CERTIFICATE

touch ./nginx/Dockerfile
echo "FROM nginx:latest" >> ./nginx/Dockerfile;
echo "ENV CTF_IP=$CTF_IP" >> ./nginx/Dockerfile;
echo "ENV CTF_DNS_IP=$CTF_DNS_IP" >> ./nginx/Dockerfile;
echo "ENV CTF_REVERSE_DNS=$CTF_REVERSE_DNS" >> ./nginx/Dockerfile;
echo "ENV CTF_DNS_TSIG_KEY=$CTF_DNS_TSIG_KEY" >> ./nginx/Dockerfile;
echo "ENV CTF_DNS_ROOT=$CTF_DNS_ROOT" >> ./nginx/Dockerfile;
echo "ENV CTF_NAME=$CTF_NAME" >> ./nginx/Dockerfile;
echo "RUN apt-get update && apt-get upgrade -y && apt-get install -y bind9 && apt-get" >> ./nginx/Dockerfile;
echo "COPY entrypoint.sh /sbin/entrypoint.sh" >> ./nginx/Dockerfile;
echo "RUN chmod 755 /sbin/entrypoint.sh" >> ./nginx/Dockerfile;
echo "EXPOSE 443" >> ./nginx/Dockerfile;
echo "ENTRYPOINT [\"/sbin/entrypoint.sh\"]" >> ./nginx/Dockerfile;
echo "Done.";

#-----------------------------------------------------------------------------------------------------#
#--------------------------------------REDIS CONTAINER CONFIGURATION----------------------------------#
# Generate Docker file with environment variables set

echo "Generating Docker configuration for NGINX container...";

#if redis directory does not exists, move redis directory there
if [ ! -d /home/$SYSTEM_USER/redis ]; then
    mv $SCRIPT_DIRECTORY/redis /home/$SYSTEM_USER/redis;
fi

touch ./redis/Dockerfile
echo "FROM redis:latest" >> ./redis/Dockerfile;
echo "COPY redis.conf /usr/local/etc/redis/redis.conf" >> ./redis/Dockerfile;
echo "CMD [ \"redis-server\", \"/usr/local/etc/redis/redis.conf\" ]" >> ./redis/Dockerfile;
echo "Done.";

#-----------------------------------------------------------------------------------------------------#
#------------------------------------------CTF CONFIGURATION------------------------------------------#
echo "Cloning CTFd into home directory...";

if ! git clone ${CTFd_REPOSITORY}
then
	echo "git clone ${CTFd_REPOSITORY} failed. Exiting...";
    exit 1;
fi

echo "Done.";
#echo "Adding cloning vSphere api and adding requirements to CTFd requirements.txt...";

#if ! git -C /home/$SYSTEM_USER clone https://github.com/vmware/vsphere-automation-sdk-python
#then
#	echo "git clone https://github.com/vmware/vsphere-automation-sdk-python failed. Exiting...";
#    exit 1;
#fi

#echo $(cat ./vsphere-automation-sdk-python/requirements.txt) >> ./CTFd/requirements.txt;

#ADD VSPHERE API REQUIREMENTS TO FILE

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
#echo "" >> ./CTFd/Dockerfile;
#echo "COPY /home/$SYSTEM_USER/vsphere-automation-sdk-python/lib /opt/vsphere-automation-sdk-python/lib" >> ./CTFd/Dockerfile;
echo "" >> ./CTFd/Dockerfile;
echo "WORKDIR /opt/CTFd" >> ./CTFd/Dockerfile;
echo "" >> ./CTFd/Dockerfile;
echo "VOLUME ["/opt/CTFd"]" >> ./CTFd/Dockerfile;
echo "" >> ./CTFd/Dockerfile;
echo "RUN pip3 install -r requirements.txt" >> ./CTFd/Dockerfile; #also install vsphere API dependencies# --extra-index-url /opt/vsphere-automation-sdk-python/lib"
echo "" >> ./CTFd/Dockerfile;
echo "RUN chmod +x /opt/CTFd/docker-entrypoint.sh" >> ./CTFd/Dockerfile;
echo "" >> ./CTFd/Dockerfile;
echo "EXPOSE 8000" >> ./CTFd/Dockerfile;
echo "" >> ./CTFd/Dockerfile;
echo "ENTRYPOINT ["/opt/CTFd/docker-entrypoint.sh"]" >> ./CTFd/Dockerfile;

echo "Done.";
echo "Adding self-signed certificate to parameters of gunicorn launch...";

APPEND=" --keyfile '/opt/CTFd/key.pem' --certfile '/opt/CTFd/cert.pem'";
echo "$(cat docker-entrypoint.sh)$APPEND" > docker-entrypoint.sh;

echo "Done.";
echo "Recreating docker-compose.yml with new configuration...";

echo "version: '2'" > ./CTFd/docker-compose.yml;
echo "" >> ./CTFd/docker-compose.yml;
echo "services:" >> ./CTFd/docker-compose.yml;
echo "  ctfd:" >> ./CTFd/docker-compose.yml;
echo "    build: ." >> ./CTFd/docker-compose.yml;
echo "    restart: always" >> ./CTFd/docker-compose.yml;
echo "    expose:" >> ./CTFd/docker-compose.yml;
echo "      - \"8000\"" >> ./CTFd/docker-compose.yml;
echo "    environment:" >> ./CTFd/docker-compose.yml;
echo "      - DATABASE_URL=mysql+pymysql://root:$MARIADB_ROOT_PASS@db/ctfd" >> ./CTFd/docker-compose.yml;
echo "      - CTF_DNS_TSIG_KEY=$CTF_DNS_TSIG_KEY" >> ./CTFd/docker-compose.yml;
echo "      - CACHE_REDIS_URL=$CACHE_REDIS_URL" >> ./CTFd/docker-compose.yml;
echo "    volumes:" >> ./CTFd/docker-compose.yml;
echo "      - .data/CTFd/logs:/opt/CTFd/CTFd/logs" >> ./CTFd/docker-compose.yml;
echo "      - .data/CTFd/uploads:/opt/CTFd/CTFd/uploads" >> ./CTFd/docker-compose.yml;
echo "    depends_on:" >> ./CTFd/docker-compose.yml;
echo "      - db" >> ./CTFd/docker-compose.yml;
echo "      - bind" >> ./CTFd/docker-compose.yml;
echo "" >> ./CTFd/docker-compose.yml;

echo "Added CTFd service (1/5).";

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

echo "Added db service (2/5).";

echo "  bind:" >> ./CTFd/docker-compose.yml;
echo "    build: /home/$SYSTEM_USER/bind/" >> ./CTFd/docker-compose.yml;
echo "    restart: always" >> ./CTFd/docker-compose.yml;
echo "    ports:" >> ./CTFd/docker-compose.yml;
echo "      - \"53:53/udp\"" >> ./CTFd/docker-compose.yml;
echo "      - \"53:53/tcp\"" >> ./CTFd/docker-compose.yml;
echo "    environment:" >> ./CTFd/docker-compose.yml;
echo "      - CTF_DNS_TSIG_KEY=$CTF_DNS_TSIG_KEY" >> ./CTFd/docker-compose.yml;
echo "    volumes:" >> ./CTFd/docker-compose.yml;
echo "      - .data/bind:/var/log/bind9" >> ./CTFd/docker-compose.yml;

echo "Added bind service (3/5).";

echo "  nginx:" >> ./CTFd/docker-compose.yml;
echo "    build: /home/$SYSTEM_USER/nginx/" >> ./CTFd/docker-compose.yml;
echo "    restart: always" >> ./CTFd/docker-compose.yml;
echo "    ports:" >> ./CTFd/docker-compose.yml;
echo "      - \"443:443\"" >> ./CTFd/docker-compose.yml;
echo "    environment:" >> ./CTFd/docker-compose.yml;
echo "      - NGINX_HOST='10.0.7.4'" >> ./CTFd/docker-compose.yml;
echo "      - APP_CONTAINER_ADDRESS='ctfd'" >> ./CTFd/docker-compose.yml;
echo "      - NGINX_PORT='443'" >> ./CTFd/docker-compose.yml;
echo "    volumes:" >> ./CTFd/docker-compose.yml;
echo "      - .data/nginx:/var/log/nginx" >> ./CTFd/docker-compose.yml;
echo "      - ../nginx/reverse-proxy.template:/etc/nginx/conf.d/reverse-proxy.template" >> ./CTFd/docker-compose.yml;
echo "    command: /bin/bash -c \"envsubst < /etc/nginx/conf.d/reverse-proxy.template > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'\"" >> ./CTFd/docker-compose.yml;

echo "Added NGINX service as reverse proxy (4/5).";

echo "  redis:" >> ./CTFd/docker-compose.yml;
echo "    build: /home/$SYSTEM_USER/nginx/" >> ./CTFd/docker-compose.yml;
echo "    restart: always" >> ./CTFd/docker-compose.yml;
echo "    expose:" >> ./CTFd/docker-compose.yml;
echo "      - \"46379\"" >> ./CTFd/docker-compose.yml;
echo "    volumes:" >> ./CTFd/docker-compose.yml;
echo "      - .data/nginx:/var/log/nginx" >> ./CTFd/docker-compose.yml;
echo "      - ../redis/redis.conf:/usr/local/etc/redis/redis.conf" >> ./CTFd/docker-compose.yml;
echo "    command: /bin/bash -c \"envsubst < /etc/nginx/conf.d/reverse-proxy.template > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'\"" >> ./CTFd/docker-compose.yml;

echo "Added redis service (5/5).";
#redis cache container to be added /myredis/conf/redis.conf:/usr/local/etc/redis/redis.conf

echo "Generating self-signed certificate...";

cd CTFd;
openssl req -x509 -newkey rsa:4096 -passout pass:notreallyneeded -keyout key.pem -out cert.pem -days 365 -subj '/CN=ctf.tm.be/O=EvilCorp LTD./C=BE';
# Remove the pass phrase on RSA private key:
openssl rsa -passin pass:notreallyneeded -in key.pem -out key.pem;

echo "Done.";

echo "Cloning plugins...";

cd ./CTFd/plugins;

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

cd ../themes;

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
echo "Launching platform...";

cd ../..;

#DEV - CREATE SAMBA SHARE FOR DIRECTORY CTFd (easy log access)
#apt-get install samba -y;
#echo "$FILE_SHARE" >> "$SAMBA_CONFIG";
#fill in password & confirm for the smbpasswd command
#echo -ne "$SAMBA_PASS\n$SAMBA_PASS\n" | smbpasswd -a -s $SAMBA_USER;
#service smbd restart;

#LAUNCH PLATFORM IN DOCKER CONTAINER WITH GUNICORN
#CHANGE DOCKER-COMPOSE PASSWORDS
cd CTFd;

if ! docker-compose -d up
then
    echo "Unable to launch containers. Exiting...";
    exit 1;
fi
#------------------------------------------------------------------------------------------------------------------#

# OPTIONAL: SETUP NGINX REVERSE PROXY CONTAINER (to be added)

echo "The platform can be reached on https://$CTF_IP.";

#bind was only needed to generate TSIG
apt-get remove bind9 -y;

#cleanup apt
apt-get clean

#cleanup shell history
history -w
history -c