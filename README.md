# Terraforming PKS GCP

Huge thanks to @pivotal-cf for [https://github.com/pivotal-cf/terraforming-gcp](https://github.com/pivotal-cf/terraforming-gcp). I have taken their work and upgraded it in accordance with current [PKS](https://docs.pivotal.io/runtimes/pks/1-0/gcp.html) documentation for GCP.

## Version Information
- Pivotal Cloud Foundry Operations Manager  : 2.5.2 build.172
- Pivotal Container Service (PKS)           : 1.4.0 build.31
- Terraform v0.11.13 + provider.google v2.6.0

## Prerequisites

Your system needs the `gcloud` cli, as well as `terraform`:

```bash
brew update
brew install Caskroom/cask/google-cloud-sdk
brew install terraform
```
You also need the following CLIs to deploy PKS with BOSH Director.
- `jq` CLI    : https://stedolan.github.io/jq/
- `om` CLI    : https://github.com/pivotal-cf/om/releases
- `uaac` CLI  : https://github.com/cloudfoundry/cf-uaac



### Service Account

You will need a key file for your service account to allow terraform to deploy resources. If you don't have one, you can create a service account and a key for it:

```
export PROJECT_ID="XXXXXXXX"
export ACCOUNT_NAME="YYYYYYYY"
gcloud iam service-accounts create ${ACCOUNT_NAME} --display-name "PKS Account"
gcloud iam service-accounts keys create "terraform.key.json" --iam-account "${ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud projects add-iam-policy-binding ${PROJECT_ID} --member "serviceAccount:${ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --role 'roles/owner'
```

### Var File

Copy the stub content below into a terminal to create `terraform.tfvars` file. Make sure it's located in the root of this project.
These vars will be used when you run `terraform  apply`.
You should fill in the stub values with the correct content.

```bash
export ENV_PREFIX="XXXXXXXX"
export OPS_IMAGE_URL="https://storage.googleapis.com/ops-manager-us/pcf-gcp-2.5.2-build.172.tar.gz"
```
```hcl
cat << EOF > terraform.tfvars
env_prefix = "${ENV_PREFIX}"
project = "${PROJECT_ID}"
region = "asia-northeast1"
zones = ["asia-northeast1-a", "asia-northeast1-b", "asia-northeast1-c"]
service_account_key = <<SERVICE_ACCOUNT_KEY
$(cat ./terraform.key.json)
SERVICE_ACCOUNT_KEY
nat_machine_type = "n1-standard-1"
opsman_image_url = "${OPS_IMAGE_URL}"
opsman_machine_type = "n1-standard-2"
EOF
```
Make sure all variables are correctly set.
```
cat terraform.tfvars
```

### Var Details
- env_prefix: **(required)** An arbitrary unique name for namespacing resources. Max 23 characters.
- project: **(required)** ID for your GCP project.
- region: **(required)** Region in which to create resources (e.g. europe-west1)
- zones: **(required)** Zones in which to create resources. Must be within the given region. Currently you must specify exactly 3 Zones for this terraform configuration to work. (e.g. [us-central1-a, us-central1-b, us-central1-c])
- opsman_image_url **(required)** Source URL of the Ops Manager image you want to boot.
- service_account_key: **(required)** Contents of your service account key file generated using the `gcloud iam service-accounts keys create` command.
- nat_machine_type: **(default: n1-standard-4)** NAT machine type
- opsman_machine_type: **(default: n1-standard-2)** Ops Manager machine type

## Running

Note: please make sure you have created the `terraform.tfvars` file above as mentioned.

### Standing up environment

```bash
terraform init
terraform plan -out=plan
terraform apply plan
```

### Tearing down environment

```bash
terraform destroy
```


# Deploying BOSH Director
### Install om CLI on Your PC
For Mac:
```bash
wget -q -O om https://github.com/pivotal-cf/om/releases/download/0.37.0/om-darwin
chmod +x om
mv om /usr/local/bin/
```
For Linux:
```bash
wget -q -O om https://github.com/pivotal-cf/om/releases/download/0.37.0/om-linux
chmod +x om
sudo mv om /usr/local/bin/
```

### Set Up Admin User for Ops Manager
```bash
OPS_MGR_USR=ops-admin
OPS_MGR_PWD=ops-password
OM_DECRYPTION_PWD=ops-password

OPSMAN_DOMAIN_OR_IP_ADDRESS=$(cat terraform.tfstate | jq -r '.modules[0].resources."google_compute_address.ops-manager-public-ip".primary.attributes.address')
om --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
   --skip-ssl-validation \
   configure-authentication \
   --username $OPS_MGR_USR \
   --password $OPS_MGR_PWD \
   --decryption-passphrase $OM_DECRYPTION_PWD
```
Output
```bash
configuring internal userstore...
waiting for configuration to complete...
configuration complete
```

Access `https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}` from a web browser.

### Configure Ops Manager
Create a config file: `config-director.yml`.
```bash
DIRECTOR_VM_TYPE=large.disk
INTERNET_CONNECTED=true
AUTH_JSON=$(cat terraform.tfstate | jq -r '.modules[0].outputs.AuthJSON.value')
OPSMAN_DOMAIN_OR_IP_ADDRESS=$(cat terraform.tfstate | tr -d '[:cntrl:]' | jq -r '.modules[0].resources."google_compute_address.ops-manager-public-ip".primary.attributes.address')
GCP_PROJECT_ID=$(echo $AUTH_JSON | jq -r .project_id)
GCP_RESOURCE_PREFIX=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Default Deployment Tag".value')
GCP_SERVICE_ACCOUNT_KEY=$(echo ${AUTH_JSON})
AVAILABILITY_ZONES=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Availability Zones".value | map({name: .})' | tr -d '\n' | tr -d '"')
PKS_INFRASTRUCTURE_NETWORK_NAME=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Infrastructure Network Name".value')
PKS_INFRASTRUCTURE_IAAS_IDENTIFIER=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Infrastructure Network Google Network Name ".value')
PKS_INFRASTRUCTURE_NETWORK_CIDR=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Infrastructure Network CIDR".value')
PKS_INFRASTRUCTURE_RESERVED_IP_RANGES=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Infrastructure Network Reserved IP Ranges".value')
PKS_INFRASTRUCTURE_DNS=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Infrastructure Network DNS".value')
PKS_INFRASTRUCTURE_GATEWAY=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Infrastructure Network Gateway".value')
PKS_INFRASTRUCTURE_AVAILABILITY_ZONES=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Availability Zones".value' | tr -d '\n')
PKS_MAIN_NETWORK_NAME=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Main Network Name".value')
PKS_MAIN_IAAS_IDENTIFIER=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Main Network Google Network Name ".value')
PKS_MAIN_NETWORK_CIDR=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Main Network CIDR".value')
PKS_MAIN_RESERVED_IP_RANGES=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Main Network Reserved IP Ranges".value')
PKS_MAIN_DNS=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Main Network DNS".value')
PKS_MAIN_GATEWAY=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Main Network Gateway".value')
PKS_MAIN_AVAILABILITY_ZONES=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Availability Zones".value' | tr -d '\n')
PKS_SERVICES_NETWORK_NAME=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Service Network Name".value')
PKS_SERVICES_IAAS_IDENTIFIER=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Service Network Google Network Name ".value')
PKS_SERVICES_NETWORK_CIDR=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Service Network CIDR".value')
PKS_SERVICES_RESERVED_IP_RANGES=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Services Network Reserved IP Ranges".value')
PKS_SERVICES_DNS=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Services Network DNS".value')
PKS_SERVICES_GATEWAY=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Services Network Gateway".value')
PKS_SERVICES_AVAILABILITY_ZONES=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Availability Zones".value' | tr -d '\n')
SINGLETON_AVAILABILITY_NETWORK=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Infrastructure Network Name".value')
SINGLETON_AVAILABILITY_ZONE=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Availability Zones".value | .[0]')

cat <<EOF > config-director.yml
iaas-configuration:
  project: $GCP_PROJECT_ID
  default_deployment_tag: $GCP_RESOURCE_PREFIX
  auth_json: |
    $GCP_SERVICE_ACCOUNT_KEY
director-configuration:
  ntp_servers_string: metadata.google.internal
  resurrector_enabled: true
  post_deploy_enabled: true
  database_type: internal
  blobstore_type: local
az-configuration: $AVAILABILITY_ZONES
networks-configuration:
  icmp_checks_enabled: false
  networks:
  - name: $PKS_INFRASTRUCTURE_NETWORK_NAME
    service_network: false
    subnets:
    - iaas_identifier: $PKS_INFRASTRUCTURE_IAAS_IDENTIFIER
      cidr: $PKS_INFRASTRUCTURE_NETWORK_CIDR
      reserved_ip_ranges: $PKS_INFRASTRUCTURE_RESERVED_IP_RANGES
      dns: $PKS_INFRASTRUCTURE_DNS
      gateway: $PKS_INFRASTRUCTURE_GATEWAY
      availability_zone_names: $PKS_INFRASTRUCTURE_AVAILABILITY_ZONES
  - name: $PKS_MAIN_NETWORK_NAME
    service_network: false
    subnets:
    - iaas_identifier: $PKS_MAIN_IAAS_IDENTIFIER
      cidr: $PKS_MAIN_NETWORK_CIDR
      reserved_ip_ranges: $PKS_MAIN_RESERVED_IP_RANGES
      dns: $PKS_MAIN_DNS
      gateway: $PKS_MAIN_GATEWAY
      availability_zone_names: $PKS_MAIN_AVAILABILITY_ZONES
  - name: $PKS_SERVICES_NETWORK_NAME
    service_network: true
    subnets:
    - iaas_identifier: $PKS_SERVICES_IAAS_IDENTIFIER
      cidr: $PKS_SERVICES_NETWORK_CIDR
      reserved_ip_ranges: $PKS_SERVICES_RESERVED_IP_RANGES
      dns: $PKS_SERVICES_DNS
      gateway: $PKS_SERVICES_GATEWAY
      availability_zone_names: $PKS_SERVICES_AVAILABILITY_ZONES
network-assignment:
  network:
    name: $SINGLETON_AVAILABILITY_NETWORK
  singleton_availability_zone:
    name: $SINGLETON_AVAILABILITY_ZONE
security-configuration:
  trusted_certificates: "$OPS_MGR_TRUSTED_CERTS"
  vm_password_type: generate
resource-configuration:
  director:
    instance_type:
      id: $DIRECTOR_VM_TYPE
    internet_connected: $INTERNET_CONNECTED
  compilation:
    instance_type:
      id: large.cpu
    internet_connected: $INTERNET_CONNECTED
EOF
```
Configure the Ops Manager with `config-director.yml`.
```bash
om --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
   --skip-ssl-validation \
   --username "$OPS_MGR_USR" \
   --password "$OPS_MGR_PWD" \
   configure-director \
   --config config-director.yml
```
Output
```bash
started configuring director options for bosh tile
finished configuring director options for bosh tile
started configuring availability zone options for bosh tile
finished configuring availability zone options for bosh tile
started configuring network options for bosh tile
finished configuring network options for bosh tile
started configuring network assignment options for bosh tile
finished configuring network assignment options for bosh tile
started configuring resource options for bosh tile
applying resource configuration for the following jobs:
  compilation
  director
finished configuring resource options for bosh tile
```
### Apply Changes
```bash
OPSMAN_DOMAIN_OR_IP_ADDRESS=$(cat terraform.tfstate | jq -r '.modules[0].resources."google_compute_address.ops-manager-public-ip".primary.attributes.address')
om --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
   --skip-ssl-validation \
   --username "${OPS_MGR_USR}" \
   --password "${OPS_MGR_PWD}" \
   apply-changes \
   --ignore-warnings
```

# Deploying PKS
### Upload PKS Tile to Ops Manager
Access `https://network.pivotal.io/products/pivotal-container-service/`. Click `i` button next to the `pivotal-container-service-x.y.z-build.N.pivotal` to get the file name and download URL. Set them to the environment variables.
```bash
FILENAME=pivotal-container-service-1.4.0-build.31.pivotal
DOWNLOAD_URL=https://network.pivotal.io/api/v2/products/pivotal-container-service/releases/354903/product_files/366115/download
```
Access `https://network.pivotal.io/users/dashboard/edit-profile` and click `REQUEST NEW REFRESH TOKEN` to get a refresh token.
```bash
REFRESH_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```
Get `ACCESS_TOKEN` with the command below.
```bash
ACCESS_TOKEN=`curl -s https://network.pivotal.io/api/v2/authentication/access_tokens -d "{\"refresh_token\":\"${REFRESH_TOKEN}\"}" | jq -r .access_token`
```
Download `pivotal-container-service-x.y.z-build.N.pivotal` on the Ops Mamager.
```bash
PKS_ENV_PREFIX=${ENV_PREFIX}
ZONE=`gcloud compute instances list --filter name:${PKS_ENV_PREFIX}-ops-manager | awk 'NR>1 {print $2}'`

gcloud compute ssh ubuntu@${PKS_ENV_PREFIX}-ops-manager \
    --zone ${ZONE} \
    --force-key-file-overwrite \
    --strict-host-key-checking=no \
    --quiet \
    --command "wget -q -O "${FILENAME}" --header='Authorization: Bearer ${ACCESS_TOKEN}' ${DOWNLOAD_URL}"
```
Install `om` command on the Ops Manager.
```bash
gcloud compute ssh ubuntu@${PKS_ENV_PREFIX}-ops-manager \
    --zone ${ZONE} \
    --force-key-file-overwrite \
    --strict-host-key-checking=no \
    --quiet \
    --command "wget -q -O om https://github.com/pivotal-cf/om/releases/download/0.37.0/om-linux && chmod +x om && sudo mv om /usr/local/bin/"
```
Upload `pivotal-container-service-x.y.z-build.N.pivotal` to the Ops Manager.
```bash
PRODUCT_NAME=`basename $FILENAME .pivotal | python -c 'print("-".join(raw_input().split("-")[:-2]))'` # pivotal-container-service
PRODUCT_VERSION=`basename $FILENAME .pivotal | python -c 'print("-".join(raw_input().split("-")[-2:]))'` # 1.0.4-build.5

gcloud compute ssh ubuntu@${PKS_ENV_PREFIX}-ops-manager \
  --zone ${ZONE} \
  --force-key-file-overwrite \
  --strict-host-key-checking=no \
  --quiet \
  --command "om --target https://localhost -k -u ${OPS_MGR_USR} -p ${OPS_MGR_PWD} --request-timeout 3600 upload-product -p ~/${FILENAME}"   
```
Output
```bash
beginning product upload to Ops Manager
 2.43 GiB / 2.43 GiB  100.00% 49s32sss
2m28s elapsed, waiting for response from Ops Manager...
finished upload
```
### Staging PKS Tile
```bash
gcloud compute ssh ubuntu@${PKS_ENV_PREFIX}-ops-manager \
  --zone ${ZONE} \
  --force-key-file-overwrite \
  --strict-host-key-checking=no \
  --quiet \
  --command "om --target https://localhost -k -u ${OPS_MGR_USR} -p ${OPS_MGR_PWD} stage-product -p ${PRODUCT_NAME} -v ${PRODUCT_VERSION}"
```
Output
```bash
staging pivotal-container-service 1.0.4-build.5
finished staging
```

### Download Stemcell
For ubuntu-xenial 250.25:
```
SC_FILENAME=light-bosh-stemcell-250.25-google-kvm-ubuntu-xenial-go_agent.tgz
SC_DOWNLOAD_URL=https://network.pivotal.io/api/v2/products/stemcells-ubuntu-xenial/releases/331971/product_files/340983/download
```
Download `light-bosh-stemcell-250.25-google-kvm-ubuntu-xenial-go_agent.tgz` on the Ops Manager.
```bash
ACCESS_TOKEN=`curl -s https://network.pivotal.io/api/v2/authentication/access_tokens -d "{\"refresh_token\":\"${REFRESH_TOKEN}\"}" | jq -r .access_token`

gcloud compute ssh ubuntu@${PKS_ENV_PREFIX}-ops-manager \
    --zone ${ZONE} \
    --force-key-file-overwrite \
    --strict-host-key-checking=no \
    --quiet \
    --command "wget -q -O "${SC_FILENAME}" --header='Authorization: Bearer ${ACCESS_TOKEN}' ${SC_DOWNLOAD_URL}"
```
Upload stemcell to the Ops Manager:
```bash
gcloud compute ssh ubuntu@${PKS_ENV_PREFIX}-ops-manager \
  --zone ${ZONE} \
  --force-key-file-overwrite \
  --strict-host-key-checking=no \
  --quiet \
  --command "om --target https://localhost -k -u ${OPS_MGR_USR} -p ${OPS_MGR_PWD} --request-timeout 3600 upload-stemcell -s ~/${SC_FILENAME}"   
```
Output
```
beginning stemcell upload to Ops Manager
 19.17 KiB / 19.17 KiB  100.00% 0s
finished upload
```

### Configure PKS Tile
Create a config file: `config-pks.yml`.
If you don't want to assign public IP addresses to K8s cluster nodes, set a `- null` instead of `- public_ip` in the  `.properties.vm_extensions:`.
```bash
om_generate_cert() (
  set -eu
  local domains="$1"
  local data=$(echo $domains | jq --raw-input -c '{"domains": (. | split(" "))}')
  local response=$(
    om --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
       --username "$OPS_MGR_USR" \
       --password "$OPS_MGR_PWD" \
       --skip-ssl-validation \
       curl \
       --silent \
       --path "/api/v0/certificates/generate" \
       -x POST \
       -d $data
    )
    echo "$response"
)

OPSMAN_DOMAIN_OR_IP_ADDRESS=$(cat terraform.tfstate | jq -r '.modules[0].resources."google_compute_address.ops-manager-public-ip".primary.attributes.address')
PKS_API_IP=$(cat terraform.tfstate | jq -r '.modules[0].resources."google_compute_address.pks-api-ip".primary.attributes.address')
PKS_DOMAIN=$(echo $PKS_API_IP | tr '.' '-').sslip.io
AUTH_JSON=$(cat terraform.tfstate | jq -r '.modules[0].outputs.AuthJSON.value')
GCP_PROJECT_ID=$(echo $AUTH_JSON | tr -d '[:cntrl:]' | jq -r .project_id)
GCP_NETWORK=$(cat terraform.tfstate | jq -r '.modules[0].resources."google_compute_network.pks-network".primary.id')
GCP_RESOURCE_PREFIX=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Default Deployment Tag".value')
PKS_MAIN_NETWORK_NAME=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Main Network Name".value')
PKS_SERVICES_NETWORK_NAME=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Service Network Name".value')
SINGLETON_AVAILABILITY_ZONE=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Availability Zones".value | .[0]')
AVAILABILITY_ZONES=$(cat terraform.tfstate | jq -r '.modules[0].outputs."Availability Zones".value | map({name: .})' | tr -d '\n' | tr -d '"')
CERTIFICATES=$(om_generate_cert "*.sslip.io *.x.sslip.io")
CERT_PEM=$(echo $CERTIFICATES  | tr '\"' '\n' | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' | sed 's/^/        /')
KEY_PEM=$(echo $CERTIFICATES  | tr '\"' '\n' | awk '/-----BEGIN RSA PRIVATE KEY-----/,/-----END RSA PRIVATE KEY-----/' | sed 's/^/        /')
GCP_MASTER_SERVICE_ACCOUNT_KEY=$(cat terraform.tfstate | jq -r '.modules[0].outputs.pks_master_node_service_account_key.value' | sed 's/^/      /')
GCP_WORKER_SERVICE_ACCOUNT_KEY=$(cat terraform.tfstate | jq -r '.modules[0].outputs.pks_worker_node_service_account_key.value' | sed 's/^/      /')
UAA_URL=api-${PKS_DOMAIN}
LB_NAME="tcp:${GCP_RESOURCE_PREFIX}-pks-api"

cat <<EOF > config-pks.yml
network-properties:
  singleton_availability_zone:
    name: asia-northeast1-a
  other_availability_zones:
  - name: asia-northeast1-a
  - name: asia-northeast1-b
  - name: asia-northeast1-c
  network:
    name: pks-main
  service_network:
    name: pks-services
product-properties:
  .pivotal-container-service.pks_tls:
    value:
      cert_pem: |
$CERT_PEM
      private_key_pem: |
$KEY_PEM
  .properties.pks_api_hostname:
    value: api-${PKS_DOMAIN}
  .properties.worker_max_in_flight: # The maximum number of non-canary instances to update in parallel within an availability zone.
    value: 1 # Maximum number of worker VMs created at a time (PKS API Service -> Worker VM Max in Flight)
  .properties.plan1_selector:
    value: Plan Active
  .properties.plan1_selector.active.allow_privileged_containers:
    value: false
  .properties.plan1_selector.active.description:
    value: "minimum resources for demo\r\nmaster node: 1\r\nworker node: 1"
  .properties.plan1_selector.active.errand_vm_type:
    value: micro
  .properties.plan1_selector.active.master_az_placement:
    value:
    - asia-northeast1-a
  .properties.plan1_selector.active.master_instances:
    value: 1
  .properties.plan1_selector.active.master_persistent_disk_type:
    value: "10240"
  .properties.plan1_selector.active.master_vm_type:
    value: micro
  .properties.plan1_selector.active.max_worker_instances:
    value: 50
  .properties.plan1_selector.active.name:
    value: small
  .properties.plan1_selector.active.worker_az_placement:
    value:
    - asia-northeast1-a
    - asia-northeast1-b
    - asia-northeast1-c
  .properties.plan1_selector.active.worker_instances:
    value: 1
  .properties.plan1_selector.active.worker_persistent_disk_type:
    value: "51200"
  .properties.plan1_selector.active.worker_vm_type:
    value: medium
  .properties.plan2_selector:
    value: Plan Active
  .properties.plan2_selector.active.allow_privileged_containers:
    value: false
  .properties.plan2_selector.active.description:
    value: "medium\r\nmaster node: 1\r\nworker node: 3"
  .properties.plan2_selector.active.errand_vm_type:
    value: micro
  .properties.plan2_selector.active.eviction_hard:
    value: memory.available=100Mi, nodefs.available=10%, nodefs.inodesFree=5%
  .properties.plan2_selector.active.master_az_placement:
    value:
    - asia-northeast1-a
    - asia-northeast1-b
    - asia-northeast1-c
  .properties.plan2_selector.active.master_instances:
    value: 1
  .properties.plan2_selector.active.master_persistent_disk_type:
    value: "10240"
  .properties.plan2_selector.active.master_vm_type:
    value: small
  .properties.plan2_selector.active.max_worker_instances:
    value: 50
  .properties.plan2_selector.active.name:
    value: medium
  .properties.plan2_selector.active.system_reserved:
    value: memory=250Mi, cpu=150m
  .properties.plan2_selector.active.worker_az_placement:
    value:
    - asia-northeast1-a
    - asia-northeast1-b
    - asia-northeast1-c
  .properties.plan2_selector.active.worker_instances:
    value: 3
  .properties.plan2_selector.active.worker_persistent_disk_type:
    value: "51200"
  .properties.plan2_selector.active.worker_vm_type:
    value: medium
  .properties.plan3_selector:
    value: Plan Active
  .properties.plan3_selector.active.allow_privileged_containers:
    value: false
  .properties.plan3_selector.active.description:
    value: "medium\r\nmaster node: 3\r\nworker node: 5"
  .properties.plan3_selector.active.errand_vm_type:
    value: micro
  .properties.plan3_selector.active.eviction_hard:
    value: memory.available=100Mi, nodefs.available=10%, nodefs.inodesFree=5%
  .properties.plan3_selector.active.master_az_placement:
    value:
    - asia-northeast1-a
    - asia-northeast1-b
    - asia-northeast1-c
  .properties.plan3_selector.active.master_instances:
    value: 3
  .properties.plan3_selector.active.master_persistent_disk_type:
    value: "10240"
  .properties.plan3_selector.active.master_vm_type:
    value: small
  .properties.plan3_selector.active.max_worker_instances:
    value: 50
  .properties.plan3_selector.active.name:
    value: medium
  .properties.plan3_selector.active.system_reserved:
    value: memory=250Mi, cpu=150m
  .properties.plan3_selector.active.worker_az_placement:
    value:
    - asia-northeast1-a
    - asia-northeast1-b
    - asia-northeast1-c
  .properties.plan3_selector.active.worker_instances:
    value: 5
  .properties.plan3_selector.active.worker_persistent_disk_type:
    value: "51200"
  .properties.plan3_selector.active.worker_vm_type:
    value: medium
  .properties.plan4_selector:
    value: Plan Inactive
  .properties.plan4_selector.active.allow_privileged_containers:
    value: false
  .properties.plan4_selector.active.description:
    value: 'Example: This plan will configure a large kubernetes cluster for resource
      heavy workloads, or a high number of workloads.'
  .properties.plan4_selector.active.master_instances:
    value: 3
  .properties.plan4_selector.active.max_worker_instances:
    value: 50
  .properties.plan4_selector.active.name:
    value: Plan-4
  .properties.plan4_selector.active.worker_instances:
    value: 5
  .properties.plan5_selector:
    value: Plan Inactive
  .properties.plan5_selector.active.allow_privileged_containers:
    value: false
  .properties.plan5_selector.active.description:
    value: 'Example: This plan will configure a large kubernetes cluster for resource
      heavy workloads, or a high number of workloads.'
  .properties.plan5_selector.active.master_instances:
    value: 3
  .properties.plan5_selector.active.max_worker_instances:
    value: 50
  .properties.plan5_selector.active.name:
    value: Plan-5
  .properties.plan5_selector.active.worker_instances:
    value: 5
  .properties.plan6_selector:
    value: Plan Inactive
  .properties.plan6_selector.active.allow_privileged_containers:
    value: false
  .properties.plan6_selector.active.description:
    value: 'Example: This plan will configure a large kubernetes cluster for resource
      heavy workloads, or a high number of workloads.'
  .properties.plan6_selector.active.master_instances:
    value: 3
  .properties.plan6_selector.active.max_worker_instances:
    value: 50
  .properties.plan6_selector.active.name:
    value: Plan-6
  .properties.plan6_selector.active.worker_instances:
    value: 5
  .properties.plan7_selector:
    value: Plan Inactive
  .properties.plan7_selector.active.allow_privileged_containers:
    value: false
  .properties.plan7_selector.active.description:
    value: 'Example: This plan will configure a large kubernetes cluster for resource
      heavy workloads, or a high number of workloads.'
  .properties.plan7_selector.active.master_instances:
    value: 3
  .properties.plan7_selector.active.max_worker_instances:
    value: 50
  .properties.plan7_selector.active.name:
    value: Plan-7
  .properties.plan7_selector.active.worker_instances:
    value: 5
  .properties.plan8_selector:
    value: Plan Inactive
  .properties.plan8_selector.active.allow_privileged_containers:
    value: false
  .properties.plan8_selector.active.description:
    value: 'Example: This plan will configure a large kubernetes cluster for resource
      heavy workloads, or a high number of workloads.'
  .properties.plan8_selector.active.master_instances:
    value: 3
  .properties.plan8_selector.active.max_worker_instances:
    value: 50
  .properties.plan8_selector.active.name:
    value: Plan-8
  .properties.plan8_selector.active.worker_instances:
    value: 5
  .properties.plan9_selector:
    value: Plan Inactive
  .properties.plan9_selector.active.allow_privileged_containers:
    value: false
  .properties.plan9_selector.active.description:
    value: 'Example: This plan will configure a large kubernetes cluster for resource
      heavy workloads, or a high number of workloads.'
  .properties.plan9_selector.active.master_instances:
    value: 3
  .properties.plan9_selector.active.max_worker_instances:
    value: 50
  .properties.plan9_selector.active.name:
    value: Plan-9
  .properties.plan9_selector.active.worker_instances:
    value: 5
  .properties.plan10_selector:
    value: Plan Inactive
  .properties.plan10_selector.active.allow_privileged_containers:
    value: false
  .properties.plan10_selector.active.description:
    value: 'Example: This plan will configure a large kubernetes cluster for resource
      heavy workloads, or a high number of workloads.'
  .properties.plan10_selector.active.master_instances:
    value: 3
  .properties.plan10_selector.active.max_worker_instances:
    value: 50
  .properties.plan10_selector.active.name:
    value: Plan-10
  .properties.plan10_selector.active.worker_instances:
    value: 5
  .properties.cloud_provider:
    value: GCP
  .properties.cloud_provider.gcp.project_id:
    value: $GCP_PROJECT_ID
  .properties.cloud_provider.gcp.network:
    value: $GCP_NETWORK
  .properties.cloud_provider.gcp.master_service_account:
    value: ${ACCOUNT_NAME}-pks-master-node@${PROJECT_ID}.iam.gserviceaccount.com
  .properties.cloud_provider.gcp.worker_service_account:
    value: ${PKS_ENV_PREFIX}-pks-worker-node@${PROJECT_ID}.iam.gserviceaccount.com
#  .properties.cloud_provider.vsphere.vcenter_master_creds:
#    value:
#      password: '***'
#  .properties.cloud_provider.azure.azure_cloud_name:
#    value: AzurePublicCloud
  .properties.syslog_selector:
    value: disabled
#  .properties.syslog_selector.enabled.transport_protocol:
#    value: tcp
#  .properties.syslog_selector.enabled.tls_enabled:
#    value: true
  .properties.pks-vrli:
    value: disabled
#  .properties.pks-vrli.enabled.skip_cert_verify:
#    value: false
#  .properties.pks-vrli.enabled.use_ssl:
#    value: true
  .properties.log_sink_resources_deploy:
    value: true
  .properties.metric_sink_resources_deploy:
    value: true
  .properties.network_selector:
    value: flannel
  .properties.network_selector.flannel.pod_network_cidr:
    value: 10.200.0.0/16
  .properties.network_selector.flannel.service_cluster_cidr:
    value: 10.100.200.0/24
#  .properties.network_selector.nsx.lb_size_large_supported:
#    value: true
#  .properties.network_selector.nsx.lb_size_medium_supported:
#    value: true
#  .properties.network_selector.nsx.nat_mode:
#    value: true
#  .properties.network_selector.nsx.network_automation:
#    value: true
#  .properties.network_selector.nsx.nsx-t-insecure:
#    value: false
#  .properties.network_selector.nsx.nsx-t-superuser-certificate:
#    value:
#      private_key_pem: '***'
#  .properties.proxy_selector.enabled.http_proxy_credentials:
#    value:
#      password: '***'
#  .properties.proxy_selector.enabled.https_proxy_credentials:
#    value:
#      password: '***'
  .properties.proxy_selector:
    value: Disabled
  .properties.vm_extensions:
    value:
    - public_ip # Networking -> Enable outbound internet access (Warning: Not allowing internet access will require a NAT instance. To do so, set a null value instead of public_ip)
  .properties.uaa_pks_cli_access_token_lifetime:
    value: 600
  .properties.uaa_pks_cli_refresh_token_lifetime:
    value: 21600
  .properties.uaa_oidc:
    value: false
  .properties.uaa:
    value: internal
#  .properties.uaa.ldap.credentials:
#    value:
#      password: '***'
#  .properties.uaa.ldap.external_groups_whitelist:
#    value: '*'
#  .properties.uaa.ldap.group_search_filter:
#    value: member={0}
#  .properties.uaa.ldap.ldap_referrals:
#    value: follow
#  .properties.uaa.ldap.mail_attribute_name:
#    value: mail
#  .properties.uaa.ldap.search_filter:
#    value: cn={0}
  .properties.wavefront:
    value: disabled
#  .properties.wavefront.enabled.wavefront_token:
#    value:
#      secret: '***'
  .properties.pks-vrops:
    value: disabled # Configure PKS Monitoring Integration(s) -> Deploy cAdvisor by VMware Integration
  .properties.telemetry_selector:
    value: disabled
#  .properties.telemetry_selector.enabled.billing_polling_interval:
#    value: 60
#  .properties.telemetry_selector.enabled.environment_provider:
#    value: none
#  .properties.telemetry_selector.enabled.telemetry_polling_interval:
#    value: 600
#  .properties.telemetry_selector.enabled.telemetry_url:
#    value: https://vcsa.vmware.com/ph
resource-config:
  pivotal-container-service:
    instances: automatic
    persistent_disk:
      size_mb: automatic
    instance_type:
      id: automatic
    internet_connected: $INTERNET_CONNECTED
    elb_names:
    - tcp:${PKS_ENV_PREFIX}-pks-api
EOF
```
Configure the PKS Tile with `config-pks.yml`.
```bash
om --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
   --username "$OPS_MGR_USR" \
   --password "$OPS_MGR_PWD" \
   --skip-ssl-validation \
   configure-product \
   --product-name "${PRODUCT_NAME}" \
   --config config-pks.yml
```
### Apply Changes
```bash
OPSMAN_DOMAIN_OR_IP_ADDRESS=$(cat terraform.tfstate | jq -r '.modules[0].resources."google_compute_address.ops-manager-public-ip".primary.attributes.address')
om --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
   --skip-ssl-validation \
   --username "${OPS_MGR_USR}" \
   --password "${OPS_MGR_PWD}" \
   apply-changes \
   --ignore-warnings
```

# Login to PKS API
### Get API Endpoint
```bash
cat <<EOF
PKS API: https://api-${PKS_DOMAIN}:9021
UAA: https://api-${PKS_DOMAIN}:8443
EOF
```
Output
```bash
PKS API: https://api-xxx-xxx-xxx-xxx.sslip.io:9021
UAA: https://api-xxx-xxx-xxx-xxx.sslip.io:8443
```
### Get Admin Client Secret from the Ops Manager
Get an `admin` client secret from the Ops Manager.
Access the Ops Manager from a web browser -> Click Pivotal Container Service Tile -> Click `Credentials Tab` -> Pks Uaa ManagementAdmin Client `Link to Credential`.
Or you can get it with the command bellow.
```bash
GUID=$(om \
    --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
    --username "$OPS_MGR_USR" \
    --password "$OPS_MGR_PWD" \
    --skip-ssl-validation \
    curl \
    --silent \
    --path "/api/v0/staged/products" \
    -x GET \
    | jq -r '.[] | select(.type == "pivotal-container-service") | .guid'
)
ADMIN_SECRET=$(om \
    --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
    --username "$OPS_MGR_USR" \
    --password "$OPS_MGR_PWD" \
    --skip-ssl-validation \
    curl \
    --silent \
    --path "/api/v0/deployed/products/${GUID}/credentials/.properties.pks_uaa_management_admin_client" \
    -x GET \
    | jq -r '.credential.value.secret'
)
```
### Get Access Token for Admin Client
```bash
UAA_URL=https://api-${PKS_DOMAIN}:8443

gcloud compute ssh ubuntu@${PKS_ENV_PREFIX}-ops-manager \
  --zone ${ZONE} \
  --force-key-file-overwrite \
  --strict-host-key-checking=no \
  --quiet \
  --command "uaac target ${UAA_URL} --skip-ssl-validation && uaac token client get admin -s ${ADMIN_SECRET}"
```
Output
```bash
Unknown key: Max-Age = 86400

Successfully fetched token via client credentials grant.
Target: https://api-xxx-xxx-xxx-xxx.sslip.io:8443
Context: admin, from client admin
```
### Create UAA User
```bash
PKS_USER=demo@example.com
PKS_PASSWORD=password1234

gcloud compute ssh ubuntu@${PKS_ENV_PREFIX}-ops-manager \
  --zone ${ZONE} \
  --force-key-file-overwrite \
  --strict-host-key-checking=no \
  --quiet \
  --command "uaac user add ${PKS_USER} --emails ${PKS_USER} -p ${PKS_PASSWORD}"
```
Output
```bash
user account successfully added
```
### Configure Scope
Configure scopes to make uaa users accessible to pks commands.
There are two types of scopes.
- `pks.clusters.admin` members have access to all the clusters.
- `pks.clusters.manage` members have access only to the clusters that created themselves.
Create `pks.clusters.admin`.
```bash
gcloud compute ssh ubuntu@${PKS_ENV_PREFIX}-ops-manager \
  --zone ${ZONE} \
  --force-key-file-overwrite \
  --strict-host-key-checking=no \
  --quiet \
  --command "uaac member add pks.clusters.admin ${PKS_USER}"
```
Output
```bash
success
```
### Login to PKS API
```bash
PKS_API_URL=https://api-${PKS_DOMAIN}:9021

pks login -k -a ${PKS_API_URL} -u ${PKS_USER} -p ${PKS_PASSWORD}
```
Output
```bash
API Endpoint: https://api-35-200-113-234.sslip.io:9021
User: demo@example.com
```


### om Command Memo
List config.
```bash
ubuntu@env-prefix-ops-manager:~$ om --target https://localhost -k -u OPS_MGR_USR -p OPS_MGR_PWD available-products
```
```bash
ubuntu@env-prefix-ops-manager:~$ om --target https://localhost -k -u OPS_MGR_USR -p OPS_MGR_PWD staged-config --product-name pivotal-container-service
```
Revert staged changes.
```bash
ubuntu@env-prefix-ops-manager:~$ om --target https://localhost -k -u OPS_MGR_USR -p OPS_MGR_PWD revert-staged-changes --product-name pivotal-container-service
```
Remove PKS and BOSH from the Ops Manager.
```bash
ubuntu@env-prefix-ops-manager:~$ om --target https://localhost -k -u OPS_MGR_USR -p OPS_MGR_PWD delete-installation --product-name pivotal-container-service
```
