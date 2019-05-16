# Terraforming PKS GCP

Huge thanks to @pivotal-cf for [https://github.com/pivotal-cf/terraforming-gcp](https://github.com/pivotal-cf/terraforming-gcp). I have taken their work and upgraded it in accordance with current [PKS](https://docs.pivotal.io/runtimes/pks/1-0/gcp.html) documentation for GCP.

## Prerequisites

Your system needs the `gcloud` cli, as well as `terraform`:

```bash
brew update
brew install Caskroom/cask/google-cloud-sdk
brew install terraform
```

### Service Account

You will need a key file for your service account to allow terraform to deploy resources. If you don't have one, you can create a service account and a key for it:

```
export PROJECT_ID="XXXXXXXX"
export ACCOUNT_NAME="YYYYYYYY"
gcloud iam service-accounts create ${ACCOUNT_NAME} --display-name "PKS Account"
gcloud iam service-accounts keys create "terraform.key.json" --iam-account "${ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud projects add-iam-policy-binding ${PROJECT_ID} --member "serviceAccount:${ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --role 'roles/owner'
```
### Prep Environment Values

export ENV_PREFIX="XXXXXXXXX" # up to you
export OPS_IMAGE_URL="https://storage.googleapis.com/ops-manager-us/pcf-gcp-2.5.2-build.172.tar.gz"

### Var File

Copy the stub content below into a terminal to create `terraform.tfvars` file. Make sure it's located in the root of this project.
These vars will be used when you run `terraform  apply`.
You should fill in the stub values with the correct content.

```hcl
cat << EOF > terraform.tfvars
env_prefix = "${ENV_PREFIX}"
project = "${PROJECT_ID}"
region = "asia-northeast1"
zones = ["asia-northeast1-a", "asia-northeast1-b", "asia-northeast1-c"]
service_account_key = <<SERVICE_ACCOUNT_KEY
$(cat ./terraform.key.json)
SERVICE_ACCOUNT_KEY
nat_machine_type = "n1-standard-4"
opsman_image_url = "${OPS_IMAGE_URL}"
opsman_machine_type = "n1-standard-2"
EOF
```
```
cat terraform.tfvars # confirm all values correctly set
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


# Configuring OpsMan
PCF Ops Manager v2.5.2-build.172
pivotal-container-service-1.4.0-build.31

## Configuring BOSH Director
opsman_image_url = "https://storage.googleapis.com/ops-manager-us/pcf-gcp-2.5.2-build.172.tar.gz"

FILENAME=pivotal-container-service-1.4.0-build.31.pivotal
DOWNLOAD_URL=https://network.pivotal.io/api/v2/products/pivotal-container-service/releases/354903/product_files/366115/download


ENV_PREFIX=XXXXX

## Configuring PKS Tile
### Generate Certificate for PKS API
```bash
# func for generate a certificate
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

# Prep for ENV VAR
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

# create config-pks.yml
cat <<EOF > config-pks.yml
product-properties:
  .pivotal-container-service.pks_tls:
    value:
      cert_pem: |
$CERT_PEM
      private_key_pem: |
$KEY_PEM
  .properties.cloud_provider:
    value: GCP
  .properties.cloud_provider.gcp.master_service_account:
    value: ${ACCOUNT_NAME}-pks-master-node@${PROJECT_ID}.iam.gserviceaccount.com
  .properties.cloud_provider.gcp.network:
    value: $GCP_NETWORK
  .properties.cloud_provider.gcp.project_id:
    value: $GCP_PROJECT_ID
  .properties.cloud_provider.gcp.worker_service_account:
    value: ${ENV_PREFIX}-pks-worker-node@${PROJECT_ID}.iam.gserviceaccount.com
  .properties.network_selector:
    value: flannel
  .properties.network_selector.flannel.pod_network_cidr:
    value: 10.200.0.0/16
  .properties.network_selector.flannel.service_cluster_cidr:
    value: 10.100.200.0/24
  .properties.pks-vrli:
    value: disabled
  .properties.pks-vrli.enabled.skip_cert_verify:
    value: false
  .properties.pks-vrli.enabled.use_ssl:
    value: true
  .properties.pks-vrops:
    value: disabled
  .properties.pks_api_hostname:
    value: api-${PKS_DOMAIN}
  .properties.plan1_selector:
    value: Plan Active
  .properties.plan1_selector.active.allow_privileged_containers:
    value: false
  .properties.plan1_selector.active.description:
    value: 'minimum resources for demo'
  .properties.plan1_selector.active.master_az_placement:
    value:
    - asia-northeast1-a
  .properties.plan1_selector.active.master_instances:
    value: 1
  .properties.plan1_selector.active.max_worker_instances:
    value: 50
  .properties.plan1_selector.active.name:
    value: small
  .properties.plan1_selector.active.worker_az_placement:
    value:
    -  asia-northeast1-a
    -  asia-northeast1-b
    -  asia-northeast1-c
  .properties.plan1_selector.active.worker_instances:
    value: 1
  .properties.plan2_selector:
    value: Plan Inactive
  .properties.plan2_selector.active.allow_privileged_containers:
    value: false
  .properties.plan2_selector.active.description:
    value: 'Example: This plan will configure a medium sized kubernetes cluster, suitable
      for more pods.'
  .properties.plan2_selector.active.master_instances:
    value: 3
  .properties.plan2_selector.active.max_worker_instances:
    value: 50
  .properties.plan2_selector.active.name:
    value: medium
  .properties.plan2_selector.active.worker_instances:
    value: 5
  .properties.plan3_selector:
    value: Plan Inactive
  .properties.plan3_selector.active.allow_privileged_containers:
    value: false
  .properties.plan3_selector.active.description:
    value: 'Example: This plan will configure a large kubernetes cluster for resource
      heavy workloads, or a high number of workloads.'
  .properties.plan3_selector.active.master_instances:
    value: 3
  .properties.plan3_selector.active.max_worker_instances:
    value: 50
  .properties.plan3_selector.active.name:
    value: large
  .properties.plan3_selector.active.worker_instances:
    value: 5
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
  .properties.proxy_selector:
    value: Disabled
  .properties.syslog_selector:
    value: disabled
  .properties.syslog_selector.enabled.tls_enabled:
    value: true
  .properties.syslog_selector.enabled.transport_protocol:
    value: tcp
  .properties.telemetry_selector:
    value: disabled
  .properties.telemetry_selector.enabled.billing_polling_interval:
    value: 60
  .properties.telemetry_selector.enabled.environment_provider:
    value: none
  .properties.telemetry_selector.enabled.telemetry_polling_interval:
    value: 600
  .properties.uaa:
    value: internal
  .properties.uaa_oidc:
    value: false
  .properties.uaa_pks_cli_access_token_lifetime:
    value: 600
  .properties.uaa_pks_cli_refresh_token_lifetime:
    value: 21600
  .properties.vm_extensions:
    value:
    - public_ip
  .properties.wavefront:
    value: disabled
  .properties.worker_max_in_flight:
    value: 1
network-properties:
  network:
    name: $PKS_MAIN_NETWORK_NAME
  other_availability_zones:
  - name: asia-northeast1-a
  - name: asia-northeast1-b
  - name: asia-northeast1-c
  service_network:
    name: $PKS_SERVICES_NETWORK_NAME
  singleton_availability_zone:
    name: $SINGLETON_AVAILABILITY_ZONE
resource-config:
  pivotal-container-service:
    instnces: automatic
    persistent_disk:
      size_mb: automatic
    instance_type:
      id: automatic
    elb_names:
    - tcp:${ENV_PREFIX}-pks-api
    internet_connected: $INTERNET_CONNECTED
EOF

# apply config-pks.yml
om --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
   --username "$OPS_MGR_USR" \
   --password "$OPS_MGR_PWD" \
   --skip-ssl-validation \
   configure-product \
   --product-name "${PRODUCT_NAME}" \
   --config config-pks.yml
```
