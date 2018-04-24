#!/bin/bash 

if [ -z $2 ]; then
	echo "usage: $0 <device> <partition-number>"
	echo
	echo eg. device /dev/sda5 is specified /dev/sda 5
	exit 1
fi

which ccrypt 2> /dev/null || exit 2
which blockdev 2> /dev/null || exit 2
which hexdump 2> /dev/null || exit 2

DEV=$1
PART=$2

tmpdir=`mktemp -d`
if [ $? != 0 ]; then
	exit 3
fi

mbroffset=$((446+(($PART-1)*16)))

sizehex=`hexdump -e '1/4 "%08x"' -s$((mbroffset+8)) -n4 $DEV`
echo $sizehex
OFFSET=`printf "%d" 0x$sizehex`
OFFSET_DATA=$(($OFFSET+1000))

insize=`blockdev --getsize64 $DEV$PART`
if [ $? != 0 ]; then
	exit 4
fi
secsize=`blockdev --getss $DEV`
if [ $? != 0 ]; then
	exit 4
fi

outbytesoffset=$(($secsize*$OFFSET))

echo "mbroffset $mbroffset"
# ccrypt prepends a magic number of 32 bytes at start of file
insize=$((insize+32))

cat <<EOF
*** WARNING WARNING WARNING ***

This will write $(($insize+(4*$secsize))) bytes on $DEV at sector offset $OFFSET (byte $outbytesoffset)
Any existing data will be destroyed!

It will also zero the MBR partition entry for $DEV$PART

EOF

read -p "proceed? (type uppercase YES): " confirm
if [ -z "$confirm" ] || [ $confirm != "YES" ]; then
	echo "aborted"
	exit 1
fi
read -sp "encryption password: " pass
echo
echo $pass > ${tmpdir}/.pass

echo using tmpdir ${tmpdir}
echo "dumping data..."
dd if=$DEV$PART of=${tmpdir}/foo 
if [ $? != 0 ]; then
	exit 5
fi

echo "encrypting data..."
ccrypt ${tmpdir}/foo -k ${tmpdir}/.pass 
if [ $? != 0 ]; then
	exit 6 
fi

# TODO: check if its on a boundary

echo "writing data..."
dd if=$DEV of=$DEV skip=$mbroffset seek=$((($secsize*$OFFSET_DATA)+32)) bs=1 count=16
dd if=${tmpdir}/foo.cpt of=$DEV seek=$((($secsize*$OFFSET_DATA)+16+32)) oflag=seek_bytes
if [ $? != 0 ]; then
	exit 7
fi

shred ${tmpdir}/foo.cpt

# create a file fs to write the encrypted scripts to
mkdir ${tmpdir}/mnt
dd if=/dev/zero of=${tmpdir}/scripts_blocks bs=$secsize count=1000
if [ $? != 0 ]; then
	exit 8
fi

mkfs.ext4 ${tmpdir}/scripts_blocks
if [ $? != 0 ]; then
	exit 9
fi

mount ${tmpdir}/scripts_blocks ${tmpdir}/mnt
if [ $? != 0 ]; then
	exit 10
fi

# create a tar of the scripts
cp w.sh r.sh ${tmpdir}/mnt
if [ $? != 0 ]; then
	exit 11
fi
cat <<eof > ${tmpdir}/mnt/data
$DEV $PART $secsize $((($secsize*$OFFSET_DATA)+32)) $insize $pass
eof

umount ${tmpdir}/mnt
if [ $? != 0 ]; then
	exit 12
fi

# encrypt the scripts
ccrypt ${tmpdir}/scripts_blocks -k ${tmpdir}/.pass
if [ $? != 0 ]; then
	exit 13
fi
dd if=${tmpdir}/scripts_blocks.cpt of=$DEV seek=$OFFSET
if [ $? != 0 ]; then
	exit 14
fi

shred ${tmpdir}/.pass
shred ${tmpdir}/scripts_blocks.cpt
rm ${tmpdir} -rf

echo "removing partition entry"
dd if=/dev/zero of=$DEV seek=$mbroffset bs=1 count=16
if [ $? != 0 ]; then
	exit 15
fi

read -p "Remove script files? (type uppercase YES):" y
if [ $y == "YES" ]; then
	shred w.sh
	shred r.sh
	rm -v w.sh
	rm -v r.sh
fi
