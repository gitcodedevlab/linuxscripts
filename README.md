# Linux Scripts 🐧

A collection of simple Bash scripts to automate common Linux setup and configuration tasks.

---

## 📋 Requirements

Before running the scripts, make sure you have:

- A Linux system
- Internet connection
- `root` access when required
- `wget` installed

---

## 🚀 Scripts

### 🔐 Install `sudo`

Install sudo and adds a user to the `sudo` group.

#### 1. Switch to root

```bash
su -
```

#### 2. Run the script

Replace `USER` with your username:

```bash
wget -qO- https://raw.githubusercontent.com/gitcodedevlab/linuxscripts/main/setup_sudo.sh | bash -s -- "USER"
```

---

### 📡 Install and Configure Wi-Fi v2 (Recommended)

Installs the required Wi-Fi components and connects to a wireless network.

Command will automatically asks for SSID and password:

```bash
wget -qO- https://raw.githubusercontent.com/gitcodedevlab/linuxscripts/main/install_wifi_v2.sh | sudo bash
```

---

### ⌨️ Install and Configure Keyboard keys for MacBook Mid 2012

Installs the required keyboard and events to set Screen brightness and keyboard backlight

```bash
wget -qO- https://raw.githubusercontent.com/gitcodedevlab/linuxscripts/main/macbook_keyboard_setup.sh | sudo bash
```

---

## ⚠️ Security Notice

These scripts execute commands directly on your Linux system.

**Always review the source code before running scripts downloaded from the internet**, especially when using `root` or `sudo`.

---

## 📁 Available Scripts

| Script | Description |
|---|---|
| `setup_sudo.sh` | Adds a user to the `sudo` group |
| `install_wifi.sh` | Installs and configures Wi-Fi |
| `macbook_keyboard_setup.sh` | Install and Configure Keyboard keys for MacBook Mid 2012 |

More scripts will be added over time.

---

## 🛠️ Usage

All scripts can be executed directly from the GitHub repository using `wget`.

You can also clone the repository and run the scripts locally:

```bash
git clone https://github.com/gitcodedevlab/linuxscripts.git
```

Then run the desired script:

```bash
sudo ./script.sh "PARAM1" "PARAM2"
```
