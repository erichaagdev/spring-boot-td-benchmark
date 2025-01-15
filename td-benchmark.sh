#!/bin/bash

# Required environment variables
td_agent_pool_id="$TD_AGENT_POOL_ID"
td_server_api_key="$TD_SERVER_API_KEY"
td_server_url="$TD_SERVER_URL"

# Usage: validate_required_config
validate_required_config() {
  local errors=()

  if [[ -z "$td_agent_pool_id" ]]; then
    errors+=("Environment variable 'TD_AGENT_POOL_ID' not set")
  fi

  if [[ -z "$td_server_api_key" ]]; then
    errors+=("Environment variable 'TD_SERVER_API_KEY' not set")
  fi

  if [[ -z "$td_server_url" ]]; then
    errors+=("Environment variable 'TD_SERVER_URL' not set")
  fi

  if [[ "${#errors[@]}" -gt 0 ]]; then
    echo "Failed to start because:"
    for i in "${errors[@]}" ; do
      echo " - $i"
    done
    exit 1
  fi
}

# Usage: run_baseline_scenario
run_baseline_scenario() {
  local min_agent_pool_size=0
  local max_agent_pool_size=0
  local max_local_executors=0
  local max_remote_executors=0
  run_scenario baseline "$min_agent_pool_size" "$max_agent_pool_size" "$max_local_executors" "$max_remote_executors"
}

# Usage: run_td_scenario {min_agent_pool_size} {max_agent_pool_size} {max_local_executors} {max_remote_executors}
run_td_scenario() {
  local min_agent_pool_size="$1"
  local max_agent_pool_size="$2"
  local max_local_executors="$3"
  local max_remote_executors="$4"
  run_scenario td "$min_agent_pool_size" "$max_agent_pool_size" "$max_local_executors" "$max_remote_executors"
}

# Usage: run_scenario {scenario_name} {min_agent_pool_size} {max_agent_pool_size} {max_local_executors} {max_remote_executors}
run_scenario() {
  local scenario_name="$1"
  local min_agent_pool_size="$2"
  local max_agent_pool_size="$3"
  local max_local_executors="$4"
  local max_remote_executors="$5"
  scale_agent_pool "$min_agent_pool_size" "$max_agent_pool_size"
  RUN_ID="$RANDOM" \
    TD_SERVER="$td_server_url" \
    TD_MIN_AGENT_POOL_SIZE="$min_agent_pool_size" \
    TD_MAX_AGENT_POOL_SIZE="$max_agent_pool_size" \
    TD_MAX_LOCAL_EXECUTORS="$max_local_executors" \
    TD_MAX_REMOTE_EXECUTORS="$max_remote_executors" \
    gradle-profiler --benchmark \
    --scenario-file td-scenarios.conf \
    --gradle-user-home ~/.gradle \
    "$scenario_name"
}

# Usage: get_agent_pool
get_agent_pool() {
  curl -s -X GET "$td_server_url/api/test-distribution/agent-pools/$td_agent_pool_id" \
    -H "Authorization: Bearer $td_server_api_key"
}

# Usage: update_agent_pool {request_body}
update_agent_pool() {
  local request_body="$1"
  curl -s -X PUT "$td_server_url/api/test-distribution/agent-pools/$td_agent_pool_id" \
    -H "Authorization: Bearer $td_server_api_key" \
    -H "Content-Type: application/json" \
    -d "$request_body" >/dev/null
}

# Usage: get_agent_status
get_agent_status() {
  curl -s -X GET "$td_server_url/api/test-distribution/agent-pools/$td_agent_pool_id/status" \
    -H "Authorization: Bearer $td_server_api_key"
}

# Usage: scale_agent_pool {min_agent_pool_size} {max_agent_pool_size}
scale_agent_pool() {
  local min_agent_pool_size="$1"
  local max_agent_pool_size="$2"
  if [[ -z "$max_agent_pool_size" ]]; then
    max_agent_pool_size="$min_agent_pool_size"
  fi

  local agent_pool agent_pool_name
  agent_pool="$(get_agent_pool)"
  agent_pool_name="$(echo "$agent_pool" | jq -r '.name')"

  if [[ "$min_agent_pool_size" == "$max_agent_pool_size" ]]; then
    echo "Scaling '$agent_pool_name' agent pool to $min_agent_pool_size agents."
  else
    echo "Scaling '$agent_pool_name' agent pool to a minimum of $min_agent_pool_size and maximum of $max_agent_pool_size agents."
  fi

  update_agent_pool "$(echo "$agent_pool" | jq --argjson min_agent_pool_size "$min_agent_pool_size" --argjson max_agent_pool_size "$max_agent_pool_size" '.minimumSize=$min_agent_pool_size | .maximumSize=$max_agent_pool_size | del(.id)')"

  local connected_agents
  connected_agents="$(get_agent_status | jq -r '.connectedAgents')"
  while [[ "$connected_agents" -lt "$min_agent_pool_size" || "$connected_agents" -gt "$max_agent_pool_size" ]]; do
    echo "Waiting for '$agent_pool_name' agent count to stabilize. Currently connected: $connected_agents agents"
    sleep 10
    connected_agents="$(get_agent_status | jq -r '.connectedAgents')"
  done
  echo "Successfully scaled '$agent_pool_name' agent pool to $connected_agents agents."
  echo ""
}

# minA = Minimum agent pool size
# maxA = Maximum agent pool size
# maxL = Maximum local executors
# maxR = Maximum remote executors
# cpus = The number of cpus of the machine, or worker count (4 in our case)

# EXPERIMENT 1: minA == maxA == maxR && maxL == 0
run_experiment_1() {
                # minA maxA maxL maxR
  run_td_scenario   10   10    0   10
  run_td_scenario   25   25    0   25
  run_td_scenario   50   50    0   50
}

# EXPERIMENT 2: minA == maxA == maxR && maxL == 1
run_experiment_2() {
                # minA maxA maxL maxR
  run_td_scenario   10   10    1   10
  run_td_scenario   25   25    1   25
  run_td_scenario   50   50    1   50
}

# EXPERIMENT 3: minA == maxA == maxR / cpus && maxL == 0
run_experiment_3() {
                # minA maxA maxL maxR
  run_td_scenario    4    4    0    1
  run_td_scenario    8    8    0    2
  run_td_scenario   12   12    0    3
  run_td_scenario   16   16    0    4
  run_td_scenario   20   20    0    5
  run_td_scenario   24   24    0    6
}

validate_required_config

run_experiment_1
run_experiment_2
run_experiment_3
run_baseline_scenario

# End of experiments. Agent pool should already be scaled to 0 after running the baseline,
# but scale it to 0 again just in case.
scale_agent_pool 0
