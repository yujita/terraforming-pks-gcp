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


### Var File

Copy the stub content below into a file called `terraform.tfvars` and put it in the root of this project.
These vars will be used when you run `terraform  apply`.
You should fill in the stub values with the correct content.

```hcl
cat << EOF > terraform.tfvars
env_prefix = "my-pks-eu"
project = "your-gcp-project"
region = "asia-northeast1"
zones = ["asia-northeast1-a", "asia-northeast1-b", "asia-northeast1-c"]
service_account_key = <<SERVICE_ACCOUNT_KEY
$(cat ../terraform.key.json)
SERVICE_ACCOUNT_KEY
nat_machine_type = "n1-standard-4"
opsman_image_url = "https://storage.googleapis.com/ops-manager-us/pcf-gcp-2.5.2-build.172.tar.gz"
opsman_machine_type = "n1-standard-2"
EOF
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
