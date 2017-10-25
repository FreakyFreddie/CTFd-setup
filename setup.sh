#!/bin/bash
#Use this script to easily set up the CTF Platform on Ubuntu 16.04 LTS
if [ $EUID -ne 0 ]
then
	echo "RUN THE SCRIPT AS ROOT.";
	exit 1;
fi

#----------------------------------------------------------PARAMETER DECLARATION----------------------------------------------------------#
SYSTEM_USER="d3nn1s";
SCRIPT_DIRECTORY=$(dirname $(readlink -f $0));
CTFd_REPOSITORY="https://github.com/CTFd/CTFd.git";

#plugins to install
PLUGINS[0]="https://github.com/tamuctf/ctfd-portable-challenges-plugin";
#PLUGINS[1]="https://github.com/FreakyFreddie/CTFd-challenge-VMs-plugin"

#CTF NETWORK SETTINGS (users connect to this interface, VLAN 15)
CTF_IFACE="ens160";
CTF_IP="10.0.7.4";
CTF_SUBNET="255.255.252.0";
CTF_GATEWAY="10.0.4.1";
CTF_DNS="10.0.7.4";

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
CTF_DNS_API_PORT="29375";
#GENERATE RANDOM API KEY OF 32 ALPHANUMERICAL CHARACTERS AND TAKE THE FIRST
CTF_DNS_API_KEY="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)";
#DNS RECORD
CTF_DNS_ROOT="myctf.be";
CTF_NAME="ctf";

#MARIADB CONTAINER CONFIG
MARIADB_ROOT_PASS="CTFd"
MARIADB_USER="CTFd"
MARIADB_PASS="CTFd"

#configuration for samba share (optional/easy way to access logs)
SAMBA_USER=""
SAMBA_PASS=""
SAMBA_CONFIG=/etc/samba/smb.conf;
FILE_SHARE="[$CTF_NAME]
path = /home/$SYSTEM_USER/$CTF_NAME
valid users = $SAMBA_USER
read only = no";

#-----------------------------------------------------------------------------------------------------------------------------------------#
#----------------------------------------------------------NETWORK CONFIGURATION----------------------------------------------------------#
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
#-----------------------------------------------------------------------------------------------------------------------------------------#
#--------------------------------------------------------------PRE INSTALLATION-----------------------------------------------------------#

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
apt-get install python-pip -y;
pip install --upgrade pip;
apt-get install docker -y;
apt-get install docker-compose -y;

echo "Done.";
echo "Configuring Docker to start on boot...";

# Configure Docker daemon to start on boot
if ! systemctl enable docker
then
    echo "Unable to configure Docker to start on boot. Exiting...";
    exit 1;
fi

echo "Done.";

#-----------------------------------------------------------------------------------------------------------------------------------------#
#--------------------------------------------------------DNS CONTAINER CONFIGURATION------------------------------------------------------#
# Generate Docker file with environment variables set

echo "Generating Docker configuration for DNS container...";

#if system user's directory does not exists, exit
if [ ! -d /home/$SYSTEM_USER ]; then
	echo "Error: User $SYSTEM_USER home directory not found. Create /home/$SYSTEM_USER and try again."
   	exit 1;
fi

#if bind directory does not exists, move bind directory there
if [ ! -d /home/$SYSTEM_USER/bind ]; then
    mv $SCRIPT_DIRECTORY/bind /home/$SYSTEM_USER/bind;
fi

#GO TO HOME DIRECTORY
cd /home/$SYSTEM_USER;

touch ./bind/Dockerfile
echo "FROM debian:latest" >> ./bind/Dockerfile;
echo "ENV CTF_IP=$CTF_IP" >> ./bind/Dockerfile;
echo "ENV CTF_DNS_IP=$CTF_DNS_IP" >> ./bind/Dockerfile;
echo "ENV CTF_REVERSE_DNS=$CTF_REVERSE_DNS" >> ./bind/Dockerfile;
echo "ENV CTF_DNS_API_PORT=$CTF_DNS_API_PORT" >> ./bind/Dockerfile;
echo "ENV CTF_DNS_API_KEY=$CTF_DNS_API_KEY" >> ./bind/Dockerfile;
echo "ENV CTF_DNS_ROOT=$CTF_DNS_ROOT" >> ./bind/Dockerfile;
echo "ENV CTF_NAME=$CTF_NAME" >> ./bind/Dockerfile;
echo "RUN apt-get update && apt-get upgrade -y && apt-get install -y bind9" >> ./bind/Dockerfile;
echo "COPY entrypoint.sh /sbin/entrypoint.sh" >> ./bind/Dockerfile;
echo "RUN chmod 755 /sbin/entrypoint.sh" >> ./bind/Dockerfile;
echo "ENTRYPOINT [\"/sbin/entrypoint.sh\"]" >> ./bind/Dockerfile;
echo "Done.";

#-----------------------------------------------------------------------------------------------------------------------------------------#
#------------------------------------------------------------CTF CONFIGURATION------------------------------------------------------------#

echo "Cloning CTFd into home directory...";

if ! git clone ${CTFd_REPOSITORY}
then
	echo "git clone ${CTFd_REPOSITORY} failed. Exiting...";
    exit 1;
fi

echo "Done.";
echo "Recreating docker-compose.yml with new configuration...";

echo "version: '2'" > ./CTFd/docker-compose.yml;
echo "" >> ./CTFd/docker-compose.yml;
echo "services:" >> ./CTFd/docker-compose.yml;
echo "  ctfd:" >> ./CTFd/docker-compose.yml;
echo "    build: ." >> ./CTFd/docker-compose.yml;
echo "    restart: always" >> ./CTFd/docker-compose.yml;
echo "    ports:" >> ./CTFd/docker-compose.yml;
echo "      - \"8000:8000\"" >> ./CTFd/docker-compose.yml;
echo "    environment:" >> ./CTFd/docker-compose.yml;
echo "      - DATABASE_URL=mysql+pymysql://root:$MARIADB_USER@db/ctfd" >> ./CTFd/docker-compose.yml;
echo "    volumes:" >> ./CTFd/docker-compose.yml;
echo "      - .data/CTFd/logs:/opt/CTFd/CTFd/logs" >> ./CTFd/docker-compose.yml;
echo "      - .data/CTFd/uploads:/opt/CTFd/CTFd/uploads" >> ./CTFd/docker-compose.yml;
echo "    depends_on:" >> ./CTFd/docker-compose.yml;
echo "      - db" >> ./CTFd/docker-compose.yml;
echo "      - bind" >> ./CTFd/docker-compose.yml;
echo "" >> ./CTFd/docker-compose.yml;

echo "Added CTFd service (1/3).";

echo "  db:" >> ./CTFd/docker-compose.yml;
echo "    image: mariadb:10.2" >> ./CTFd/docker-compose.yml;
echo "    restart: always" >> ./CTFd/docker-compose.yml;
echo "    environment:" >> ./CTFd/docker-compose.yml;
echo "      - MYSQL_ROOT_PASSWORD=$MARIADB_ROOT_PASS" >> ./CTFd/docker-compose.yml;
echo "      - MYSQL_USER=$MARIADB_USER" >> ./CTFd/docker-compose.yml;
echo "      - MYSQL_PASSWORD=$MARIADB_PASS" >> ./CTFd/docker-compose.yml;
echo "    volumes:" >> ./CTFd/docker-compose.yml;
echo "      - .data/mysql:/var/lib/mysql" >> ./CTFd/docker-compose.yml;
echo "" >> ./CTFd/docker-compose.yml;

echo "Added db service (2/3).";

echo "  bind:" >> ./CTFd/docker-compose.yml;
echo "    build: /home/$SYSTEM_USER/bind/" >> ./CTFd/docker-compose.yml;
echo "    restart: always" >> ./CTFd/docker-compose.yml;
echo "    ports:" >> ./CTFd/docker-compose.yml;
echo "      - \"53:53/udp\"" >> ./CTFd/docker-compose.yml;
echo "      - \"53:53/tcp\"" >> ./CTFd/docker-compose.yml;
echo "      - \"$CTF_DNS_API_PORT:$CTF_DNS_API_PORT\"" >> ./CTFd/docker-compose.yml;
echo "    volumes:" >> ./CTFd/docker-compose.yml;
echo "      - .data/bind:/var/log/bind9" >> ./CTFd/docker-compose.yml;

echo "Added bind service (3/3).";
echo "Cloning plugins...";

cd ./CTFd/CTFd/plugins;

#still needs work (copy directly into plugin folder)
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
#-----------------------------------------------------------------------------------------------------------------------------------------#

#SETUP NGINX REVERSE PROXY CONTAINER
#SETUP DNS SERVER CONTAINER
#ADD DNS RECORD

echo "The platform can be reached on https://$CTF_IP:8000.";

#cleanup apt
apt-get clean

#cleanup shell history
history -w
history -c
