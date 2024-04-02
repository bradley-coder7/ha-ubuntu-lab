#!/bin/bash
echo "This script will build the lab environment. It can consume a lot of disk space, RAM, and CPU."
if [[ "root" != "$(whoami)" ]]; then
	echo "This script requires root privileges to execute several commands. Please run with sudo."
	exit 1
fi
if [ ! -f ./id_rsa ]; then
	echo "Generating SSH keypair."
	ssh-keygen -N "" -q -f ./id_rsa
fi

# Get a timestamp for pseudo-random filenames
ts=$(date +%s.%N)
for unit in ./*/;
do
	unit=${unit%*/}
	unit=${unit##*/}
	echo "Building $unit"
	cd $unit
	echo "  Creating a 1G sparse file at $unit.$ts.img"
	dd if=/dev/zero of=$unit.$ts.img bs=1M count=1024 conv=sparse
	echo "  Creating a vfat filesystem with label 'CIDATA' on the $unit.$ts.img"
	mkfs.vfat -n CIDATA $unit.$ts.img
	echo "  Temporarily mounting $unit.$ts.img at $unit/mnt"
	mkdir -p mnt
	mount $unit.$ts.img ./mnt
	if [ -f user-data.yaml ]; then
		echo "    Creating user-data in $unit/mnt"
		cat user-data.yaml | sed -E "s/(.*content: )LAB_PLACEHOLDER_B64 (.*)/echo -n \"\1\" \&\& base64 -w 0 \2/e
			s/(.* )LAB_PLACEHOLDER (.*)/echo -n \"\1\" \&\& cat \2/e" > ./mnt/user-data
	else
		echo "    No user-data.yaml file found. $unit build process failed"
	fi
	echo "    Making empty meta-data file in $unit/mnt"
	touch ./mnt/meta-data
	echo "  Unmounting $unit.$ts.img"
	umount ./mnt
	echo "  Creation of autoinstall image $unit.$ts.img completed"
	echo "  Starting virt-install in background"
	virt-install \
		--name $unit \
		--os-variant ubuntu22.04 \
		--hvm \
		--vcpus 2 \
		--cpu host \
		--memory 2048 \
		--location ../ubuntu-22.04.3-live-server-amd64.iso,kernel=casper/vmlinuz,initrd=casper/initrd \
		--network bridge=br0,model=virtio \
		--network bridge=br1,model=virtio \
		--network bridge=br2,model=virtio \
		--disk size=20 \
		--disk path=./$unit.$ts.img,format=raw,cache=none \
		--graphics none \
		--extra-args='console=ttyS0,115200n8 autoinstall' \
		--noautoconsole
	cd ../
	echo "Steps for $unit completed. Installation is running in the background."
done

echo "The script will now wait for the build to complete."
echo "On a meager machine, this could take 20 minutes or longer."

i=1
while [ $i -gt 0 ]; do
	echo "Checking to make sure all units are not running..."
	running=0
	for unit in ./*/; do
		unit=${unit%*/}
		unit=${unit##*/}
		echo "  Checking on $unit"
		state=$(virsh list --all | grep -c " $unit *shut off")
		if [ $state -eq 0 ]; then
			echo "    $unit does not appear to be ready"
			((running++))
		else
			echo "    $unit appears to be ready"
		fi
	done
	if [ $running -eq 0 ]; then
		echo "It appears all units exist and are not running."
		i=0
	else
		echo "Waiting for 60 seconds and checking again"
		sleep 60
	fi
done

echo "Attempting to start all instances."
for unit in ./*/; do
	unit=${unit%*/}
	unit=${unit##*/}
	virsh start $unit
done
echo "This script does not currently clean up after itself."
echo "New <unit>/<unit>.<timestamp>.img files are created each run and will persist unless deleted by hand."
echo "TODO: Detach the ISO and CIDATA images"
echo "TODO: Remove installation NICs"
echo "Build complete. You can use 'virsh console <unit>' to access the instances"
