# azure-devops-pipeline-manager

Bash script useful for managing Azure DevOps pipelines locally.

With this script you can manage your Azure DevOps CI/CD pipelines and your task group.
You can list, export, update, create and delete them.

For the moment the only way to login is by interactive browser window.

## Installation

Just clone the repository locally and then copy [pipeline.sh](http://pipeline.sh) file to your /usr/bin directory.

## Usage

[pipeline.sh](http://pipeline.sh/) <resource> <command>

### Resources

- cd/CD
- ci/CI
- tg/TG

### Commands:

- get <project> <resource-id> [optional: <output-dir>]: Get a resource from a given project
- create <project> <input-json> : Create a resource from a given project
- update <project> <input-json> : Update a resource from a given project
- export-all <project> <output-dir> [optional: <bkp>] : Export all resources from a given project
- delete <project> <resource-id> : Delete a resource from a given project
- list <project> [optional: <resource-id>] : List all resources from a given project or get resource details if resource id is provided"
- help : Show this message

## Prerequisites

jq, az cli, openssl, base64, bc, curl, tar, tr