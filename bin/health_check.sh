#!/usr/bin/env sh

# Wait for the server to be up
# Try up to 10 times to get HTTP 200
target="${WAIT_HOSTS:-move-app:9292}"
target="${target%%,*}"

for i in {1..9}; do
  status=$(curl -s -o /dev/null -w '%{http_code}' "http://${target}/up")
  if [[ "$status" == "200" ]]; then
    echo "Server is up!"
    break
  fi
  echo "Attempt $i: Server not ready (HTTP $status). Retrying..."
  sleep 2
done

if [[ "$status" != "200" ]]; then
  echo "Server did not become ready after 10 attempts. Exiting..."
  exit 1
fi

exit 0
