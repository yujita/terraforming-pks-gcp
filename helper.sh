#!/bin/bash

AUTH_JSON=$(cat terraform.tfstate | jq -r .modules[0].outputs.AuthJSON.value)


cat <<EOF
# Ops Manager Director

## Google Cloud Platform Config

Project ID = $(echo $AUTH_JSON | jq -r .project_id)
Default Deployment Tag = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Default Deployment Tag"].value')
AuthJSON = ${AUTH_JSON}

## Director Config
NTP Servers (comma delimited) = metadata.google.internal
Enable VM Resurrector Plugin = checked
Enable Post Deploy Scripts  = checked

## Create Availability Zones

Availability Zones = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Availability Zones"].value')

## Networks

### pks-infrastructure

Name = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Infrastructure Network Name"].value')
Service Network	= unchecked
Google Network Name = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Infrastructure Network Google Network Name "].value')
CIDR = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Infrastructure Network CIDR"].value')
Reserved IP Ranges = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Infrastructure Network Reserved IP Ranges"].value')
DNS	= $(cat terraform.tfstate | jq -r '.modules[0].outputs["Infrastructure Network DNS"].value')
Gateway	= $(cat terraform.tfstate | jq -r '.modules[0].outputs["Infrastructure Network Gateway"].value')
Availability Zones = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Availability Zones"].value')

### pks-main

Name = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Main Network Name"].value')
Service Network	= unchecked.
Google Network Name = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Main Network Google Network Name "].value')
CIDR = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Main Network CIDR"].value')
Reserved IP Ranges = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Main Network Reserved IP Ranges"].value')
DNS	= $(cat terraform.tfstate | jq -r '.modules[0].outputs["Main Network DNS"].value')
Gateway	= $(cat terraform.tfstate | jq -r '.modules[0].outputs["Main Network Gateway"].value')
Availability Zones = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Availability Zones"].value')

### pks-services

Name = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Service Network Name"].value')
Service Network	= checked
Google Network Name = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Service Network Google Network Name "].value')
CIDR = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Service Network CIDR"].value')
Reserved IP Ranges = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Services Network Reserved IP Ranges"].value')
DNS	= $(cat terraform.tfstate | jq -r '.modules[0].outputs["Services Network DNS"].value')
Gateway	= $(cat terraform.tfstate | jq -r '.modules[0].outputs["Services Network Gateway"].value')
Availability Zones = $(cat terraform.tfstate | jq -r '.modules[0].outputs["Availability Zones"].value')


EOF
