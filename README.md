Consul Connect GCP Demo Lab
==================================

This is a simple demo showing command line operations of Consul Connect using Docker containers

The demo uses docker and  Terraform to create the infrastructure and launch the applications.

## Prerequisites

 * Install `terraform` binary
 * Install and configure `gcloud sdk`
 * Create project in GCP account and set `gcloud` to that project  (i.e. `gcloud config set project my-demo`)

## Installing in GCP (Google Cloud)

 1. Create a new project to house your demo. In this example, I call my project `my-demo`. The `my-demo` is a project id, you can use the command `gcloud projects list` to get the project ID for `my-demo`. 

 2. Create a service account that has the "Compute Instance Admin (v1)" and "Compute Security Admin" roles. Download the account credentials as a JSON file. This can be done through the UI or through the `gcloud` command line tool, e.g.:

        project="my-demo"
        account="my-service-account"

        gcloud iam service-accounts create ${account} \
            --display-name "Demo Lab Service Account" \
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

 4. Modify the variables.tf file to reflect the project id. 

      variable "project_name" {
        type        = string
        default     = "my-demo"
        description = "Name of the GCP project to create resources in."
      }

 5. Use Terraform to create the GCE instances, firewall rules, and Consul Connect intentions.

        terraform init
        terraform plan
        terraform apply

    If successful, the output will end with something similar to this:

        Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

 6. You can see the public IP addresses and URL's for your demo by inspecting the Terraform output:

        Outputs:

        Consul_Server_HTTP_Address = http://35.243.149.159:8500
        Consul_Server_Public_IP = 35.243.149.159

**Note:** It may take a minute or two for the site to become available, as the JVM needs to create all the database objects.

## Registering and Deregistering Services and Intentions
Once Terraform finishes executing, you should have a working consul lab enviroment. You can `ssh` in to the demo Consul VM that has been deployed into the environent to register or deregister the services.

```
$ gcloud compute ssh demo-consul-server0 
$ sudo su
$ cd /tmp
$ docker ps -a
CONTAINER ID        IMAGE                                         COMMAND                  CREATED             STATUS              PORTS                                                                      NAMES
e802b501c523        nicholasjackson/consul_connect_agent:latest   "consul agent -confi…"   33 minutes ago      Up 33 minutes       8300-8302/tcp, 8500/tcp, 8301-8302/udp, 8600/tcp, 8600/udp                 demo_web1_1
92d1631390f7        nicholasjackson/consul_connect_agent:latest   "consul agent -confi…"   33 minutes ago      Up 33 minutes       8300-8302/tcp, 8500/tcp, 8301-8302/udp, 8600/tcp, 8600/udp                 demo_db2_1
5fe85d6cc4ee        nicholasjackson/consul_connect_agent:latest   "consul agent -confi…"   33 minutes ago      Up 33 minutes       8300-8302/tcp, 8500/tcp, 8301-8302/udp, 8600/tcp, 8600/udp                 demo_app3_1
e4578ae725ef        nicholasjackson/consul_connect:latest         "/bin/sh -c 'consul …"   33 minutes ago      Up 33 minutes       8300-8302/tcp, 8301-8302/udp, 8600/tcp, 8600/udp, 0.0.0.0:8500->8500/tcp   demo_consul_server_1
b36914ea2335        nicholasjackson/consul_connect_agent:latest   "consul agent -confi…"   33 minutes ago      Up 33 minutes       8300-8302/tcp, 8500/tcp, 8301-8302/udp, 8600/tcp, 8600/udp                 demo_db1_1
108254b3039f        nicholasjackson/consul_connect_agent:latest   "consul agent -confi…"   33 minutes ago      Up 33 minutes       8300-8302/tcp, 8500/tcp, 8301-8302/udp, 8600/tcp, 8600/udp                 demo_web2_1
8edffe0a66c3        nicholasjackson/consul_connect_agent:latest   "consul agent -confi…"   33 minutes ago      Up 33 minutes       8300-8302/tcp, 8500/tcp, 8301-8302/udp, 8600/tcp, 8600/udp                 demo_web3_1
472438a815d9        nicholasjackson/consul_connect_agent:latest   "consul agent -confi…"   33 minutes ago      Up 33 minutes       8300-8302/tcp, 8500/tcp, 8301-8302/udp, 8600/tcp, 8600/udp                 demo_app2_1
5b8951940d35        nicholasjackson/consul_connect_agent:latest   "consul agent -confi…"   33 minutes ago      Up 33 minutes       8300-8302/tcp, 8500/tcp, 8301-8302/udp, 8600/tcp, 8600/udp                 demo_app1_1
```
* Registering services
  ```
  # Register Web Services
  docker exec -it demo_web1_1 curl -s -X PUT -d @/web1.json "http://127.0.0.1:8500/v1/agent/service/register"
  docker exec -it demo_web2_1 curl -s -X PUT -d @/web2.json "http://127.0.0.1:8500/v1/agent/service/register"
  docker exec -it demo_web3_1 curl -s -X PUT -d @/web3.json "http://127.0.0.1:8500/v1/agent/service/register"
  # Register App Services
  docker exec -it demo_app1_1 curl -s -X PUT -d @/app1.json "http://127.0.0.1:8500/v1/agent/service/register"
  docker exec -it demo_app2_1 curl -s -X PUT -d @/app2.json "http://127.0.0.1:8500/v1/agent/service/register"
  docker exec -it demo_app3_1 curl -s -X PUT -d @/app3.json "http://127.0.0.1:8500/v1/agent/service/register"
  # Register DB Services
  docker exec -it demo_db1_1 curl -s -X PUT -d @/db1.json "http://127.0.0.1:8500/v1/agent/service/register"
  docker exec -it demo_db2_1 curl -s -X PUT -d @/db2.json "http://127.0.0.1:8500/v1/agent/service/register"
  ```
* Deregistering services
  ```
  # Deregister postgres service
  docker exec -it demo_web1_1 curl -s -X PUT "http://127.0.0.1:8500/v1/agent/service/deregister/web"
  docker exec -it demo_web2_1 curl -s -X PUT "http://127.0.0.1:8500/v1/agent/service/deregister/web"
  docker exec -it demo_web3_1 curl -s -X PUT "http://127.0.0.1:8500/v1/agent/service/deregister/web"

  # Deregister service 2
  docker exec -it demo_app1_1 curl -s -X PUT "http://127.0.0.1:8500/v1/agent/service/deregister/app"
  docker exec -it demo_app2_1 curl -s -X PUT "http://127.0.0.1:8500/v1/agent/service/deregister/app"
  docker exec -it demo_app3_1 curl -s -X PUT "http://127.0.0.1:8500/v1/agent/service/deregister/app"

  # Deregister service 1
  docker exec -it demo_db1_1 curl -s -X PUT "http://127.0.0.1:8500/v1/agent/service/deregister/db"
  docker exec -it demo_db2_1 curl -s -X PUT "http://127.0.0.1:8500/v1/agent/service/deregister/db"
  ```
  If the above does not work, you will need to stop the container that the service lives
  ```
  docker stop demo_web1_1
  docker stop demo_app1_1
  docker stop demo_db1_1
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
$ pkill docker-compose
$ nohup docker-compose -p demo up &
$ docker ps -a
```