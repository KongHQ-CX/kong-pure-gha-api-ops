BASENAME="api-spec-1"
FILENAME="../apis/api-spec-1.yaml"

deck file openapi2kong -s $FILENAME -o ./$BASENAME.yaml

if [ -f "../plugins/$BASENAME.yaml/service.yaml" ];
then
  echo "-> We have a SERVICE plugins file for $BASENAME"

  # yq eval '.service' ../plugins/$BASENAME.yaml/plugins.yaml

  # Get the service name
  SERVICE_NAME=$(yq eval '.services[0].name' ./$BASENAME.yaml)

  echo "--> Inserting service name '$SERVICE_NAME' onto each service.yaml plugin"
  yq eval -i '.plugins.[].service |= strenv(SERVICE_NAME)' ../plugins/api-spec-1.yaml/service.yaml

  # yq '
  #   .kong.plugins += load("../plugins/api-spec-1.yaml/plugins.yaml").service
  # ' $BASENAME.yaml
fi
