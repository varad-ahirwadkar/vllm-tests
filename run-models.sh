#!/bin/bash

# Vars
HF_TOKEN=""
VLLM_IMAGE=${VLLM_IMAGE:-quay.io/vahirwad/vllm:v0.6.6-ubi}
PORT=8000
CACHE_SPACE=/root/.cache/huggingface
RESULTS=$(pwd)/results.txt

declare -a MODELS=(
[0]=facebook/opt-125m
[1]=TinyLlama/TinyLlama-1.1B-Chat-v1.0
[2]=ibm-granite/granite-3.0-2b-instruct
[3]=ibm-granite/granite-3b-code-instruct-2k
[4]=microsoft/Phi-3-mini-4k-instruct
)

# Run the container
deploy_vllm_container() {
    local model=$1
    docker run -dti --rm -v $CACHE_SPACE:$CACHE_SPACE --name test-vllm \
       --env HUGGING_FACE_HUB_TOKEN=$HF_TOKEN -p $PORT:$PORT \
       --env LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/usr/local/lib \
       --ipc=host $VLLM_IMAGE --dtype=float32 --model=$model

       docker wait test-vllm

       echo "Wait for server to start, timeout after 600 seconds"
       docker exec -it test-vllm /bin/sh -c "timeout 600 bash -c 'until curl localhost:8000/v1/models; do sleep 1; done' || exit 1"
}


validate_status() {
    local status=$1
    if [ $? -eq 0 ] && [ "$status" -eq 200 ]; then
        echo "${REQUEST_TYPE} request is successful (HTTP $status)."
    else
        echo "${REQUEST_TYPE} request is unsuccessful (HTTP $status)"
    fi
}

# Validate the requests 
# Currently validating completion requests
validate_requests() {
    local MODEL=$1
    REQUEST_TYPE="completions"
    HEADER="Content-Type: application/json"

    validate_status $(curl -s  -o response.txt -w "%{http_code}" \
        "http://localhost:${PORT}/v1/${REQUEST_TYPE}" \
         -H "${HEADER}" \
         -d '{
             "model": "'"${MODEL}"'",
             "prompt": "San Francisco is a",
             "max_tokens": 7
         }'
        ) $REQUEST_TYPE

    save_results $MODEL
}

save_results() {
    local MODEL=$1
    echo "Saving the results for ${MODEL}"
    echo "Output of curl request for ${MODEL}:" >> $RESULTS
    cat response.txt >> $RESULTS
    echo "" >> $RESULTS
}

# Clean up
cleanup() {
    echo "Stoping the container..."
    docker stop test-vllm
    docker wait test-vllm
    echo "Cleaning up the workspace..."
    rm -rf $CACHE_SPACE
    rm -rf response.txt
}

main() {
    echo "Creating a output file: ${RESULTS}"
    echo "" > $RESULTS

    for model in ${MODELS[@]}; do
        echo ""
        echo "Deploying $model"
        deploy_vllm_container ${model}
        echo ""
        echo "Validating $model"
        validate_requests $model
        echo ""
        echo "Cleaning $model"
        cleanup
    done
}

main
