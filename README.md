# CTFd setup
<p>CTFd (https://github.com/CTFd/CTFd) will be installed over 4 containers: ctfd (app), db (database), nginx (Reverse proxy) and bind (DNS). Don't forget to configure the variables in the script.</p>
<ol>
	<li>Set up ESXi cluster with vCenter server</li>
	<li>Set up clean Ubuntu 16.04 LTS VM with an interface in VLAN 5, another in VLAN 10 and another in VLAN 15</li>
	<li>git clone https://github.com/FreakyFreddie/CTFd-setup</li>
	<li>Configure variables in CTFd-setup/setup.sh</li>
	<li>sudo bash ./CTFd-setup/setup.sh</li>
</ol>
