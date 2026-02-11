# 🚀 My Custom Fedora Bootc Image

This repository contains the "recipe" for the automated build of my operating system image based on **Fedora 43**. The system is immutable, focused on performance with **Nvidia** drivers and the **GNOME** interface.

## 🛠️ Project Architecture

* **Base:** Fedora Linux (version 43)
* **Interface:** GNOME Shell
* **Drivers:** Nvidia (via Negativo17), included in the image
* **Automation:** GitHub Actions with a daily build at **03:45 (Brasília time)**

## 📁 File Structure

| File                   | Function                                                                                           |
| ---------------------- | -------------------------------------------------------------------------------------------------- |
| `Containerfile`        | Build instructions for the image (package and driver installation).                                |
| `pacotes_rpm`          | List of applications and libraries for DNF to install.                                             |
| `post-install.sh`      | Post-install configuration script (removes Fedora Flatpaks, adds Flathub, and installs Flatpaks).  |
| `.github/workflows`    | Contains the GitHub Actions .yml file for automatic builds.                                        |
| `10-nvidia-args.toml`  | Configures parameters to blacklist nouveau.                                                        |
| `post-install.service` | Systemd service to download Flatpaks on first boot after installation.                             |
| `vconsole.conf`        | Configures TTY for pt-BR.                                                                          |
| `locale.conf`          | Sets the system locale to pt-BR.                                                                   |
| `config.toml`          | Defines the Fedora Kickstart file for generating an ISO with Anaconda to install the custom image. |

## ⚙️ How to Update the System

The image is rebuilt daily at **03:45 (Brasília time)**. Since I usually wake up between **07:00 and 08:00**, I already have a fresh update ready to apply in the morning.

I also configured GitHub Actions to integrate with the Telegram bot **@Botfather**, which automatically notifies me on Telegram whenever the image build completes successfully or fails.

![Image](https://i.imgur.com/5Ip7A1N.png)

### Manual Update

1. Open the terminal.
2. Check for updates:

```
sudo bootc upgrade --check
```

3. Perform the upgrade:

```
sudo bootc upgrade
```

4. After rebooting into the new image, check which packages were updated:

```
rpm-ostree db diff
```

5. If changes are present, reboot the machine:

```
sudo reboot
```

## 🛠️ Maintenance Commands

If you need to switch images or check the current state:

* **Check current version:**

```
bootc status
```

* **Rollback to previous version:**

```
sudo bootc rollback
```

* **Switch to this image (first time):**

```
sudo bootc switch container-registry:tag
```

## 🤖 Create a Custom ISO to Install the Bootc Image

### Build the custom image:

```
git clone https://github.com/Ferlinuxdebian/bootc-gnome-minimal.git
cd bootc-gnome-minimal
mkdir output
sudo podman build -t bootc-gnome-minimal -f Containerfile
```

### Create the installation ISO:

```
sudo podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v ./output:/output \
    -v ./config.toml:/config.toml:ro \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type anaconda-iso \
    --rootfs btrfs \
    localhost/bootc-gnome-minimal
```

After the build process, open the `output/bootiso` directory. Inside, you will find an ISO file named **install.iso**, which you can use to install the system.

---
