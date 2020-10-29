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
cat << EOF > /tmp/connect_postgres.json
{
  "name": "postgres",
  "port": 5432,
  "connect": {
    "proxy": {
      "config": {
        "bind_port": 443
      }
    }
  }
}
EOF

cat << EOF > /tmp/connect_service1.json
{
  "name": "service1",
  "port": 8080,
  "connect": {
    "proxy": {
      "config": {
        "bind_port": 8443,
        "upstreams": [
          {
            "destination_name": "service2",
            "local_bind_port": 9191
          },
          {
            "destination_name": "postgres",
            "local_bind_port": 5432
          }
        ]
      }
    }
  }
}
EOF

cat << EOF > /tmp/connect_service2.json
{
  "name": "service2",
  "port": 8080,
  "connect": {
    "proxy": {
      "config": {
        "bind_port": 443
      }
    }
  }
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
  
  service1:
    image: nicholasjackson/consul_connect_agent:latest
    volumes:
      - "./connect_service1.json:/service1.json"
    networks:
      connect_network: {}
    environment:
      CONSUL_BIND_INTERFACE: eth0
      CONSUL_CLIENT_INTERFACE: eth0
    command:
      - "-retry-join"
      - "consul_server"
  
  service2:
    image: nicholasjackson/consul_connect_agent:latest
    volumes:
      - "./connect_service2.json:/service2.json"
    networks:
      connect_network: {}
    environment:
      CONSUL_BIND_INTERFACE: eth0
      CONSUL_CLIENT_INTERFACE: eth0
    command:
      - "-retry-join"
      - "consul_server"

  postgres:
    image: nicholasjackson/consul_connect_agent:latest
    volumes:
      - "./connect_postgres.json:/postgres.json"
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

# Register postgres service
docker exec -it demo_postgres_1 curl -s -X PUT -d @/postgres.json "http://127.0.0.1:8500/v1/agent/service/register"

# Register service 2
docker exec -it demo_service2_1 curl -s -X PUT -d @/service2.json "http://127.0.0.1:8500/v1/agent/service/register"

# Register service 1
docker exec -it demo_service1_1 curl -s -X PUT -d @/service1.json "http://127.0.0.1:8500/v1/agent/service/register"

# Set up consul intentions
consul intention create -allow service1 service2
consul intention create -allow service1 postgres

else
  echo "Bootstrap already completed"
fi
EOF

chmod 700 /tmp/bootstrap_docker_server_clients.sh

%{ endif }

%{ if bootstrap_docker }/tmp/bootstrap_docker_server_clients.sh%{ endif }