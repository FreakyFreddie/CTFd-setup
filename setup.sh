#!/bin/bash
#Use this script to easily set up the CTF Platform on Ubuntu 16.04 LTS
if [ $EUID -ne 0 ]
then
	echo "RUN THE SCRIPT AS ROOT."
	exit 1
fi

#PARAMETERS
SYSTEM_USER="";
CTF_NAME="CTF_Platform";
CTFd_REPOSITORY="https://github.com/CTFd/CTFd";

#CTF NETWORK SETTINGS (users connect to this interface)
CTF_IFACE="ens160";
CTF_IP="192.168.5.4";
CTF_SUBNET="255.255.248.0";
CTF_GATEWAY="192.168.4.1";
CTF_DNS="192.168.4.1";

#VM MANAGEMENT NETWORK SETTINGS (used to manage the VM through SSH)
VM_MANAGEMENT_IFACE="ens192";
VM_MANAGEMENT_IP="192.168.2.4";
VM_MANAGEMENT_SUBNET="255.255.255.0";
VM_MANAGEMENT_GATEWAY="192.168.2.1";

#HYPERVISOR MANAGEMENT NETWORK SETTINGS (used to connect to vCenter server API )
HV_MANAGEMENT_IFACE="ens224";
HV_MANAGEMENT_IP="192.168.1.254";
HV_MANAGEMENT_SUBNET="255.255.255.0";
HV_MANAGEMENT_GATEWAY="192.168.1.1";

#USED TO CONFIGURE DNS SERVER
CTF_DNS_IP="192.168.5.2";

#DNS RECORD
DNS_ROOT="myctf.be";
DNS_NAME="ctf";

#add plugins to install
PLUGINS[0]="https://github.com/tamuctf/ctfd-portable-challenges-plugin";
#PLUGINS[1]="https://github.com/FreakyFreddie/CTFd-challenge-VMs-plugin"

#configuration for samba share (optional/easy way to access logs)
SAMBA_USER="ubuntu"
SAMBA_PASS=""
SAMBA_CONFIG=/etc/samba/smb.conf;
FILE_SHARE="[$CTF_NAME]
path = /home/$SYSTEM_USER/$CTF_NAME
valid users = $SAMBA_USER
read only = no";

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

ifup $CTF_IFACE;

echo "Done.";
echo "Starting VM management interface...";

ifup $VM_MANAGEMENT_IFACE;

echo "Done.";
echo "Starting Hypervisor management interface...";

#DOWN & UP THE INTERFACES
ifup $HV_MANAGEMENT_IFACE;

echo "Done.";
#-----------------------------------------------------------------------------------------------------------------------------------------#
#-------------------------------------------------------------CTFd CONFIGURATION----------------------------------------------------------#

echo "Updating package list & upgrading packages...";

#UPDATES
apt-get update -y;
apt-get upgrade -y;

echo "Done.";
echo "Adding SSH access...";

#ADD SSH ACCESS (optional)
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
echo "Configuring Docker...";

# Add user to the docker group
# Warning: The docker group grants privileges equivalent to the root user. 
usermod -aG docker $SYSTEM_USER;

# Configure Docker to start on boot
systemctl enable docker;

echo "Done.";
echo "Cloning CTFd into home directory...";

#GO TO HOME DIRECTORY
cd /home/$SYSTEM_USER;

#CREATE FILE SHARE MAP
mkdir ./$CTF_NAME

#GO INSIDE NEW SHARE
cd ./$CTF_NAME;

#ADD PLUGINS
mkdir plugins
cd ./plugins
git clone ${CTFd_REPOSITORY};

echo "Done.";
echo "Cloning plugins...";

#still needs work (copy directly into plugin folder)
for i in "${PLUGINS[@]}"
do
   git clone $i;
   echo "Cloned $i.";
done
cd ..
cp -r ./plugins/* ./CTFd/CTFd/plugins/

echo "Done.";
echo "Launching platform...";

#DEV - CREATE SAMBA SHARE FOR DIRECTORY CTFd (easy log access)
#apt-get install samba -y;
#echo "$FILE_SHARE" >> "$SAMBA_CONFIG";
#fill in password & confirm for the smbpasswd command
#echo -ne "$SAMBA_PASS\n$SAMBA_PASS\n" | smbpasswd -a -s $SAMBA_USER;
#service smbd restart;

#LAUNCH PLATFORM IN DOCKER CONTAINER WITH GUNICORN
#CHANGE DOCKER-COMPOSE PASSWORDS
cd CTFd;
docker-compose up;
#-----------------------------------------------------------------------------------------------------------------------------------------#

#SETUP NGINX REVERSE PROXY CONTAINER
#SETUP DNS SERVER CONTAINER
#ADD DNS RECORD

#reset hostname
cat /dev/null > /etc/hostname

#cleanup apt
apt-get clean

#cleanup shell history
history -w
history -c