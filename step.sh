#!/bin/bash
set -ex

ARGS=()

function add_args() {
  ARGS+=("$1")
}

function exit_script() {
  local code=$?
  envman add --key AUTIFY_TEST_RUN_EXIT_CODE --value "${code}"
}
trap exit_script EXIT

# Install Autify CLI
if [ -z "${autify_cli_installer_url:-}" ]; then
  echo "Missing autify_cli_installer_url."
  exit 1
fi
export XDG_CACHE_HOME="$PWD/.cache"
export XDG_CONFIG_HOME="$PWD/.config"
export XDG_DATA_HOME="$PWD/.data"
export AUTIFY_CLI_INSTALL_USE_CACHE=1
curl -L "${autify_cli_installer_url}" | bash -xe

while IFS= read -r line; do
  export PATH="$line:$PATH"
done < "$PWD/autify/path"

# Setup autify path
AUTIFY=${autify_path:-"autify"}

# Check access token
if [ -z "${access_token:-}" ]; then
  echo "Missing access-token."
  exit 1
fi

# Setup command line arguments
if [ -n "${autify_test_url:-}" ]; then
  add_args "${autify_test_url}"
else
  echo "Missing autify-test-url."
  exit 1
fi

if [ -n "${build_id:-}" ] && [ -n "${build_path:-}" ]; then
  echo "Can't specify both build-id and build-path."
  exit_script 1
elif [ -n "${build_id}" ]; then
  add_args "--build-id=${build_id}"
elif [ -n "${build_path}" ]; then
  add_args "--build-path=${build_path}"
else
  echo "Specify either build-id or build-path."
  exit 1
fi

if [ "${wait:-"false"}" = "true" ]; then
  add_args "--wait"
fi

if [ -n "${timeout:-}" ]; then
  add_args "-t=${timeout}"
fi

export AUTIFY_CLI_USER_AGENT_SUFFIX="${AUTIFY_CLI_USER_AGENT_SUFFIX:=bitrise-step-autify-test-run}"

# Execute a command
OUTPUT=./output.log
AUTIFY_MOBILE_ACCESS_TOKEN=${access_token} $AUTIFY mobile test run "${ARGS[@]}" 2>&1 | tee $OUTPUT
exit_code=${PIPESTATUS[0]}

# Setup outputs
test_result_url=$(grep "Successfully started" "$OUTPUT" | grep -Eo 'https://[^ ]+' | head -1)
envman add --key AUTIFY_TEST_RESULT_URL --value "$test_result_url"

uploaded_build_id=$(grep "Successfully uploaded" "$OUTPUT" | grep -Eo 'ID: [^\)]+' | cut -f2 -d' ' | head -1)
envman add --key AUTIFY_BUILD_ID --value "${uploaded_build_id:-$build_id}"

# Exit
exit "$exit_code"
