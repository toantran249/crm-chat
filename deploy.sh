#!/bin/bash

is_reup_crm_fe="$1"
is_reup_crm_be="$2"
is_reup_chat="$3"

if [[ $is_reup_crm_fe != "" && $is_reup_crm_be != "" && $is_reup_chat != "" ]]
    then
        REGISTRY_URL="https://index.docker.io/v1/"
        USERNAME="toantran2409@gmail.com"
        PASSWORD="1jahdi@#jdskljk33A"

        docker login $REGISTRY_URL -u $USERNAME -p $PASSWORD
        if [ "$is_reup_chat" == "true" ]
            then
                docker pull toantran249/chat-org:latest
                docker compose -f docker-compose.yml up -d sidekiq
                docker compose -f docker-compose.yml up -d rails
                echo "chat be success"
        fi
        if [ "$is_reup_crm_be" == "true" ]
            then
                docker pull toantran249/crm-be-org:latest
                docker compose -f docker-compose.yml up -d crm-be
                echo "crm be success"
        fi
        if [ "$is_reup_crm_fe" == "true" ]
            then
                docker pull toantran249/crm-fe-org:latest
                docker compose -f docker-compose.yml up -d crm-fe
                echo "crm fe success"
        fi
        docker logout $REGISTRY_URL
    else
        echo "missing variables"
fi
