# sh-decrypt-and-hide

***WARNING WARNING WARNING***

**This program messes around with raw partitions and the MBR. They can REALLY EASILY destroy data. This code is to be treated as sample code, not a working application. There is weak error handling, and may make a lot of dangerous assumptions. Author assumes NO liability for their usage**

The imagined use case for this code is to temporarily conceal the existence of data on a block device. It encrypts the partition data into nonsensical random bytes, but also hides the fact that there was a partition there in the first place. The data and scripts required to restore the data partition are embedded in the encrypted blob itself.

# hide

First, manually make a note of the partition start sector and sector size. If this numbers are lost, the data cannot be recovered:

```
fdisk -l <device>

eg.

]$ sudo fdisk -l /dev/sda
Disk /dev/sda: 111.8 GiB, 120034123776 bytes, 234441648 sectors
Units: sectors of 1 * 512 = 512 bytes <==================================== sector size is here
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0x6ca35cb5

Device     Boot    Start       End   Sectors  Size Id Type
/dev/sda1           2048  41945087  41943040   20G 83 Linux
/dev/sda2  *    41945088  41947135      2048    1M  4 FAT16 <32M
/dev/sda3       41947136  50335743   8388608    4G 82 Linux swap / Solaris
/dev/sda4       50335744 234441647 184105904 87.8G 83 Linux

                    ^========================= start sector is here
```

Then invoke the script:

 
```
w.sh <device> <partition number>

eg.

w.sh /dev/sda 4
```

The procedure will:

* dump and encrypt a partition
* dump the partition table entry for that partition
* create an ext4 fs with the two scripts, plus device/partition information, the data offset, encryption password and size of data, and encrypt it
    - this fs will be 1000 times the sector size.
* write this data to the start sector pos of the partition, immediately following each other:
    - the encrypted script/data fs
    - the partition table entry
    - the encrypted partition data itself
* shred and remove data and password from disk, and optionally scripts aswell.

# reveal

```
dd if=<device> bs=1 count=$(((<sector size>*1000)+32)) | ccrypt -d -c > <fsfile>
mount <fsfile> <mntpnt>
cd <mntpnt>
sh r.sh
```

The procedure will:

* Read the device, partition number, the absolute data offset and the encryption password from the stored data file.
* calculates the data size from the LBA size field in the stored partition entry
* writes the partition entry to the partition table
* decrypts and dumps the data to a temporary file
* writes the data back to the original sector offset on the partition
* shreds and deletes the data file, and optionally copies the script files (back) to a desired location 

# requirements

This code has been successfully run using:

- linux 4.15.13 (ARCH)
- bash 4.4.19
- coreutils 8.29 (dd, shred ...)
- utils-linux 2.31.1 (fdisk, blockdev, hexdump)
- ccrypt 1.10 
