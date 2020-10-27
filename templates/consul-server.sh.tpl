#!/usr/bin/env bash

# Env Variables
DEBIAN_FRONTEND=noninteractive
sudo echo "127.0.0.1 $(hostname)" >> /etc/hosts

# Install System Packages
apt-get update
apt-get install -y apt-transport-https \
  ca-certificates \
  curl \
  unzip \
  software-properties-common \
  gnupg-agent \
  git \
  jq

# Install docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
apt-get update
apt-get install docker-ce docker-ce-cli 

# Installation Vars
echo "Starting deployment from AMI: ${image}"
INSTANCE_ID=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/id?recursive=true&alt=text" -H "Metadata-Flavor: Google")
AVAILABILITY_ZONE="$(curl http://metadata.google.internal/computeMetadata/v1/instance/zone -H "Metadata-Flavor: Google" | awk -F'/' '{print $NF}')"
LOCAL_IPV4=$(curl http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip -H "Metadata-Flavor: Google")

CONSUL_ZIP="consul_1.8.5_linux_amd64.zip"
CONSUL_URL="https://releases.hashicorp.com/consul/1.8.5/consul_1.8.5_linux_amd64.zip"
sudo curl --silent --output /tmp/$${CONSUL_ZIP} $${CONSUL_URL}
sudo unzip -o /tmp/$${CONSUL_ZIP} -d /usr/local/bin/
sudo chmod 0755 /usr/local/bin/consul
sudo chown consul:consul /usr/local/bin/consul

# Create a user account to own files
useradd -c "Consul Service Account" -m -r -s /bin/bash consul

# Create config and data directories
install -d -m 0755 -o consul -g consul /data/consul /etc/consul.d

# Install a unit file for systemd
cat << EOF > /lib/systemd/system/consul.service
[Unit]
Description=Consul
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target

[Service]
User=consul
Restart=on-failure
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGTERM
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Generate a gossip encryption key
jq -n ".encrypt = \"$(consul keygen)\"" > /tmp/consul.d/gossip.json

# Consul Server Bootstrap
cat << EOF > /etc/consul.d/consul.hcl
datacenter          = "${datacenter}"
node_name           = "$${INSTANCE_ID}"
server              = true
bootstrap_expect    = ${bootstrap_expect}
data_dir            = "/data/consul"
advertise_addr      = "$${LOCAL_IPV4}"
client_addr         = "0.0.0.0"
log_level           = "INFO"
ui                  = true
leave_on_terminate  = true
# GCP cloud join
retry_join          = ["provider=gce project_name=${project} tag_value=${environment_name}-consul"]
performance {
    raft_multiplier = 1
}
EOF

# Consul Auto Pilot Bootstrap
cat << EOF > /etc/consul.d/autopilot.hcl
autopilot {%{ if redundancy_zones }
  redundancy_zone_tag = "az"%{ endif }
  upgrade_version_tag = "consul_cluster_version"
}
EOF
 %{ if redundancy_zones }
cat << EOF > /etc/consul.d/redundancy_zone.hcl
node_meta = {
    az = "$${AVAILABILITY_ZONE}"
}
EOF
%{ endif }

# Consul Cluster Version Bootstrap
cat << EOF > /etc/consul.d/cluster_version.hcl
node_meta = {
    consul_cluster_version = "${consul_cluster_version}"
}
EOF

chmod 0664 /lib/systemd/system/consul.service
chown -R consul:consul /etc/consul.d
chmod -R 0644 /etc/consul.d/*

# Set up Consul environment
sudo tee -a /etc/environment <<EOF
export CONSUL_HTTP_ADDR=http://127.0.0.1:8500
EOF

source /etc/environment

# Start Consul Server
systemctl daemon-reload
systemctl enable consul
systemctl start consul

echo "Waiting for Consul to start..."
while [[ -z $(curl -fsSL localhost:8500/v1/status/leader) ]]
do
    sleep 3
done 

# Bootstrap Clients
%{ if bootstrap }
cat << EOF > /tmp/bootstrap_clients.sh
#!/bin/bash
echo "Bootstraping clients..."

else
  echo "Bootstrap already completed"
fi
EOF

chmod 700 /tmp/bootstrap_clients.sh

%{ endif }

%{ if bootstrap }/tmp/bootstrap_clients.sh%{ endif }