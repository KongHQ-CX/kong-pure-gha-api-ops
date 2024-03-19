BASENAME="api-spec-1"
FILENAME="../apis/api-spec-1.yaml"

deck file openapi2kong -s $FILENAME -o ./$BASENAME.yaml

if [ -f "$BASENAME.yaml" ];
then
  echo "We have a plugins file for $BASENAME"
fi
