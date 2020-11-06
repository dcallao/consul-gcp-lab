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
apt-key fingerprint 0EBFCD88
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli
curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/bin/docker-compose
chmod +x  /usr/bin/docker-compose

# Installation Vars
echo "Starting deployment from AMI: ${image}"
INSTANCE_ID=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/id?recursive=true&alt=text" -H "Metadata-Flavor: Google")
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
connect {
  enabled = true
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

%{ if bootstrap_consul }

cat << EOF > /tmp/bootstrap_consul.sh
#!/bin/bash
echo "Bootstraping consul..."
# Start Consul Server
systemctl daemon-reload
systemctl enable consul
systemctl start consul

echo "Waiting for Consul to start..."
while [[ -z $(curl -fsSL localhost:8500/v1/status/leader) ]]
do
    sleep 3
done 

else
  echo "Bootstrap already completed"
fi
EOF

chmod 700 /tmp/bootstrap_consul.sh

%{ endif }

%{ if bootstrap_consul }/tmp/bootstrap_consul.sh%{ endif }


# Bootstrap Docker Server & Clients
%{ if bootstrap_docker }
cat << EOF > /tmp/connect_web1.json
{
    "name": "web",
    "id": "web1",
    "port": 80,
    "connect": {}
}
EOF

cat << EOF > /tmp/connect_web2.json
{
    "name": "web",
    "id": "web2",
    "port": 80,
    "connect": {}
}
EOF

cat << EOF > /tmp/connect_web3.json
{
    "name": "web",
    "id": "web3",
    "port": 80,
    "connect": {}
}
EOF

cat << EOF > /tmp/connect_app1.json
{
    "name": "app",
    "id": "app1",
    "port": 5000,
    "connect": {}
}
EOF

cat << EOF > /tmp/connect_app2.json
{
    "name": "app",
    "id": "app2",
    "port": 5000,
    "connect": {}
}
EOF

cat << EOF > /tmp/connect_app3.json
{
    "name": "app",
    "id": "app3",
    "port": 5000,
    "connect": {}
}
EOF

cat << EOF > /tmp/connect_db1.json
{
    "name": "db",
    "id": "db1",
    "port": 1434,
    "connect": {}
}
EOF

cat << EOF > /tmp/connect_db2.json
{
    "name": "db",
    "id": "db2",
    "port": 1434,
    "connect": {}
}
EOF

cat << EOF > /tmp/docker-compose.yml
version: '3'
services:

  consul_server:
    image: nicholasjackson/consul_connect:latest
    environment:
      CONSUL_BIND_INTERFACE: eth0
      CONSUL_UI_BETA: "true"
    ports:
      - "8500:8500"
    networks:
      connect_network: {}

  web1:
    image: nicholasjackson/consul_connect_agent:latest
    volumes:
      - "./connect_web1.json:/web1.json"
    networks:
      connect_network: {}
    environment:
      CONSUL_BIND_INTERFACE: eth0
      CONSUL_CLIENT_INTERFACE: eth0
    command:
      - "-retry-join"
      - "consul_server"

  web2:
    image: nicholasjackson/consul_connect_agent:latest
    volumes:
      - "./connect_web2.json:/web2.json"
    networks:
      connect_network: {}
    environment:
      CONSUL_BIND_INTERFACE: eth0
      CONSUL_CLIENT_INTERFACE: eth0
    command:
      - "-retry-join"
      - "consul_server"

  web3:
    image: nicholasjackson/consul_connect_agent:latest
    volumes:
      - "./connect_web3.json:/web3.json"
    networks:
      connect_network: {}
    environment:
      CONSUL_BIND_INTERFACE: eth0
      CONSUL_CLIENT_INTERFACE: eth0
    command:
      - "-retry-join"
      - "consul_server"
 
  app1:
    image: nicholasjackson/consul_connect_agent:latest
    volumes:
      - "./connect_app1.json:/app1.json"
    networks:
      connect_network: {}
    environment:
      CONSUL_BIND_INTERFACE: eth0
      CONSUL_CLIENT_INTERFACE: eth0
    command:
      - "-retry-join"
      - "consul_server"

  app2:
    image: nicholasjackson/consul_connect_agent:latest
    volumes:
      - "./connect_app2.json:/app2.json"
    networks:
      connect_network: {}
    environment:
      CONSUL_BIND_INTERFACE: eth0
      CONSUL_CLIENT_INTERFACE: eth0
    command:
      - "-retry-join"
      - "consul_server"

  app3:
    image: nicholasjackson/consul_connect_agent:latest
    volumes:
      - "./connect_app3.json:/app3.json"
    networks:
      connect_network: {}
    environment:
      CONSUL_BIND_INTERFACE: eth0
      CONSUL_CLIENT_INTERFACE: eth0
    command:
      - "-retry-join"
      - "consul_server"

  db1:
    image: nicholasjackson/consul_connect_agent:latest
    volumes:
      - "./connect_db1.json:/db1.json"
    networks:
      connect_network: {}
    environment:
      CONSUL_BIND_INTERFACE: eth0
      CONSUL_CLIENT_INTERFACE: eth0
    command:
      - "-retry-join"
      - "consul_server"

  db2:
    image: nicholasjackson/consul_connect_agent:latest
    volumes:
      - "./connect_db2.json:/db2.json"
    networks:
      connect_network: {}
    environment:
      CONSUL_BIND_INTERFACE: eth0
      CONSUL_CLIENT_INTERFACE: eth0
    command:
      - "-retry-join"
      - "consul_server"

networks:
  connect_network:
    external: false
    driver: bridge
EOF
cat << EOF > /tmp/bootstrap_docker_server_clients.sh
#!/bin/bash
echo "Bootstraping docker server and clients..."
cd /tmp/
# Start docker compose
nohup docker-compose -p demo up &

sleep 30

# Register web services
/usr/bin/docker exec -t demo_web1_1 curl -s -X PUT -d @/web1.json "http://127.0.0.1:8500/v1/agent/service/register"
/usr/bin/docker exec -t demo_web2_1 curl -s -X PUT -d @/web2.json "http://127.0.0.1:8500/v1/agent/service/register"

# Register app services
/usr/bin/docker exec -t demo_app1_1 curl -s -X PUT -d @/app1.json "http://127.0.0.1:8500/v1/agent/service/register"
/usr/bin/docker exec -t demo_app2_1 curl -s -X PUT -d @/app2.json "http://127.0.0.1:8500/v1/agent/service/register"

# Register db services
/usr/bin/docker exec -t demo_db1_1 curl -s -X PUT -d @/db1.json "http://127.0.0.1:8500/v1/agent/service/register"
/usr/bin/docker exec -t demo_db2_1 curl -s -X PUT -d @/db2.json "http://127.0.0.1:8500/v1/agent/service/register"

# Set up consul intentions
consul intention create -allow web app
consul intention create -allow app db

echo "Bootstrap already completed" >> /tmp/bootstrap.log

EOF

chmod 700 /tmp/bootstrap_docker_server_clients.sh

%{ endif }

%{ if bootstrap_docker }/tmp/bootstrap_docker_server_clients.sh%{ endif }