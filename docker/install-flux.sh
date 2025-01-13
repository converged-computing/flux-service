#!/usr/bin/env bash

set -o pipefail
# set -o nounset
# set -o errexit

# Note: I don't have a check to see if we have already installed
# flux - the idea being that if we delete and reinstall the daemonset,
# we would want this to re-generate. That said, we do need a means
# to allow for autoscaling (adding new nodes) that works out of
# the box. Let's better test this alter.

touch /opt/flux-finished.txt
if ! test -f /opt/flux-finished.txt; then
    apt-get update && /bin/bash /mnt/install/install-debian.sh
    cp /mnt/install/finished.txt /opt/flux-finished.txt
fi

which oras || (
    # Install ORAS client
    VERSION="1.2.2"
    curl -LO "https://github.com/oras-project/oras/releases/download/v${VERSION}/oras_${VERSION}_linux_amd64.tar.gz"
    mkdir -p oras-install/
    tar -zxf oras_${VERSION}_*.tar.gz -C oras-install/
    mv oras-install/oras /usr/local/bin/
    rm -rf oras_${VERSION}_*.tar.gz oras-install/
)

# Install netmark
which netmark || (
    mkdir -p /netmark-install
    cd /netmark-install
    oras pull ghcr.io/converged-computing/flux-distribute:src
    cd src
    mpicc -lmpi -O3 netmark.c -DTRACE -o netmark.x
    cp netmark.x /usr/local/bin/netmark
    cp netmark.x /usr/bin/netmark
)

# Prepare resource system directory
mkdir -p /etc/flux/system/conf.d
mkdir -p /etc/flux/system/cron.d
mkdir -p /etc/flux/system
mkdir -p /var/lib/flux /var/run/flux

echo "Looking for netmark..."
which netmark

# Install OSU benchmarks
if ! test -f /osu-micro-benchmarks-5.8/mpi/pt2pt/osu_latency; then
    OSU_VERSION=5.8
    wget http://mvapich.cse.ohio-state.edu/download/mvapich/osu-micro-benchmarks-$OSU_VERSION.tgz
    tar zxvf ./osu-micro-benchmarks-5.8.tgz
    cd osu-micro-benchmarks-5.8/
    ./configure CC=/usr/bin/mpicc CXX=/usr/bin/mpicxx
    make -j 4 && make install
fi

# Flux curve.cert
# Ensure we have a shared curve certificate
# This is just for development - we need a means to generate and distribute this.

if ! test -f /etc/flux/system/curve.cert; then

cat <<EOF | tee /tmp/curve.cert
#  ZeroMQ CURVE **Secret** Certificate
#  DO NOT DISTRIBUTE

metadata
    name = "flux-service"
    keygen.flux-core-version = "0.64.0"
    keygen.hostname = "flux-service"
    keygen.time = "2024-10-28T13:30:32"
    keygen.userid = "0"
    keygen.zmq-version = "4.3.5"
curve
    public-key = "uMQkII5d)VB?![bXY1.(PBV([Qew1x2l.ar3}5cg"
    secret-key = "ifW737B*JG:U\$s8lvlt6JeMsVfWZ#*eL5JWX2y(b"
EOF

mv /tmp/curve.cert /etc/flux/system/curve.cert
chmod o-r /etc/flux/system/curve.cert
chmod g-r /etc/flux/system/curve.cert
fi

# /var/lib/flux needs to be owned by the instance owner (root)
# this should already by the case

# Get the linkname of the device
linkname=$(python3 /mnt/install/parse-links.py)
echo "Found ip link name ${linkname} to provide to flux"

# Assume we add all brokers, unless "control-plane" in name (kind)
brokers=""
for broker in $(cat /mnt/install/brokers.txt)
  do 
    # Don't include the control plane, we don't use it
    if [[ $broker = *'control-plane'* ]]; then
       continue
    fi
    echo "Adding broker ${broker}"
    if [[ "${brokers}" == "" ]]; then
      brokers="${broker}"
    else
      brokers="${brokers},${broker}"
    fi
  done

# One node cluster vs. not...
if [[ "$brokers" == "" ]]; then
    echo "No brokers found - this should not happen"
    exit 1
fi

# Generate resources!
flux R encode --hosts="${brokers}" --local > /etc/flux/system/R

# Show ip addresses for debugging
ip addr

# Write broker.toml
cat <<EOF | tee /tmp/broker.toml
# Allow users other than the instance owner (guests) to connect to Flux
# Optionally, root may be given "owner privileges" for convenience
[access]
allow-guest-user = true
allow-root-owner = true

# Point to resource definition generated with flux-R(1).
# Uncomment to exclude nodes (e.g. mgmt, login), from eligibility to run jobs.
[resource]
path = "/etc/flux/system/R"

# Point to shared network certificate generated flux-keygen(1).
# Define the network endpoints for Flux's tree based overlay network
# and inform Flux of the hostnames that will start flux-broker(1).
[bootstrap]
curve_cert = "/etc/flux/system/curve.cert"

# ubuntu does not have eth0
default_port = 8050
default_bind = "tcp://eth0:%p"
# default_bind = "tcp://${linkname}:%p"
default_connect = "tcp://%h:%p"

# Rank 0 is the TBON parent of all brokers unless explicitly set with
# parent directives.
# The actual ip addresses (for both) need to be added to /etc/hosts
# of each VM for now.
hosts = [
   { host = "${brokers}" },
]
# Speed up detection of crashed network peers (system default is around 20m)
[tbon]
tcp_user_timeout = "2m"
EOF

# Move to conf.d
mv /tmp/broker.toml /etc/flux/system/conf.d/broker.toml

# If we don't do this, fails on too many open files
sysctl fs.inotify.max_user_instances=8192
sysctl fs.inotify.max_user_watches=524288

# Write a small script that makes it easy to connect
cat <<EOF | tee /flux-connect.sh
#!/bin/bash

flux proxy local:///var/run/flux/local bash
EOF
chmod +x /flux-connect.sh

# Options for the broker.
brokerOptions="-Scron.directory=/etc/flux/system/cron.d \
-Stbon.fanout=256 \
-Srundir=/var/run/flux \
-Sbroker.rc2_none \
-Sstatedir=/etc/flux/system \
-Slocal-uri=local:///var/run/flux/local \
-Slog-stderr-level=6 \
-Slog-stderr-mode=local"

cfg="/etc/flux/system/conf.d/broker.toml"
echo "🌀 flux broker --config-path ${cfg} ${brokerOptions}"

# Retry for failure
while true
do
  flux broker --config-path ${cfg} ${brokerOptions}
  echo "Return value for follower worker is ${retval}"
  echo "😪 Sleeping 15s to try again..."
  sleep 15
done
