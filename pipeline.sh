#!/bin/bash
# This script is useful to manage Azure DevOps pipelines
# Usage: pipeline.sh <command> 
# Commands:
#   - get <project> <pipeline-id> [optional: <output-dir>]: Get a pipeline from a given project
#   - create <project> <input-json> : Create a pipeline from a given project
#   - update <project> <input-json> : Update a pipeline from a given project
#   - export-all <project> <output-dir> [optional: <bkp>] : Export all pipelines from a given project
#   - delete <project> <pipeline-id> : Delete a pipeline from a given project
#   - list <project> [optional: <pipeline-id>] : List all pipelines from a given project or get pipeline details if pipeline id is provided"
#   - help : Show this help

# Prerequisites: jq, az cli, openssl, base64, bc, curl, tar

# Get the command
command=$1

help='# Usage: pipeline.sh <command>
# Commands:
#   - get <project> <pipeline-id> [optional: <output-dir>] : Get a pipeline from a given project
#   - create <project> <input-json> : Create a pipeline from a given project
#   - update <project> <input-json> : Update a pipeline from a given project
#   - export-all <project> <output-dir> [optional: <bkp>] : Export all pipelines from a given project, if bkp is provided, it will create a backup tar of the pipelines
#   - delete <project> <pipeline-id> : Delete a pipeline from a given project
#   - list <project> [optional: <pipeline-id>] : List all pipelines from a given project or if pipeline id is provided gets pipeline details 
#   - settings : Set Azure DevOps organization and username and password
#   - help : Show this help
'

if [[ -z $command || $command == "help" ]] ; then
    echo "Command is required!"
    echo "$help"
    exit 1
fi

par=$@
npar=$#
settings_file=".az-pipeline.conf"

# Check number of parameters
function check(){
    if [[ $command == "get" ]]; then
        if [[ $npar -lt 3 ]]; then
            echo "Project and pipeline id are required"
            echo "# Usage: pipeline.sh get <project> <pipeline-id> [optional: <output-dir>]"
            exit 1
        fi
    elif [[ $command == "create" ]]; then
        if [[ $npar -lt 3 ]]; then
            echo "Project, input json and mode are required"
            echo "# Usage: pipeline.sh create <project> <input-json>"
            exit 1
        fi
    elif [[ $command == "update" ]]; then
        if [[ $npar -lt 3 ]]; then
            echo "Project, input json and mode are required"
            echo "# Usage: pipeline.sh update <project> <input-json>"
            exit 1
        fi
    elif [[ $command == "export-all" ]]; then
        if [[ $npar -lt 3 ]]; then
            echo "Project and output dir are required"
            echo "# Usage: pipeline.sh export-all <project> <output-dir>"
            exit 1
        fi
    elif [[ $command == "delete" ]]; then
        if [[ $npar -lt 3 ]]; then
            echo "Project and pipeline id are required"
            echo "# Usage: pipeline.sh delete <project> <pipeline-id>"
            exit 1
        fi
    elif [[ $command == "list" ]]; then
        if [[ $npar -lt 2 ]]; then
            echo "Project is required"
            echo "# Usage: pipeline.sh list <project> [optional: <pipeline-id>]"
            exit 1
        fi
    fi
}

# Azure DevOps login
function login(){
    # if [[ ! -e ~/"$settings_file" || $(grep "username" ~/"$settings_file") == "" || $(grep "password" ~/"$settings_file") == "" ]] ; then
    #     az login &> /dev/null
    # else
    #     local username=$(cat ~/"$settings_file" | grep "username" | sed 's/username=//')
    #     local password=$(cat ~/"$settings_file" | grep "password" | sed 's/password=//' | openssl enc -aes-256-cbc -md sha512 -a -d -pbkdf2 -iter 100000 -salt -pass pass:'FH=32feghrI%ie£"h32t38')
    #     echo $username
    #     echo $password 
    #     az login --username $username --password $password 
    # fi
    az login &> /dev/null
    local token=$(az account get-access-token --query accessToken -o tsv)
    b64=$(printf "%s"":$token" | base64 -w 0)
}

function show_progress {
    bar_size=40
    bar_char_done="#"
    bar_char_todo="-"
    bar_percentage_scale=2

    current="$1"
    total="$2"

    # calculate the progress in percentage 
    percent=$(bc <<< "scale=$bar_percentage_scale; 100 * $current / $total" )
    # The number of done and todo characters
    done=$(bc <<< "scale=0; $bar_size * $percent / 100" )
    todo=$(bc <<< "scale=0; $bar_size - $done" )

    # build the done and todo sub-bars
    done_sub_bar=$(printf "%${done}s" | tr " " "${bar_char_done}")
    todo_sub_bar=$(printf "%${todo}s" | tr " " "${bar_char_todo}")

    # output the bar
    echo -ne " Total Progress : [${done_sub_bar}${todo_sub_bar}] ${percent}%"

    if [[ $total == $current ]] ; then
        echo -e "\nDONE"
    fi
}


# Get pipeline
function get(){
    echo "***** Parameters *****"
    echo "Command: $command"
    local project=$(echo $par | cut -f 2 -d " ")
    echo "Project: $project"
    if [[ $command == "get" ]]; then
        local pipeline_id=$(echo $par | cut -f 3 -d " ")
        echo "PipelineID: $pipeline_id"
        local outputDir=$(echo $par | cut -f 4 -d " ")
        echo "Output Directory: $outputDir"
    else
        local outputDir=$(echo $par | cut -f 3 -d " ")
        echo "Output Directory: $outputDir"
        if [[ $(echo $par | cut -f 4 -d " ") == "bkp" ]]; then
            local bkp=true            
        else
            local bkp=false
        fi
        echo "Backup: $bkp"
    fi
    echo "**********************"

    if [[ -z $outputDir ]]; then
        outputDir="."
    else
        mkdir -p $outputDir
    fi
    echo "Logging in to Azure DevOps..."
    login
    local http_code=0
    if [[ $command == "get" ]];then
        # Get pipeline from project
        echo "Getting pipeline $pipeline_id from project $project..."
        while [[ $http_code != 200 ]] ; do
            local p=$(curl -s --max-time 5 --location https://vsrm.dev.azure.com/$org/$project/_apis/release/definitions/$pipeline_id?api-version=7.0 \
            --header "Authorization: Basic $b64" -w " %{http_code}")
            local http_code=$(echo $p | awk '{print $NF}')
            local p=$(echo $p | awk '{$(NF--)=""; print}')
        done
        local name=$(echo $p | jq .name | sed -E 's;";;g' | sed -E 's;\/;_;g' | sed -E 's; ;_;g')
        echo $p | jq . > $outputDir/$pipeline_id-$name.json
        echo "Pipeline $pipeline_id from project $project saved in $outputDir/$pipeline_id-$name.json"
    else    
    # Get all pipelines from project
        echo "Getting all pipelines from project $project..."
        while [[ $http_code != 200 ]] ; do
            local res=$(curl -s --max-time 5 --location "https://vsrm.dev.azure.com/$org/$project/_apis/release/definitions?api-version=7.0" \
            --header "Authorization: Basic $b64" -w " %{http_code}")
            local http_code=$(echo $res | awk '{print $NF}')
            local res=$(echo $res | awk '{$(NF--)=""; print}')
        done
        local http_code=0
        npipelines=$(echo $res | jq .count)
        local i=0
        echo $res | for id in $(jq .value[].id )
            do 
                echo -ne "\rDownloading pipeline $id..."
                show_progress $i $npipelines
                i=$((i+1))
                while [[ $http_code != 200 ]] ; do
                    local p=$(curl -s --max-time 3 --location "https://vsrm.dev.azure.com/$org/$project/_apis/release/definitions/$id?api-version=7.0" \
                    --header "Authorization: Basic $b64" -w " %{http_code}")
                    local http_code=$(echo $p | awk '{print $NF}')
                    local p=$(echo $p | awk '{$(NF--)=""; print}')
                done 
                local name=$(echo $p | jq .name | sed -E 's;";;g' | sed -E 's;\/;_;g' | sed -E 's; ;_;g')
                echo $p | jq . > $outputDir/$id-$name.json 
                local http_code=0
            done
        echo "All pipelines from project $project saved in $outputDir"
        if $bkp; then
            echo "Backing up pipelines..."
            local date=$(date +%Y%m%d%H%M%S)
            local bkpDir=$outputDir-$date
            mkdir -p $bkpDir
            mv $outputDir/*.json $bkpDir
            tar -cf $bkpDir.tar $bkpDir
            rm -rf $bkpDir $outputDir
            echo "Pipelines backed up in $bkpDir.tar"
        fi
    fi
}

# Create/Update pipeline
function send(){
    echo "***** Parameters *****"
    echo "Command: $command"
    local project=$(echo $par | cut -f 2 -d " ")
    echo "Project: $project"
    local input_file=$(echo $par | cut -f 3 -d " ")
    echo "Input file: $input_file"
    echo "**********************"

    if [ -e "$input_file" ]; then
        echo "$input_file does exist."
        else
        echo "$input_file does not exist."
        exit 1
    fi
    echo "Logging in to Azure DevOps..."
    login

    #Get pipeline id from file
    id=$(jq .id $input_file)

    if [[ $command == "update" ]]; then
        echo "Updating pipeline $id"
        res=$(curl -s --location --request PUT https://vsrm.dev.azure.com/$org/$project/_apis/release/definitions/$id?api-version=7.0 \
         --header "Authorization: Basic $b64" --header "Content-Type: application/json" --data @$input_file -w " %{http_code}")
        local http_code=$(echo $res | awk '{print $NF}')
        if [[ $http_code == 200 ]]; then
            echo "Pipeline $id updated"
        else
            echo "Error updating pipeline $id"
            echo $res
        fi
    elif [[ $command == "create" ]]; then
        echo "Creating pipeline $id"
        res=$(curl -s --location --request POST https://vsrm.dev.azure.com/$org/$project/_apis/release/definitions/$id?api-version=7.0 \
         --header "Authorization: Basic $b64" --header "Content-Type: application/json" --data @$input_file -w " %{http_code}")
        local http_code=$(echo $res | awk '{print $NF}')
        if [[ $http_code == 200 ]]; then
            echo "Pipeline $id created"
        else
            echo "Error creating pipeline $id"
            echo $res
        fi
    fi
    
}

# Delete pipeline
function delete(){
    echo "***** Parameters *****"
    echo "Command: $command"
    local project=$(echo $par | cut -f 2 -d " ")
    echo "Project: $project"
    local pipeline_id=$(echo $par | cut -f 3 -d " ")
    echo "PipelineID: $pipeline_id"
    echo "**********************"

    echo "Logging in to Azure DevOps..."
    login
    local http_code=0
    while [[ $http_code != "200" ]] ; do
        local res=$(curl -s --max-time 5 --location "https://vsrm.dev.azure.com/$org/$project/_apis/release/definitions?api-version=7.0" \
        --header "Authorization: Basic $b64" -w " %{http_code}")
        local http_code=$(echo $res | awk '{print $NF}')
        local res=$(echo $res | awk '{$(NF--)=""; print}')
    done
    local res=$(echo $res | jq -r '.value[] | select(.id == '$pipeline_id') | "\(.id)-\(.name)"')
    echo "Are you sure you want to delete pipeline $res? (y/n)"
    read -r answer
    if [[ $answer == "y" || $answer == "Y" || $answer == "yes" ]]; then
        res=$(curl -s --location --request DELETE https://vsrm.dev.azure.com/$org/$project/_apis/release/definitions/$pipeline_id?api-version=7.0 \
         --header "Authorization: Basic $b64" --header "Content-Type: application/json" --data @$input_file -w " %{http_code}")
        local http_code=$(echo $res | awk '{print $NF}')
        if [[ $http_code == 204 ]]; then
            echo "Pipeline $pipeline_id deleted successfully"
        else
            echo "Error deleting pipeline $pipeline_id"
            echo $res
        fi
    else
        echo "Operation cancelled!"
        exit 1
    fi    
}

# List pipelines
function list(){
    echo "***** Parameters *****"
    echo "Command: $command"
    local project=$(echo $par | cut -f 2 -d " ")
    echo "Project: $project"
    local pipeline_id=$(echo $par | cut -f 3 -d " ")
    echo "PipelineID: $pipeline_id"
    echo "**********************"

    echo "Logging in to Azure DevOps..."
    login
    local http_code=0

    # Get pipelines from project
    echo "Getting pipelines from project $project..."
    while [[ $http_code != "200" ]] ; do
        local res=$(curl -s --max-time 5 --location "https://vsrm.dev.azure.com/$org/$project/_apis/release/definitions?api-version=7.0" \
        --header "Authorization: Basic $b64" -w " %{http_code}")
        local http_code=$(echo $res | awk '{print $NF}')
        local res=$(echo $res | awk '{$(NF--)=""; print}')
    done

    if [[ -z $pipeline_id ]]; then
        echo $res | jq -r '.value[] | "\(.id)-\(.name)"'
    else
        echo $res | jq -r '.value[] | select(.id == '$pipeline_id') | "\(.id)-\(.name)"'
    fi    
}

function settings(){    
    local option=-1

    while [[ $option != "4" ]]; do
        echo "***** Settings *****"
        echo "Choose:"
        echo "1) Set Azure DevOps organization"
        echo "2) Set Azure DevOps username"
        echo "3) Set Azure DevOps password"
        # echo "4) Create Service Principal"
        echo "4) Exit"
        echo "*********************"
        read -p "Choose an option: " option

        if [[ $option == "1" ]]; then
            read -p "Enter Azure DevOps organization: " org
            grep -q org ~/$settings_file
            if [[ $? == 0 ]]; then
                sed -i "s;org=.*;org=$org;" ~/$settings_file
            else
                echo "org=$org" >> ~/$settings_file
            fi
        elif [[ $option == "2" ]]; then
            read -p "Enter Azure DevOps username: " username
            grep -q username ~/$settings_file
            if [[ $? == 0 ]]; then
                sed -i "s;username=.*;username=$username;" ~/$settings_file
            else
                echo "username=$username" >> ~/$settings_file
            fi
        elif [[ $option == "3" ]]; then
            read -sp "Enter Azure DevOps password: " password
            local pwd=$(echo $password | openssl enc -aes-256-cbc -md sha512 -a -pbkdf2 -iter 100000 -salt -pass pass:'FH=32feghrI%ie£"h32t38')
            grep -q password ~/$settings_file
            if [[ $? == 0 ]]; then
                sed -i "s;password=.*;password=$pwd;" ~/$settings_file
            else
                echo "password=$pwd" >> ~/$settings_file
            fi
            echo ""
        # elif [[ $option == "4" ]]; then
        #     az login &> /dev/null
        #     servicePrincipalName="Pipeline-manager"
        #     subscriptionID=$(az account show --query id -o tsv)
        #     echo "Creating service principal $servicePrincipalName..."
        #     echo "Using subscription ID $subscriptionID"
        #     local res=$(az ad sp create-for-rbac --name $servicePrincipalName --role contributor --scopes /subscriptions/$subscriptionID )
        #     echo $res
        elif [[ $option == "4" ]]; then
            exit 0
        else
            echo "Invalid option"
        fi
    done
}

if [ ! -e ~/"$settings_file" ] ; then
    touch ~/"$settings_file"
    chmod 600 ~/"$settings_file"
    echo "This is the first time you run this script. Please enter your Azure DevOps settings."
    echo "You can change them later by running the script with the settings command."
    echo "You have to set at least the organization in order to use the script."
    settings
fi

org=$(grep org ~/$settings_file | cut -f 2 -d "=")
check

if [[ $command == "get" || $command == "export-all" ]]; then
    get 
elif [[ $command == "create" || $command == "update" ]]; then
    send 
elif [[ $command == "delete" ]]; then
    delete 
elif [[ $command == "list" ]]; then
    list 
elif [[ $command == "settings" ]]; then
    settings
else
    echo "Command not found!"
    echo "$help"
    exit 1
fi









