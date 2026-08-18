Install `sudo` and add user to `sudo` group:

Run:

```bash
su -
```

Then run code below replacing `USER` with your username:

```bash
wget -qO- https://raw.githubusercontent.com/gitcodedevlab/linuxscripts/main/setup_sudo.sh | bash -s -- "USER"
```
