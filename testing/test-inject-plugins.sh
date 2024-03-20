BASENAME="api-spec-1"
FILENAME="../apis/api-spec-1.yaml"

deck file openapi2kong -s $FILENAME -o ./$BASENAME.yaml

# Get the service name
export SERVICE_NAME=$(yq eval '.services[0].name' ./$BASENAME.yaml)

if [ -f "../plugins/$BASENAME.yaml/service.yaml" ];
then
  echo "-> We have a SERVICE plugins file for $BASENAME"
  echo "--> Inserting service name '$SERVICE_NAME' onto each service.yaml plugin"
  yq eval -i '.plugins.[].service |= strenv(SERVICE_NAME)' ../plugins/$BASENAME.yaml/service.yaml

  # yq '
  #   .kong.plugins += load("../plugins/api-spec-1.yaml/plugins.yaml").service
  # ' $BASENAME.yaml
fi

echo ''

if [ -f "../plugins/$BASENAME.yaml/routes.yaml" ];
then
  echo "-> We have a ROUTES plugins file for $BASENAME"

  PLUGINS=$(yq e -o=j -I=0 '.plugins[]' ../plugins/$BASENAME.yaml/routes.yaml)

  export i=0

  while IFS=\= read -r PLUGIN; do
    export OPERATION_ID_REF=$(echo "$PLUGIN" | yq e '.operationId | sub("(-|\.|_| )", "-") | downcase' -)
    export ROUTE_NAME="${SERVICE_NAME}_${OPERATION_ID_REF}"
    
    echo "--> Parsed route name as ${ROUTE_NAME} - attaching back to plugin"
    yq eval -i '.plugins[env(i)].route = strenv(ROUTE_NAME)' ../plugins/api-spec-1.yaml/routes.yaml
    yq eval -i 'del(.plugins[env(i)].operationId)' ../plugins/api-spec-1.yaml/routes.yaml
    export i=$((i+1))
  done <<EOF
$PLUGINS
EOF



  
fi
