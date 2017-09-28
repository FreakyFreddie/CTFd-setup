#!/bin/bash
#Use this script to easily set up the CTF Platform
if [$EUID -ne 0]
then
	echo "RUN THE SCRIPT AS ROOT."
	exit 1
fi

#PARAMETERS
SYSTEM_USER="ubuntu";
CTF_NAME="CTF_Platform";
CTFd_REPOSITORY="https://github.com/FreakyFreddie/CTFd";
SAMBA_USER="ubuntu"
SAMBA_PASS="ubuntu"
SAMBA_CONFIG=/etc/samba/smb.conf;
FILE_SHARE="[$CTF_NAME]
path = /home/$SYSTEM_USER/$CTF_NAME
valid users = $SAMBA_USER
read only = no";

#UPDATES
apt-get update -y;
apt-get upgrade -y;

#ADD SSH ACCESS (maybe later)

#INSTALL DEPENDENCIES
apt-get install git -y;
apt-get install python-pip -y;
pip install --upgrade pip;
apt-get install docker -y;
apt-get install docker-compose -y;

# Add user to the docker group
# Warning: The docker group grants privileges equivalent to the root user. 
sudo usermod -aG docker $SYSTEM_USER

# Configure Docker to start on boot
sudo systemctl enable docker

#GO TO HOME DIRECTORY
cd /home/$SYSTEM_USER;

#CREATE FILE SHARE MAP
mkdir ./$CTF_NAME

#DEV - CREATE SAMBA SHARE FOR DIRECTORY
apt-get install samba -y;
echo "$FILE_SHARE" >> "$SAMBA_CONFIG";
#fill in password & confirm for the smbpasswd command
echo -ne "$SAMBA_PASS\n$SAMBA_PASS\n" | smbpasswd -a -s $SAMBA_USER;
service smbd restart;

#GO INSIDE NEW SHARE
cd ./$CTF_NAME

#CLONE REPOSITORY
git clone ${CTFd_REPOSITORY};
cd CTFd;

#The following is executed in the Docker container
#bash ./prepare.sh;
#pip install -r requirements.txt;

#LAUNCH PLATFORM IN DOCKER CONTAINER WITH GUNICORN
docker-compose up;
