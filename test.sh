export API_TAG=jack-tag
mkdir -p output/

echo "-> Generating decks from all API specs"

for API_SPEC_PATH in apis/*.yaml; do
  export API_SPEC_FILENAME=$(basename $API_SPEC_PATH)

  deck file openapi2kong \
    -s $API_SPEC_PATH \
    -o output/$API_SPEC_FILENAME \
    --select-tag $API_TAG

  echo "-> Genarated Kong config from ${API_SPEC_FILENAME}"
done


for API_SPEC_PATH in apis/*.yaml; do
  export API_SPEC_FILENAME=$(basename $API_SPEC_PATH)

  if [ -f "plugins/$API_SPEC_FILENAME/service.yaml" ];
  then
    echo "-> We have a SERVICE plugins file for $API_SPEC_FILENAME"

    cp plugins/$API_SPEC_FILENAME/service.yaml output/service-plugins.$API_SPEC_FILENAME
  
    # Get the service name
    export SERVICE_NAME=$(yq eval '.services[0].name' output/$API_SPEC_FILENAME)

    echo "--> Inserting service name '$SERVICE_NAME' onto each service.yaml plugin"
    yq eval -i '.plugins.[].service |= strenv(SERVICE_NAME)' output/service-plugins.$API_SPEC_FILENAME

    echo "--> Adding API tag to all plugins"
    yq eval -i '.plugins[].tags = [env(API_TAG)]' output/service-plugins.$API_SPEC_FILENAME
  fi

  if [ -f "plugins/$API_SPEC_FILENAME/routes.yaml" ];
  then
    echo "-> We have a ROUTES plugins file for $API_SPEC_FILENAME"

    cp plugins/$API_SPEC_FILENAME/routes.yaml output/routes-plugins.$API_SPEC_FILENAME

    PLUGINS=$(yq e -o=j -I=0 '.plugins[]' output/routes-plugins.$API_SPEC_FILENAME)

    export i=0

    while IFS=\= read -r PLUGIN; do
      export X_KONG_NAME=$(echo "$PLUGIN" | yq e '.x-kong-name' -)

      if [ ! "$X_KONG_NAME" == "null" ];
      then
        # look for the operation in the spec, and parse the route name from it
        echo "---> Finding OAS operation by x-kong-name '${X_KONG_NAME}'"
        export ROUTE_PATH=$(yq e '.paths | with_entries(select(.*.*.x-kong-name == env(X_KONG_NAME))) | keys | .[0] | sub("(-|\.|_|/|{|}| )", "-") | sub("(--)", "-") | downcase' $API_SPEC_PATH)
        export ROUTE_PATH="${ROUTE_PATH:1}"
        export ROUTE_PATH="${ROUTE_PATH::-1}"
        export X_KONG_NAME_REPLACED=$(echo "$PLUGIN" | yq e '.x-kong-name | sub("(-|\.|_| )", "-") | downcase' -)

        echo $ROUTE_PATH
        echo $X_KONG_NAME_REPLACED
      else
        # old-fashioned way
        export OPERATION_ID_REF=$(echo "$PLUGIN" | yq e '.operationId | sub("(-|\.|_| )", "-") | downcase' -)
        export ROUTE_NAME="${SERVICE_NAME}_${OPERATION_ID_REF}"

        echo "--> Parsed route name as ${ROUTE_NAME} - attaching back to plugin"

        yq eval -i '.plugins[env(i)].route = strenv(ROUTE_NAME)' output/routes-plugins.$API_SPEC_FILENAME
        yq eval -i 'del(.plugins[env(i)].operationId)' output/routes-plugins.$API_SPEC_FILENAME
        export i=$((i+1))
      fi
    done <<EOF
$PLUGINS
EOF

  echo "--> Adding API tag to all plugins"
  yq eval -i '.plugins[].tags = [env(API_TAG)]' output/routes-plugins.$API_SPEC_FILENAME
  fi
done

deck --konnect-addr="https://eu.api.konghq.com" \
               --konnect-token="$(cat ~/.passwords/konnect-pat.txt)" \
               --konnect-control-plane-name="api-ops-demo" \
               --select-tag="${API_TAG}" \
               gateway diff output
