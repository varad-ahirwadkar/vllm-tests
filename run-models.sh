#!/bin/bash

# Global variables
VLLM_CONTAINER_PORT=8000
MAX_MODEL_LEN=2048
CACHE_SPACE=/root/.cache/huggingface
RESULTS=$(pwd)/results.txt
IS_REQUEST_FAILED=false
VLLM_REGISTRY=na.artifactory.swg-devops.com/sys-linux-power-team-ftp3distro-docker-images-docker-local/vllm

# Please export the creds USERNAME and ARTIFACTORY_TOKEN before running the script 
# Login to the registry
echo $ARTIFACTORY_TOKEN | docker $VLLM_REGISTRY --username=$USERNAME --password-stdin

# Models List
declare -a MODELS=(
[0]=facebook/opt-125m
[1]=TinyLlama/TinyLlama-1.1B-Chat-v1.0
[2]=ibm-granite/granite-3.0-2b-instruct
[3]=ibm-granite/granite-3b-code-instruct-2k
[4]=microsoft/Phi-3-mini-4k-instruct
[5]=mistralai/Mistral-7B-v0.3
[6]=ibm-granite/granite-3.1-8b-instruct
[7]=meta-llama/Llama-3.1-8B
[8]=meta-llama/Llama-3.1-8B-Instruct
)

# Run the container
deploy_vllm_container() {
    sleep 5s
    docker run -dti --rm -v $CACHE_SPACE:$CACHE_SPACE --name test-vllm \
       --env HUGGING_FACE_HUB_TOKEN=$HF_TOKEN -p $VLLM_CONTAINER_PORT:$VLLM_CONTAINER_PORT \
       --ipc=host $VLLM_IMAGE --model=$MODEL --max-model-len $MAX_MODEL_LEN

       echo "Wait for server to start, timeout after 20 minutes"
       docker exec -i test-vllm /bin/sh -c "timeout 20m bash -c 'until curl localhost:8000/v1/models; do sleep 1; done' || exit 1"
}

validate_status() {
    local status=$1
    local request_type=$2
    if [ $? -eq 0 ] && [ "$status" -eq 200 ]; then
        echo "${request_type} request is successful (HTTP $status)."
        save_results $request_type
    else
        echo "${request_type} request is unsuccessful (HTTP $status)"
        IS_REQUEST_FAILED=true
    fi
}

# Validate the requests
# Currently validating completion requests
validate_requests() {
    local request_type="completions"
	local request_header="Content-Type: application/json"
    
    validate_status $(curl -s  -o response.txt -w "%{http_code}" \
        "http://localhost:${PORT}/v1/${request_type}" \
         -H "${request_header}" \
         -d '{
             "model": "'"${MODEL}"'",
             "prompt": "San Francisco is a",
             "max_tokens": 7
         }'
        ) $request_type
}

save_results() {
    echo "Saving the results for ${MODEL}"
    echo "Output of ${request_type} request:" >> $RESULTS
    cat response.txt >> $RESULTS
    echo "" >> $RESULTS
}

# Clean up
cleanup() {
    echo "Stoping the container..."
    docker stop test-vllm
    docker wait test-vllm

    echo "Cleaning up the cache and workspace..."
    rm -rf $CACHE_SPACE
    rm -rf response.txt
}

main() {
    echo "Creating a output file: ${RESULTS}"
    echo "" > $RESULTS

    for MODEL in ${MODELS[@]}; do
        echo "Deploying $MODEL"
        deploy_vllm_container
        echo ""
        echo "Validating the $MODEL"
        validate_requests
        echo ""
        echo "Cleaning $MODEL"
        cleanup
    done
}

main
