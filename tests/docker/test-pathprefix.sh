#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-stac-browser:test}"
BUILD_ARG_IMAGE="${IMAGE}-buildarg"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

CONTAINERS=(sb-test-root sb-test-prefix-19081 sb-test-prefix-19082 sb-test-prefix-19083 sb-test-prefix-19084 sb-test-prefix-19085)
trap 'for c in "${CONTAINERS[@]}"; do docker rm -f "$c" >/dev/null 2>&1 || true; done' EXIT

docker build -t "$IMAGE" .
docker build -t "$BUILD_ARG_IMAGE" --build-arg pathPrefix="/build.arg/" .

assert_status() {
  local url="$1"
  local expected="$2"
  local actual
  actual=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $url expected HTTP $expected, got $actual" >&2
    exit 1
  fi
}

assert_header() {
  local url="$1"
  local header="$2"
  local expected="$3"
  local actual
  actual=$(curl -sI "$url" | tr -d '\r' | awk -v h="$header" 'tolower($1) == tolower(h) ":" { print $2; exit }')
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $url expected $header: $expected, got $actual" >&2
    exit 1
  fi
}

cleanup() {
  docker rm -f "$1" >/dev/null 2>&1 || true
}

test_root() {
  local name="sb-test-root"
  cleanup "$name"
  docker run -d --name "$name" -p 19080:8080 "$IMAGE" >/dev/null
  sleep 2

  assert_status "http://localhost:19080/" 200

  if docker exec "$name" grep -q 'return 301' /etc/nginx/conf.d/default.conf; then
    echo "FAIL: root deployment should not include bare-prefix redirect" >&2
    exit 1
  fi

  cleanup "$name"
  echo "OK root deployment"
}

test_prefix() {
  local env_prefix="$1"
  local canonical="$2"
  local bare="${canonical%/}"
  local port="$3"
  local image="${4:-$IMAGE}"
  local name="sb-test-prefix-${port}"
  local env_arg=()

  cleanup "$name"
  if [ -n "$env_prefix" ]; then
    env_arg=(-e "SB_pathPrefix=${env_prefix}")
  fi
  docker run -d --name "$name" -p "${port}:8080" "${env_arg[@]}" "$image" >/dev/null
  sleep 2

  assert_status "http://localhost:${port}${bare}" 301
  assert_header "http://localhost:${port}${bare}" "Location" "${canonical}"
  assert_status "http://localhost:${port}${canonical}" 200
  assert_status "http://localhost:${port}${canonical}runtime-config.js" 200

  if ! curl -s "http://localhost:${port}${canonical}" | grep -q "src=\"${canonical}runtime-config.js\""; then
    echo "FAIL: index.html does not reference prefixed runtime-config.js" >&2
    exit 1
  fi

  if ! curl -s "http://localhost:${port}${canonical}runtime-config.js" | grep -q "pathPrefix: '${canonical}'"; then
    echo "FAIL: runtime-config.js does not contain pathPrefix ${canonical}" >&2
    exit 1
  fi
  if docker exec "$name" grep -rqF "__SB_PATH_PREFIX__" /usr/share/nginx/html; then
    echo "FAIL: unresolved pathPrefix placeholder remains" >&2
    exit 1
  fi

  local asset
  asset=$(curl -s "http://localhost:${port}${canonical}" | grep -oE "${canonical}assets/[^\"']+" | head -1)
  if [ -z "$asset" ]; then
    echo "FAIL: could not find asset URL in index.html for ${canonical}" >&2
    exit 1
  fi
  assert_status "http://localhost:${port}${asset}" 200

  assert_status "http://localhost:${port}${canonical}collections/foo" 200

  cleanup "$name"
  echo "OK prefix ${env_prefix} -> ${canonical}"
}

test_override() {
  local name="sb-test-prefix-19084"
  local canonical="/override/"
  cleanup "$name"
  docker run -d --name "$name" -p 19084:8080 \
    -e "SB_pathPrefix=${canonical}" \
    "$BUILD_ARG_IMAGE" >/dev/null
  sleep 2

  assert_status "http://localhost:19084${canonical}" 200
  if ! curl -s "http://localhost:19084${canonical}runtime-config.js" | grep -q "pathPrefix: '${canonical}'"; then
    echo "FAIL: runtime SB_pathPrefix should override build-arg default" >&2
    exit 1
  fi

  cleanup "$name"
  echo "OK runtime override of build-arg default"
}

test_invalid() {
  local output
  output=$(docker run --rm -e "SB_pathPrefix=/bad path/" "$IMAGE" 2>&1 || true)
  if echo "$output" | grep -q "invalid characters"; then
    echo "OK invalid pathPrefix rejected"
    return
  fi
  echo "FAIL: invalid pathPrefix should be rejected" >&2
  exit 1
}

test_root
test_prefix "/browser/" "/browser/" 19081
test_prefix "/stac-browser" "/stac-browser/" 19082
test_prefix "browser" "/browser/" 19085
test_prefix "" "/build.arg/" 19083 "$BUILD_ARG_IMAGE"
test_override
test_invalid

echo "All pathPrefix tests passed"
