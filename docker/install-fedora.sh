#!/bin/bash

set -euo pipefail

################################################################
#
# Flux, and Singularity
# This is likely going to hit Amazon Linux
#

yum update -y
yum group install -y "Development Tools"

yum install -y \
    munge \
    fuse \
    munge-devel \
    hwloc \
    hwloc-devel \
    pmix \
    pmix-devel \
    lua \
    lua-devel \
    lua-posix \
    libevent-devel \
    jansson-devel \
    lz4-devel \
    sqlite-devel \
    ncurses-devel \
    yaml-cpp \
    libarchive-devel \
    libxml2-devel \
    yaml-cpp-devel \
    boost-devel \
    libedit-devel \
    systemd \
    systemd-devel \
    nfs-utils \
    python3-devel \
    python3-cffi \
    python3-yaml \
    python3-jsonschema \
    python3-sphinx \
    python3-docutils \
    aspell \
    aspell-en \
    valgrind-devel \
    openmpi.x86_64 \
    openmpi-devel.x86_64 \
    libsodium \
    libsodium-devel \
    uuid-devel \
    libuuid-devel \
    wget \
    jq

# Epel release
# yum install https://archives.fedoraproject.org/pub/archive/epel/7/x86_64/Packages/e/epel-release-7-14.noarch.rpm
# yum install -y munge munge-devel

# yum install -y gcc-toolset-12
# yum list \*gcc\*
# yum install -y gcc10.x86_64 gcc10-c++.x86_64

# update-alternatives --set gcc /usr/bin/gcc10-gcc
# update-alternatives --set g++ /usr/bin/gcc10-g++
# rm /usr/bin/gcc /usr/bin/g++ --force
# ln -s /usr/bin/gcc10-gcc /usr/bin/gcc
# ln -s /usr/bin/gcc10-g++ /usr/bin/g++
# gcc --version

cd /opt

export CMAKE=3.23.1
export ARCH=x86_64
export ORAS_ARCH=amd64

curl -s -L https://github.com/Kitware/CMake/releases/download/v$CMAKE/cmake-$CMAKE-linux-$ARCH.sh > cmake.sh && \
    sh cmake.sh --prefix=/usr/local --skip-license 

################################################################
## Install Flux and dependencies
#
mkdir -p /opt/prrte && \
    cd /opt/prrte && \
    git clone https://github.com/openpmix/openpmix.git && \
    git clone https://github.com/openpmix/prrte.git && \
    cd openpmix && \
    git checkout fefaed568f33bf86f28afb6e45237f1ec5e4de93 && \
    ./autogen.pl && \
    ./configure --prefix=/usr --disable-static && make install && \
    ldconfig

cd /opt/prrte/prrte && \
    git checkout 477894f4720d822b15cab56eee7665107832921c && \
   ./autogen.pl && \
   ./configure --prefix=/usr && make -j install

# flux security
wget https://github.com/flux-framework/flux-security/releases/download/v0.13.0/flux-security-0.13.0.tar.gz && \
    tar -xzvf flux-security-0.13.0.tar.gz && \
    mv flux-security-0.13.0 /opt/flux-security && \
    cd /opt/flux-security && \
    PYTHON=$(which python3) ./configure --prefix=/usr --sysconfdir=/etc && \
    make -j && make install

# The VMs will share the same munge key
mkdir -p /var/run/munge && \
    dd if=/dev/urandom bs=1 count=1024 > munge.key && \
    mv munge.key /etc/munge/munge.key && \
    chown -R munge /etc/munge/munge.key /var/run/munge && \
    chmod 600 /etc/munge/munge.key

git clone https://github.com/zeromq/libzmq /opt/libzmq
cd /opt/libzmq
./autogen.sh
./configure --prefix=/usr --with-libsodium
make -j
make -j install

# Flux core (the python packages are likely already installed)
python3 -m ensurepip
python3 -m pip install cffi pyyaml ply jsonschema
wget https://github.com/flux-framework/flux-core/releases/download/v0.68.0/flux-core-0.68.0.tar.gz && \
    tar -xzvf flux-core-0.68.0.tar.gz && \
    mv flux-core-0.68.0 /opt/flux-core && \
    cd /opt/flux-core && \
    PYTHON=$(which python3) ./configure --prefix=/usr --sysconfdir=/etc --runstatedir=/opt/flux/run --with-flux-security=/usr && \
    make clean && \
    make -j && make install

# Flux pmix (must be installed after flux core)
wget https://github.com/flux-framework/flux-pmix/releases/download/v0.5.0/flux-pmix-0.5.0.tar.gz && \
    tar -xzvf flux-pmix-0.5.0.tar.gz && \
    mv flux-pmix-0.5.0 /opt/flux-pmix && \
    cd /opt/flux-pmix && \
    PYTHON=$(which python3) ./configure --prefix=/usr && make -j && \
    make -j install

wget https://github.com/flux-framework/flux-sched/releases/download/v0.37.0/flux-sched-0.37.0.tar.gz && \
    tar -xzvf flux-sched-0.37.0.tar.gz && \
    mv flux-sched-0.37.0 /opt/flux-sched && \
    cd /opt/flux-sched && \
    PYTHON=$(which python3) ./configure --prefix=/usr && \
    make -j && \
    make install && ldconfig && \
    echo "DONE flux build"

# Permissions for imp
chmod u+s /usr/libexec/flux/flux-imp && \
chmod 4755 /usr/libexec/flux/flux-imp && \
# /var/lib/flux needs to be owned by the instance owner
mkdir -p /var/lib/flux

# clean up (and make space)
cd /opt
rm -rf /opt/flux-core /opt/flux-sched /opt/prrte /opt/flux-security /opt/flux-pmix

# IMPORANT: the above installs to /usr/lib64 but you will get a flux_open error if it's
# not found in /usr/lib. So we put in both places :)
cp -R /usr/lib64/flux /usr/lib/flux
cp -R /usr/lib64/libflux-* /usr/lib/

# Ensure the flux uri is exported for all users
# The build should be done as azureuser, but don't assume it.
export FLUX_URI=local:///opt/run/flux/local
echo "export FLUX_URI=local:///var/run/flux/local" >> /root/.bashrc
echo "export FLUX_URI=local:///var/run/flux/local" >> /environment

#
# At this point we have what we need!
touch /mnt/install/finished.txt
