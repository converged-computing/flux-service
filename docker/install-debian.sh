#!/bin/bash

set -euo pipefail

################################################################
#
# Flux, and Singularity
# Starting on ubuntu 24.04
#

export DEBIAN_FRONTEND=noninteractive
apt-get update && \
    apt-get install -y apt-transport-https ca-certificates curl jq apt-utils wget curl jq \
         build-essential make

# cmake is needed for flux-sched, and make sure to choose arm or x86
export CMAKE=3.23.1
export ARCH=x86_64
export ORAS_ARCH=amd64

curl -s -L https://github.com/Kitware/CMake/releases/download/v$CMAKE/cmake-$CMAKE-linux-$ARCH.sh > cmake.sh && \
    sh cmake.sh --prefix=/usr/local --skip-license && \
    apt-get update && \
    apt-get install -y man flex ssh sudo vim luarocks munge lcov ccache lua5.4 \
         valgrind build-essential pkg-config autotools-dev libtool \
         libffi-dev autoconf automake make clang clang-tidy \
         gcc g++ libpam-dev apt-utils lua-posix \
         libsodium-dev libzmq3-dev libczmq-dev libjansson-dev libmunge-dev \
         libncursesw5-dev liblua5.4-dev liblz4-dev libsqlite3-dev uuid-dev \
         libhwloc-dev libs3-dev libevent-dev libarchive-dev \
         libboost-graph-dev libboost-system-dev libboost-filesystem-dev \
         libboost-regex-dev libyaml-cpp-dev libedit-dev uidmap dbus-user-session python3-cffi \
         openmpi-bin openmpi-doc libopenmpi-dev locales

locale-gen en_US.UTF-8

################################################################
## Install Flux and dependencies

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
cd /opt
wget https://github.com/flux-framework/flux-security/releases/download/v0.13.0/flux-security-0.13.0.tar.gz && \
    tar -xzvf flux-security-0.13.0.tar.gz && \
    mv flux-security-0.13.0 /opt/flux-security && \
    cd /opt/flux-security && \
    ./configure --prefix=/usr --sysconfdir=/etc && \
    make -j && make install

# The VMs will share the same munge key
mkdir -p /var/run/munge && \
    dd if=/dev/urandom bs=1 count=1024 > munge.key && \
    mv munge.key /etc/munge/munge.key && \
    chown -R munge /etc/munge/munge.key /var/run/munge && \
    chmod 600 /etc/munge/munge.key

# Flux core
apt-get install -y python3-pip
cd /opt
wget https://github.com/flux-framework/flux-core/releases/download/v0.68.0/flux-core-0.68.0.tar.gz && \
    tar -xzvf flux-core-0.68.0.tar.gz && \
    mv flux-core-0.68.0 /opt/flux-core && \
    cd /opt/flux-core && \
    ./configure --prefix=/usr --sysconfdir=/etc --with-flux-security && \
    make clean && \
    make -j && make install

# Flux pmix (must be installed after flux core)
cd /opt
wget https://github.com/flux-framework/flux-pmix/releases/download/v0.5.0/flux-pmix-0.5.0.tar.gz && \
     tar -xzvf flux-pmix-0.5.0.tar.gz && \
     mv flux-pmix-0.5.0 /opt/flux-pmix && \
     cd /opt/flux-pmix && \
     ./configure --prefix=/usr && \
     make -j && \
     make install

# Flux sched
cd /opt
wget https://github.com/flux-framework/flux-sched/releases/download/v0.40.0/flux-sched-0.40.0.tar.gz && \
    tar -xzvf flux-sched-0.40.0.tar.gz && \
    mv flux-sched-0.40.0 /opt/flux-sched && \
    cd /opt/flux-sched && \
    mkdir build && \
    cd build && \
    cmake ../ && make -j && make install && ldconfig && \
    echo "DONE flux build"

# Flux curve.cert
# Ensure we have a shared curve certificate
mkdir -p /etc/flux/system && \
    # Permissions for imp
    chmod u+s /usr/libexec/flux/flux-imp && \
    chmod 4755 /usr/libexec/flux/flux-imp && \
    # /var/lib/flux needs to be owned by the instance owner
    mkdir -p /var/lib/flux && \
    cd /opt

# Ensure the flux uri is exported for all users
# The build should be done as azureuser, but don't assume it.
export FLUX_URI=local:///opt/run/flux/local
echo "export FLUX_URI=local:///var/run/flux/local" >> /root/.bashrc
echo "export FLUX_URI=local:///var/run/flux/local" >> /environment

# 
# At this point we have what we need!
touch /mnt/install/finished.txt