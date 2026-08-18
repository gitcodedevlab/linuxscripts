Install `sudo` and add user to `sudo` group:

Run:

```bash
su -
```

Then run code below replacing `USER` with your username:

```bash
wget -qO- https://raw.githubusercontent.com/gitcodedevlab/linuxscripts/main/setup_sudo.sh | bash -s -- "USER"
```



Install `Wi-Fi` and connect to a network:

Then run code below replacing `SSID` and `PASS` with your network SSID name and password:

```bash
wget -qO- https://raw.githubusercontent.com/gitcodedevlab/linuxscripts/main/install_wifi.sh | bash -s -- "SSID" "PASS"
```
