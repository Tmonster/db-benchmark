# script to format mount and copy data.

# remove a leftover instance mount
rm -rf ~/db-benchmark-metal

# format the mount

mount_name=$(sudo lsblk | awk '
NR > 1 && $1 ~ /^nvme/ && $7 == "" {
    # Convert SIZE column to bytes for comparison
    size = $4;
    unit = substr(size, length(size));
    value = substr(size, 1, length(size)-1);
    if (unit == "G") { value *= 1024^3; }
    else if (unit == "T") { value *= 1024^4; }
    else if (unit == "M") { value *= 1024^2; }
    else if (unit == "K") { value *= 1024; }
    else { value *= 1; }

    # Keep track of the largest size
    if (value > max) {
        max = value;
        largest = $1;
    }
}
END { if (largest) print largest; else print "No match found"; }
')

sudo mkfs -t xfs /dev/$mount_name

mkdir ~/db-benchmark-metal
# mount the nvme volumn
sudo mount /dev/$mount_name ~/db-benchmark-metal
# change ownsership of the volume
sudo chown -R ubuntu ~/db-benchmark-metal/

git clone $(git remote get-url origin) ~/db-benchmark-metal