#!/bin/bash

# Function to detect Linux distribution and version
detect_distro() {
  if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    DISTRO=$NAME
    VERSION=$VERSION_ID
  elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    DISTRO=$(lsb_release -si)
    VERSION=$(lsb_release -sr)
  elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    DISTRO=$DISTRIB_ID
    VERSION=$DISTRIB_RELEASE
  elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    DISTRO=Debian
    VERSION=$(cat /etc/debian_version)
  elif [ -f /etc/SuSe-release ]; then
    # Older SuSE/etc.
    ...
  elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    ...
  else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    DISTRO=$(uname -s)
    VERSION=$(uname -r)
  fi

  # Export the variables to make them available globally
  export DISTRO
  export VERSION
}

# Call the function to detect distribution
detect_distro

# Print the detected distribution and version
echo "Detected Distribution: $DISTRO"
echo "Detected Version: $VERSION"

# Function to check for existing NVIDIA drivers
check_existing_drivers() {
  NVIDIA_DRIVERS_INSTALLED=false
  if command -v nvidia-smi &> /dev/null; then
    NVIDIA_DRIVERS_INSTALLED=true
  elif lsmod | grep -qw nvidia; then
    NVIDIA_DRIVERS_INSTALLED=true
  fi
  export NVIDIA_DRIVERS_INSTALLED
}

# Call the function to check for existing drivers
check_existing_drivers

# Print message based on driver status
if [ "$NVIDIA_DRIVERS_INSTALLED" = true ]; then
  echo "NVIDIA drivers appear to be already installed."
  # Potentially exit here if drivers are already installed, or offer to reinstall
  # For now, we'll proceed, assuming a reinstall or update might be desired.
else
  echo "No NVIDIA drivers detected. Proceeding with dependency installation."
fi

# Function to install dependencies
install_dependencies() {
  echo "Installing dependencies for $DISTRO..."
  local lower_distro
  lower_distro=$(echo "$DISTRO" | tr '[:upper:]' '[:lower:]')

  case "$lower_distro" in
    ubuntu|debian)
      echo "Using apt-get to install build-essential dkms linux-headers-$(uname -r)"
      sudo apt-get update && sudo apt-get install -y build-essential dkms linux-headers-$(uname -r)
      ;;
    fedora)
      echo "Using dnf to install kernel-devel kernel-headers dkms gcc make"
      sudo dnf install -y kernel-devel kernel-headers dkms gcc make
      ;;
    centos)
      echo "Using yum to install kernel-devel kernel-headers dkms gcc make"
      # For CentOS, ensure EPEL is enabled for DKMS if not in base repo
      # sudo yum install -y epel-release # Uncomment if dkms is in EPEL
      sudo yum install -y kernel-devel kernel-headers dkms gcc make
      ;;
    *)
      echo "Unsupported distribution: $DISTRO for automatic dependency installation."
      echo "Please install the necessary dependencies manually: build-essential (or equivalent like gcc, make), dkms, and kernel headers for your current kernel."
      exit 1
      ;;
  esac

  if [ $? -ne 0 ]; then
    echo "Dependency installation failed. Please check the errors above."
    exit 1
  fi
  echo "Dependencies installed successfully."
}

# Call the function to install dependencies if drivers are not already installed
# (or if we decide to proceed regardless of existing drivers for update/reinstall)
if [ "$NVIDIA_DRIVERS_INSTALLED" = false ]; then
  install_dependencies

  # Function to download the NVIDIA driver
  download_nvidia_driver() {
    echo "Automatic NVIDIA driver detection from web is not yet supported."
    echo "Please provide a direct download URL for the NVIDIA driver .run file."
    read -p "Enter driver download URL: " DRIVER_URL

    if [ -z "$DRIVER_URL" ]; then
      echo "No download URL provided. Cannot proceed with driver installation."
      exit 1
    fi

    echo "Downloading NVIDIA driver from $DRIVER_URL..."
    if command -v wget &> /dev/null; then
      wget -O nvidia_driver.run "$DRIVER_URL"
    elif command -v curl &> /dev/null; then
      curl -L -o nvidia_driver.run "$DRIVER_URL"
    else
      echo "Error: Neither wget nor curl is available to download the driver."
      echo "Please install wget or curl and try again."
      exit 1
    fi

    if [ $? -ne 0 ]; then
      echo "Driver download failed. Please check the URL and your internet connection."
      # Clean up partially downloaded file if it exists
      [ -f nvidia_driver.run ] && rm nvidia_driver.run
      exit 1
    fi

    if [ ! -s nvidia_driver.run ]; then
        echo "Downloaded file nvidia_driver.run is empty. This might be due to an incorrect URL or network issue."
        rm nvidia_driver.run
        exit 1
    fi

    echo "NVIDIA driver downloaded successfully as nvidia_driver.run."
  }

  download_nvidia_driver

  # Function to prepare the system for NVIDIA driver installation
  prepare_for_installation() {
    echo "Preparing for NVIDIA driver installation..."
    NOUVEAU_LOADED=$(lsmod | grep nouveau)
    if [ -n "$NOUVEAU_LOADED" ]; then
      echo "Nouveau driver is loaded. Attempting to blacklist it."
      echo -e "blacklist nouveau\noptions nouveau modeset=0" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
      if [ $? -eq 0 ]; then
        echo "Successfully created /etc/modprobe.d/blacklist-nouveau.conf."
        echo "IMPORTANT: You may need to update your initramfs and reboot for the blacklist to take full effect."
        local lower_distro
        lower_distro=$(echo "$DISTRO" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_distro" == "ubuntu" || "$lower_distro" == "debian" ]]; then
          echo "Run 'sudo update-initramfs -u' then 'sudo reboot'."
        elif [[ "$lower_distro" == "fedora" || "$lower_distro" == "centos" || "$lower_distro" == "rhel" ]]; then
          echo "Run 'sudo dracut --force' then 'sudo reboot'."
        else
          echo "Please consult your distribution's documentation on how to update initramfs and then reboot."
        fi
        echo "After rebooting, re-run this script. It will detect that drivers are not yet installed and skip to the installation step."
        # It's better to exit here and let the user reboot and re-run.
        # The script will then skip the previous steps.
        exit 0 
      else
        echo "Failed to create blacklist file. Please do this manually."
        exit 1
      fi
    else
      echo "Nouveau driver does not seem to be loaded. Skipping blacklist."
    fi
  }

  prepare_for_installation

  # Function to guide running the NVIDIA installer
  run_nvidia_installer() {
    if [ ! -f nvidia_driver.run ]; then
        echo "NVIDIA driver file (nvidia_driver.run) not found. Please ensure it was downloaded correctly."
        exit 1
    fi
    chmod +x nvidia_driver.run
    echo ""
    echo "---------------------------------------------------------------------"
    echo "IMPORTANT: Manual Installation Steps Required"
    echo "---------------------------------------------------------------------"
    echo "The NVIDIA driver installer must be run from a text-only console (TTY),"
    echo "without an active graphical session (X server or Wayland)."
    echo ""
    echo "1. Exit your graphical session:"
    echo "   - If you are in a desktop environment, log out completely."
    echo "   - Switch to a TTY by pressing Ctrl+Alt+F3 (or F1-F6)."
    echo "   - Log in with your username and password in the TTY."
    echo ""
    echo "2. Navigate to the directory where this script is located: $(pwd)"
    echo ""
    echo "3. Run the NVIDIA installer using the following command:"
    echo "   sudo ./nvidia_driver.run"
    echo ""
    echo "4. Follow the on-screen instructions provided by the NVIDIA installer."
    echo "   - It's generally recommended to allow the installer to register DKMS modules"
    echo "     if prompted. This helps keep the driver working after kernel updates."
    echo "   - The installer might ask to update your X configuration file. Usually, this is safe."
    echo ""
    echo "5. After the installer finishes, it might prompt you to reboot. Please do so if asked."
    echo "---------------------------------------------------------------------"
    echo ""
    echo "This script will now pause. Perform the steps above in a TTY."
    echo "Once the NVIDIA installer has completed AND you have rebooted (if required by the installer),"
    echo "you can proceed with the next step (verification)."
    echo "If you did not need to reboot after installation, you can proceed directly."
    echo ""
    read -p "Have you completed the NVIDIA driver installation in a TTY and rebooted if necessary? (yes/no): " CONFIRMATION
    if [[ "$CONFIRMATION" != "yes" && "$CONFIRMATION" != "YES" ]]; then
      echo "Please complete the installation steps and reboot if needed before proceeding."
      echo "If you re-run this script, it should detect the installed drivers."
      exit 1
    fi
    verify_installation # Call verification right after user confirms
  }

  # Function to verify NVIDIA driver installation
  verify_installation() {
    echo ""
    echo "---------------------------------------------------------------------"
    echo "Verifying NVIDIA Driver Installation"
    echo "---------------------------------------------------------------------"
    
    # Check for nvidia-smi
    if command -v nvidia-smi &> /dev/null; then
      echo "SUCCESS: nvidia-smi command found."
      echo "Displaying NVIDIA driver information:"
      nvidia-smi
    else
      echo "WARNING: nvidia-smi command not found."
      echo "This suggests the NVIDIA driver installation may not have been successful or is not in PATH."
      echo "Please check the NVIDIA installer log for details (usually /var/log/nvidia-installer.log)."
    fi

    echo "" # Add a blank line for better readability

    # Check for NVIDIA kernel modules
    if lsmod | grep -qw nvidia; then
      echo "SUCCESS: NVIDIA kernel modules appear to be loaded."
      echo "Output of lsmod | grep nvidia:"
      lsmod | grep nvidia
    else
      echo "WARNING: NVIDIA kernel modules (e.g., 'nvidia', 'nvidia_uvm', 'nvidia_drm') not found in lsmod output."
      echo "This suggests the kernel modules failed to load."
      echo "Ensure that Secure Boot is disabled in BIOS/UEFI if you haven't signed the modules, or that the modules were built correctly against your kernel."
      echo "Check logs like dmesg or /var/log/nvidia-installer.log for errors."
    fi
    
    echo ""
    echo "---------------------------------------------------------------------"
    echo "Verification complete. If nvidia-smi ran successfully and modules are loaded, the basic installation should be working."
    # Removed the reboot advice from here as it's now in a dedicated function.
    echo "---------------------------------------------------------------------"
  }

  # Function to provide final reboot instructions
  final_reboot_instructions() {
    echo ""
    echo "---------------------------------------------------------------------"
    echo "Final Steps and Reboot Recommendation"
    echo "---------------------------------------------------------------------"
    echo "If you haven't rebooted your system since the NVIDIA driver installation completed, it is highly recommended to do so now."
    echo "A full reboot ensures that all system changes are correctly applied, the new kernel modules are properly loaded,"
    echo "and your graphical environment (X server or Wayland) starts fresh with the NVIDIA drivers."
    echo ""
    if [[ "$(tty)" == /dev/tty[0-9]* ]]; then
      # User is likely in a TTY
      echo "You appear to be in a TTY. You can reboot now by typing: sudo reboot"
      echo "Alternatively, you could try restarting your display manager, but this can sometimes be unreliable."
      echo "Common display manager restart commands (use the one for your system):"
      echo "  - For GDM (GNOME): sudo systemctl restart gdm"
      echo "  - For LightDM (LXDE, XFCE, some Ubuntu spins): sudo systemctl restart lightdm"
      echo "  - For SDDM (KDE Plasma): sudo systemctl restart sddm"
      echo "A full 'sudo reboot' is generally the safest option to ensure everything works correctly."
    else
      # User is likely in a graphical session (e.g., re-ran script from terminal emulator)
      echo "Please save all your work and reboot your system to apply all changes."
      echo "You can typically reboot using your desktop environment's logout/shutdown menu, or by running 'sudo reboot' in a terminal."
    fi
    echo ""
    echo "After rebooting, your NVIDIA drivers should be fully active."
    echo "---------------------------------------------------------------------"
  }

  run_nvidia_installer
  # Call final reboot instructions after the main installation and verification flow
  if [ "$NVIDIA_DRIVERS_INSTALLED" = false ]; then # Check if we went through the install process
      # This check is a bit redundant given the structure, but ensures it only runs if install was attempted.
      # The internal logic of run_nvidia_installer already handles if the user exits early.
      # If verify_installation was called, it means user confirmed install.
      final_reboot_instructions
  fi
fi
# Add a final message for script completion here, outside the if block,
# or ensure all paths within the if block that don't exit print a completion message.
echo ""
echo "NVIDIA Driver Installation Script finished."
# Clean up downloaded driver file if it exists and we are done with it.
if [ -f nvidia_driver.run ]; then
    echo "You may want to remove the downloaded driver file: nvidia_driver.run"
    # For safety, don't automatically remove it, let the user do it.
    # rm nvidia_driver.run
fi
