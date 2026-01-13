#!/bin/bash
#
# build-rootfs.sh - Creates an Alpine Linux root filesystem for OpenWork VM
#
# This script creates a minimal Alpine Linux image with development tools
# for use with Apple's Virtualization.framework (VZVirtualMachine)
#
# Requirements:
# - Docker (for building the rootfs)
# - qemu-img (for creating disk image) - brew install qemu
#
# Usage:
#   ./build-rootfs.sh [output_dir]
#

set -e

OUTPUT_DIR="${1:-../Resources/linux}"
ALPINE_VERSION="3.19"
IMAGE_SIZE="2G"
ROOTFS_NAME="rootfs.img"

echo "=== OpenWork Alpine Linux RootFS Builder ==="
echo "Alpine Version: $ALPINE_VERSION"
echo "Output Directory: $OUTPUT_DIR"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Check for required tools
command -v docker >/dev/null 2>&1 || { echo "Error: docker is required but not installed."; exit 1; }
command -v qemu-img >/dev/null 2>&1 || { echo "Error: qemu-img is required. Install with: brew install qemu"; exit 1; }

# Create a temporary directory for building
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

echo "Working directory: $WORK_DIR"

# Create the rootfs using Docker
echo ""
echo "=== Step 1: Building Alpine rootfs with Docker ==="

cat > "$WORK_DIR/Dockerfile" << 'DOCKERFILE'
FROM alpine:3.19

# Install essential packages for development
RUN apk update && apk add --no-cache \
    alpine-base \
    openrc \
    dhcpcd \
    openssh \
    curl \
    wget \
    python3 \
    py3-pip \
    nodejs \
    npm \
    git \
    build-base \
    gcc \
    musl-dev \
    linux-headers \
    bash \
    jq \
    ripgrep \
    fd \
    tree \
    vim \
    e2fsprogs \
    util-linux

# Set up Python environment
RUN python3 -m pip install --break-system-packages \
    requests \
    httpx

# Configure services
RUN rc-update add devfs sysinit && \
    rc-update add dmesg sysinit && \
    rc-update add mdev sysinit && \
    rc-update add hwdrivers sysinit && \
    rc-update add networking boot && \
    rc-update add hostname boot && \
    rc-update add sshd default

# Set up console
RUN echo "ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100" >> /etc/inittab
RUN echo "hvc0::respawn:/sbin/getty -L hvc0 115200 vt100" >> /etc/inittab

# Configure networking
RUN echo -e "auto lo\niface lo inet loopback\n\nauto eth0\niface eth0 inet dhcp" > /etc/network/interfaces

# Set root password (openwork)
RUN echo "root:openwork" | chpasswd

# Create workspace directory for mounted folders
RUN mkdir -p /workspace

# Configure SSH for easier access
RUN sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN ssh-keygen -A

# Set hostname
RUN echo "openwork-vm" > /etc/hostname

# Create a welcome message
RUN echo -e '\n\nWelcome to OpenWork VM (Alpine Linux)\n\n' > /etc/motd

# Clean up
RUN rm -rf /var/cache/apk/*
DOCKERFILE

# Build the Docker image
docker build -t openwork-rootfs "$WORK_DIR"

echo ""
echo "=== Step 2: Exporting rootfs from Docker ==="

# Create container and export filesystem
CONTAINER_ID=$(docker create openwork-rootfs)
docker export "$CONTAINER_ID" > "$WORK_DIR/rootfs.tar"
docker rm "$CONTAINER_ID" >/dev/null

echo ""
echo "=== Step 3: Creating disk image ==="

# Create an empty disk image
qemu-img create -f raw "$WORK_DIR/$ROOTFS_NAME" "$IMAGE_SIZE"

# Use Docker to create ext4 filesystem and populate it (macOS doesn't have mkfs.ext4)
echo ""
echo "=== Step 4: Formatting and populating disk image ==="

docker run --rm --privileged \
    -v "$WORK_DIR:/work" \
    alpine:3.19 sh -c "
        apk add --no-cache e2fsprogs tar
        # Format the disk image as ext4
        mkfs.ext4 -F /work/$ROOTFS_NAME
        # Mount and populate
        mkdir -p /mnt
        mount -o loop /work/$ROOTFS_NAME /mnt
        tar -xf /work/rootfs.tar -C /mnt
        # Create necessary directories
        mkdir -p /mnt/dev /mnt/proc /mnt/sys /mnt/tmp /mnt/run
        chmod 1777 /mnt/tmp
        # Unmount
        umount /mnt
        echo 'Disk image created successfully'
    "

echo ""
echo "=== Step 5: Downloading Linux kernel ==="

# Download kernel from Alpine Linux directly using Docker
if [[ $(uname -m) == "arm64" ]]; then
    echo "Building ARM64 kernel from Alpine..."

    docker run --rm -v "$OUTPUT_DIR:/output" alpine:3.19 sh -c "
        apk add --no-cache linux-virt
        cp /boot/vmlinuz-virt /output/vmlinuz
        cp /boot/initramfs-virt /output/initrd.img
        chmod 644 /output/vmlinuz /output/initrd.img
        echo 'Kernel files copied successfully'
    "
else
    echo "Building x86_64 kernel from Alpine..."

    docker run --rm --platform linux/amd64 -v "$OUTPUT_DIR:/output" alpine:3.19 sh -c "
        apk add --no-cache linux-virt
        cp /boot/vmlinuz-virt /output/vmlinuz
        cp /boot/initramfs-virt /output/initrd.img
        chmod 644 /output/vmlinuz /output/initrd.img
        echo 'Kernel files copied successfully'
    "
fi

# Copy the rootfs image
cp "$WORK_DIR/$ROOTFS_NAME" "$OUTPUT_DIR/$ROOTFS_NAME"

echo ""
echo "=== Build Complete ==="
echo ""
echo "Files created in $OUTPUT_DIR:"
ls -lh "$OUTPUT_DIR"
echo ""
echo "To use with OpenWork:"
echo "1. Copy the linux/ folder to OpenWork.app/Contents/Resources/"
echo "2. Or add as a Copy Files build phase in Xcode"
echo ""
echo "VM Credentials:"
echo "  Username: root"
echo "  Password: openwork"
echo ""

# Clean up Docker image
docker rmi openwork-rootfs >/dev/null 2>&1 || true

echo "Done!"
