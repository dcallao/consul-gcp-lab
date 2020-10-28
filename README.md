Consul Connect GCP Demo Lab
==================================

This is a simple demo showing command line operations of Consul Connect using Docker containers

The demo uses docker and  Terraform to create the infrastructure and launch the applications.

## Prerequisites

 * Install `terraform` binary
 * Install and configure `gcloud sdk` 

## Installing in GCP (Google Cloud)

 1. Create a new project to house your demo. In this example, I call my project `my-demo`.

 2. Create a service account that has the "Compute Instance Admin (v1)" and "Compute Security Admin" roles. Download the account credentials as a JSON file. This can be done through the UI or through the `gcloud` command line tool, e.g.:

        project="my-demo"
        account="my-service-account"

        gcloud iam service-accounts create ${account} \
            --display-name "Heat Clinic Service Account" \
            --project ${project}

        for role in iam.serviceAccountUser compute.instanceAdmin.v1 compute.networkAdmin compute.securityAdmin
        do
            gcloud projects add-iam-policy-binding ${project} \
                --member serviceAccount:${account}@${project}.iam.gserviceaccount.com \
                --role roles/${role}
        done

        gcloud iam service-accounts keys create ${account}-key.json \
            --iam-account ${account}@${project}.iam.gserviceaccount.com

 3. Add the credentials to your shell environment so the tools can find them.

        export GOOGLE_APPLICATION_CREDENTIALS=my-service-account-key.json

 4. Use Terraform to create the GCE instances, firewall rules, and Consul Connect intentions.

        terraform init
        terraform plan
        terraform apply

    If successful, the output will end with something similar to this:

        Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

 5. You can see the public IP addresses and URL's for your demo by inspecting the Terraform output:

        Outputs:

        Consul_Server_HTTP_Address = http://35.243.149.159:8500
        Consul_Server_Public_IP = 35.243.149.159

**Note:** It may take a minute or two for the site to become available, as the JVM needs to create all the database objects.

## Registering and Deregistering Services and Intentions
Once Terraform finishes executing, you will need to `ssh` in to the demo Consul VM that has  been deployed into the environent to register or deregister the services.

```
$ gcloud compute ssh demo-consul-server0 
$ sudo su
$ cd /tmp
$ docker ps -a
CONTAINER ID        IMAGE                                         COMMAND                  CREATED             STATUS              PORTS                                                                      NAMES
7804998db78e        nicholasjackson/consul_connect_agent:latest   "consul agent -confi…"   About an hour ago   Up About an hour    8300-8302/tcp, 8500/tcp, 8301-8302/udp, 8600/tcp, 8600/udp                 demo_postgres_1
83d455cac28f        nicholasjackson/consul_connect_agent:latest   "consul agent -confi…"   About an hour ago   Up About an hour    8300-8302/tcp, 8500/tcp, 8301-8302/udp, 8600/tcp, 8600/udp                 demo_service1_1
d072b017f67a        nicholasjackson/consul_connect_agent:latest   "consul agent -confi…"   About an hour ago   Up About an hour    8300-8302/tcp, 8500/tcp, 8301-8302/udp, 8600/tcp, 8600/udp                 demo_service2_1
dbc84740f511        nicholasjackson/consul_connect:latest         "/bin/sh -c 'consul …"   About an hour ago   Up About an hour    8300-8302/tcp, 8301-8302/udp, 8600/tcp, 8600/udp, 0.0.0.0:8500->8500/tcp   demo_consul_server_1
```
* Registering services
  ```
  # Register postgres service
  docker exec -it demo_postgres_1 curl -s -X PUT -d @/postgres.json "http://127.0.0.1:8500/v1/agent/service/register"

  # Register service 2
  docker exec -it demo_service2_1 curl -s -X PUT -d @/service2.json "http://127.0.0.1:8500/v1/agent/service/register"

  # Register service 1
  docker exec -it demo_service1_1 curl -s -X PUT -d @/service1.json "http://127.0.0.1:8500/v1/agent/service/register"
  ```
* Deregistering services
  ```
  # Deregister postgres service
  docker exec -it demo_postgres_1 curl -s -X PUT "http://127.0.0.1:8500/v1/agent/service/deregister/postgres"

  # Deregister service 2
  docker exec -it demo_service2_1 curl -s -X PUT "http://127.0.0.1:8500/v1/agent/service/deregister/service1"

  # Deregister service 1
  docker exec -it demo_service1_1 curl -s -X PUT "http://127.0.0.1:8500/v1/agent/service/deregister/service2"
  ```
  If the above does not work, you will need to stop the container that the service lives
  ```
  docker stop demo_postgres_1
  docker stop demo_service1_1
  docker stop demo_service2_1
  ```
* Adding intentions
  ```
  consul intention create -allow service1 service2
  consul intention create -allow service1 postgres
  ```
## Re-deploying Consul Container Stack
In order to re-deploy all of the containers on the demo host, run the following:

```
$ cd /tmp
$ docker rm -f $(docker ps -a -q)
$ nohup docker-compose -p demo up &
$ docker ps -a
```