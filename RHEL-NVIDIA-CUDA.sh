
###################################################################
#
# Date:
# April 12, 2023
#
# Description:
# This Script is intended for Installing NVIDIA and CUDA 
#
# Version:
# 1.0
#
# Author:
# Peter Aldrich
#
#########

#!/bin/bash
source nvidia-content.ini

check_os(){
	# Check that user is running a supported distribution
	if ! . /etc/redhat-release; then
		fatal "NVIDIA Installs: No /etc/redhat-release file. Unable to detect distribution."

	elif [ "$OS_NAME" != "Rocky" ]&& [ "$OS_NAME" != "RedHat" ]; then
		stderr "NIVDIA CUDAinstall: '$OS_NAME' is not a supported software distribution."
		fatal "NVIDIA CUDA presently only supports ROCKY/RHEL"

	elif [ "$OS_VERSION" != "8.9" ] && [ "$OS_VERSION" != "9.3" ]; then
		stderr "nvidia-cuda-install: 'ROCKY/RHEL $OS_VERSION' is not a supported Rocky/RedHat release."
		fatal "nvidia cuda drivers only supports Rocky/RedHat 8.9 & 9.3."
	fi
}

uninstall_driver(){

        # Check if NVIDIA drivers are installed
    if nvidia-smi &>/dev/null; then
        echo "NVIDIA drivers are installed. Uninstalling..."
        ${remove} nvidia-*
        ${module} remove --all nvidia-driver
        ${module} reset nvidia-driver
    else
        echo "NVIDIA drivers are not installed."
    fi

    # Check if CUDA drivers are installed
    if nvcc --version &>/dev/null; then
        echo "CUDA drivers are installed. Uninstalling..."
        ${remove} cuda* -y
    else
        echo "CUDA drivers are not installed."
    fi
}

install_driver(){
	# Install prerequisites
	stderr "Installing prerequisites."
	${update}
	${install} pciutils wget -y 

	# Install RPMS
	stderr "Installing NVIDIA RPM."
	wget --quiet -O "${NVIDIA_REPO_URL}"
    ${install} ./${nvidia-driver-rpm}
	rm -f "${nvidia-driver-rpm}"

	stderr "Installing RPM."
	wget --quiet -O"${CUDA_REPO_URL}"
    ${install} ./${cuda-nvidia-rpm}
	rm -f "${cuda-nvidia-rpm}"

    ${module} install -y nvidia-driver:${nversion}-dkms
	${update}

}

reboot(){

while "$bool"=true
do
echo -e " "
echo -e "Do you want to reboot:"
echo -e "----------------------"
echo -e "  1.) Not Reboot"
echo -e "  0.) Reboot"

read rebootoptions
echo -e " "

case $optionsSet1 in
  1) echo -e " NOT REBOOTING"
     $bool=false

  2) echo -e "REBOOTING"
     reboot now
     $bool=false
  0)
  break
  ;;

esac
done



}

main() {

check_os

uninstall_driver

install_driver

reboot

}

main
