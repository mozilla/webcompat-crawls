#!/usr/bin/env bash
set -e

if [[ $# -lt 1 ]]; then
    echo "Usage: new-crawl-directory.sh deployment_environment crawl_name" >&2
    exit 1
fi
DEPLOYMENT_ENVIRONMENT=$1
CRAWL_NAME=$2

export CRAWL_DIRECTORY="$(date +"%Y_%m_%d")_$CRAWL_NAME"

# always run from deployment instructions path
script_path=$(dirname $0)
cd "$script_path/$DEPLOYMENT_ENVIRONMENT"

CRAWL_CONFIG_DIR="../../crawls/$DEPLOYMENT_ENVIRONMENT/$CRAWL_DIRECTORY"
mkdir -p "$CRAWL_CONFIG_DIR"
envsubst < "./crawl.tmpl.yaml" > "$CRAWL_CONFIG_DIR/crawl.yaml"

echo "* Success. New crawl config created. Run the following to use this config for subsequent commands:"
echo ""
echo "  export CRAWL_CONFIG_YAML=$CRAWL_CONFIG_DIR/crawl.yaml"
echo ""

exit 0
