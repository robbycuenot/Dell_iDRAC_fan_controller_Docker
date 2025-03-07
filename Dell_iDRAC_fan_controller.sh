#!/bin/bash

###############################################################################
#                             DEBUG SETTINGS
###############################################################################

# Uncomment this for very verbose Bash output (each command printed as it runs).
# set -x

echo "=== DEBUG: Starting Dell_iDRAC_fan_controller.sh at $(date) ==="

# Trap the signals for container exit and run graceful_exit function
trap 'graceful_exit' SIGINT SIGQUIT SIGTERM

# Make sure we see environment variables of interest
echo "=== DEBUG: Environment variables of interest ==="
echo "FAN_SPEED='$FAN_SPEED'"
echo "HIGH_FAN_SPEED='$HIGH_FAN_SPEED'"
echo "CPU_TEMPERATURE_THRESHOLD='$CPU_TEMPERATURE_THRESHOLD'"
echo "CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION='$CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION'"
echo "CHECK_INTERVAL='$CHECK_INTERVAL'"
echo "IDRAC_HOST='$IDRAC_HOST'"
echo "IDRAC_USERNAME='$IDRAC_USERNAME'"
# We won't echo password for security, but you could if you need to debug
# echo "IDRAC_PASSWORD='$IDRAC_PASSWORD'"

# If you have multiple scripts:
# Make sure we actually source the functions that define 'retrieve_temperatures' etc.
# (Adjust this path if needed!)
source functions.sh

# If your functions.sh does NOT define these functions, we define them here as stubs:
# (Remove or comment out if your functions.sh already has them.)
if ! declare -F CPU1_OVERHEATING &>/dev/null; then
  echo "=== DEBUG: Defining stub for CPU1_OVERHEATING because it wasn't found ==="
  function CPU1_OVERHEATING() {
    # Return 0 (true) if CPU1_TEMPERATURE is defined and > CPU_TEMPERATURE_THRESHOLD
    [ -n "$CPU1_TEMPERATURE" ] && [ "$CPU1_TEMPERATURE" -gt "$CPU_TEMPERATURE_THRESHOLD" ]
  }
fi

if ! declare -F CPU2_OVERHEATING &>/dev/null; then
  echo "=== DEBUG: Defining stub for CPU2_OVERHEATING because it wasn't found ==="
  function CPU2_OVERHEATING() {
    [ -n "$CPU2_TEMPERATURE" ] && [ "$CPU2_TEMPERATURE" -gt "$CPU_TEMPERATURE_THRESHOLD" ]
  }
fi

if ! declare -F CPU1_HEATING &>/dev/null; then
  echo "=== DEBUG: Defining stub for CPU1_HEATING because it wasn't found ==="
  function CPU1_HEATING() {
    [ -n "$CPU1_TEMPERATURE" ] && [ -n "$CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION" ] && \
    [ "$CPU1_TEMPERATURE" -gt "$CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION" ]
  }
fi

if ! declare -F CPU2_HEATING &>/dev/null; then
  echo "=== DEBUG: Defining stub for CPU2_HEATING because it wasn't found ==="
  function CPU2_HEATING() {
    [ -n "$CPU2_TEMPERATURE" ] && [ -n "$CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION" ] && \
    [ "$CPU2_TEMPERATURE" -gt "$CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION" ]
  }
fi

# Also check if 'retrieve_temperatures' is found (the cause of "Illegal number of parameters"?).
if ! declare -F retrieve_temperatures &>/dev/null; then
  echo "=== DEBUG: ERROR: retrieve_temperatures function not found in functions.sh! ==="
  echo "Make sure your functions.sh actually has retrieve_temperatures defined."
  exit 1
fi

###############################################################################
#                              MAIN SCRIPT
###############################################################################

# Example revised usage line in functions.sh might be:
#   retrieve_temperatures() {
#     if [ $# -ne 4 ]; then
#       echo "/!\\ Error /!\\ Illegal number of parameters."
#       echo "Usage: retrieve_temperatures IS_EXHAUST_SENSOR_PRESENT IS_CPU2_SENSOR_PRESENT IS_CPU3_SENSOR_PRESENT IS_CPU4_SENSOR_PRESENT"
#       return 1
#     fi
#     ...
#   }

# set -euo pipefail  # Sometimes optional if it breaks known workflows

# Check if FAN_SPEED variable is in hexadecimal format. If not, convert it
if [[ $FAN_SPEED == 0x* ]]; then
  readonly DECIMAL_FAN_SPEED=$(convert_hexadecimal_value_to_decimal "$FAN_SPEED")
else
  readonly DECIMAL_FAN_SPEED=$FAN_SPEED
fi

# Decide if fan speed interpolation is enabled
if [ -z "$HIGH_FAN_SPEED" ] || [ -z "$CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION" ]; then
  readonly FAN_SPEED_INTERPOLATION_ENABLED=false
  readonly HIGH_FAN_SPEED=$FAN_SPEED
  readonly CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION=$CPU_TEMPERATURE_THRESHOLD
elif [[ "$FAN_SPEED" -gt "$HIGH_FAN_SPEED" ]]; then
  echo "Error: FAN_SPEED ($FAN_SPEED) must be <= HIGH_FAN_SPEED ($HIGH_FAN_SPEED). Exiting."
  exit 1
else
  readonly FAN_SPEED_INTERPOLATION_ENABLED=true
fi

# Convert HIGH_FAN_SPEED if hex
if [[ $HIGH_FAN_SPEED == 0x* ]]; then
  readonly DECIMAL_HIGH_FAN_SPEED=$(convert_hexadecimal_value_to_decimal "$HIGH_FAN_SPEED")
else
  readonly DECIMAL_HIGH_FAN_SPEED=$HIGH_FAN_SPEED
fi

# Check local/remote iDRAC
if [[ $IDRAC_HOST == "local" ]]; then
  if [ ! -e "/dev/ipmi0" ] && [ ! -e "/dev/ipmi/0" ] && [ ! -e "/dev/ipmidev/0" ]; then
    echo "/!\ Could not open device at /dev/ipmi0 or /dev/ipmi/0 or /dev/ipmidev/0"
    exit 1
  fi
  IDRAC_LOGIN_STRING='open'
else
  echo "iDRAC/IPMI username: $IDRAC_USERNAME"
  echo "iDRAC/IPMI password: (hidden)"
  IDRAC_LOGIN_STRING="lanplus -H $IDRAC_HOST -U $IDRAC_USERNAME -P $IDRAC_PASSWORD"
fi

echo "=== DEBUG: About to detect server model via get_Dell_server_model ==="
get_Dell_server_model

if [[ ! $SERVER_MANUFACTURER == "DELL" ]]; then
  echo "/!\ Your server is not a Dell product. Exiting."
  exit 1
fi

# Gen detection
if [[ $SERVER_MODEL =~ .*[RT][[:space:]]?[0-9][4-9]0.* ]]; then
  readonly DELL_POWEREDGE_GEN_14_OR_NEWER=true
  readonly CPU1_TEMPERATURE_INDEX=2
  readonly CPU2_TEMPERATURE_INDEX=4
  readonly CPU3_TEMPERATURE_INDEX=6
  readonly CPU4_TEMPERATURE_INDEX=8
elif [[ $SERVER_MODEL =~ .*[RT][[:space:]]?[8-9][3]0.* ]]; then
  readonly DELL_POWEREDGE_GEN_14_OR_NEWER=false
  readonly CPU1_TEMPERATURE_INDEX=2
  readonly CPU2_TEMPERATURE_INDEX=4
  readonly CPU3_TEMPERATURE_INDEX=6
  readonly CPU4_TEMPERATURE_INDEX=8
else
  readonly DELL_POWEREDGE_GEN_14_OR_NEWER=false
  readonly CPU1_TEMPERATURE_INDEX=1
  readonly CPU2_TEMPERATURE_INDEX=2
  readonly CPU3_TEMPERATURE_INDEX=3
  readonly CPU4_TEMPERATURE_INDEX=4
fi

# Log main info
echo "Server model: $SERVER_MANUFACTURER $SERVER_MODEL"
echo "iDRAC/IPMI host: $IDRAC_HOST"
echo "Check interval: ${CHECK_INTERVAL}s"
echo "Fan speed interpolation enabled: $FAN_SPEED_INTERPOLATION_ENABLED"

if $FAN_SPEED_INTERPOLATION_ENABLED; then
  echo "Fan speed lower value: $DECIMAL_FAN_SPEED%"
  echo "Fan speed higher value: $DECIMAL_HIGH_FAN_SPEED%"
  echo "CPU lower temperature threshold: $CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION°C"
  echo "CPU higher temperature threshold: $CPU_TEMPERATURE_THRESHOLD°C"
  echo ""
  print_interpolated_fan_speeds \
    "$CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION" \
    "$CPU_TEMPERATURE_THRESHOLD" \
    "$DECIMAL_FAN_SPEED" \
    "$DECIMAL_HIGH_FAN_SPEED"
else
  echo "Fan speed objective: $DECIMAL_FAN_SPEED%"
  echo "CPU temperature threshold: $CPU_TEMPERATURE_THRESHOLD°C"
fi
echo ""

readonly TABLE_HEADER_PRINT_INTERVAL=10
i=$TABLE_HEADER_PRINT_INTERVAL
IS_DELL_FAN_CONTROL_PROFILE_APPLIED=true

# Initialize sensor presence flags
IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT=true
IS_CPU2_TEMPERATURE_SENSOR_PRESENT=true
IS_CPU3_TEMPERATURE_SENSOR_PRESENT=true
IS_CPU4_TEMPERATURE_SENSOR_PRESENT=true

echo "=== DEBUG: First retrieve_temperatures call (4 arguments) ==="
echo "Calling retrieve_temperatures with: $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT $IS_CPU2_TEMPERATURE_SENSOR_PRESENT $IS_CPU3_TEMPERATURE_SENSOR_PRESENT $IS_CPU4_TEMPERATURE_SENSOR_PRESENT"
retrieve_temperatures \
  "$IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT" \
  "$IS_CPU2_TEMPERATURE_SENSOR_PRESENT" \
  "$IS_CPU3_TEMPERATURE_SENSOR_PRESENT" \
  "$IS_CPU4_TEMPERATURE_SENSOR_PRESENT"

# Check if any of those temps are empty
if [ -z "$EXHAUST_TEMPERATURE" ]; then
  echo "No exhaust temperature sensor detected."
  IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT=false
fi
if [ -z "$CPU2_TEMPERATURE" ]; then
  echo "No CPU2 temperature sensor detected."
  IS_CPU2_TEMPERATURE_SENSOR_PRESENT=false
fi
if [ -z "$CPU3_TEMPERATURE" ]; then
  echo "No CPU3 temperature sensor detected."
  IS_CPU3_TEMPERATURE_SENSOR_PRESENT=false
fi
if [ -z "$CPU4_TEMPERATURE" ]; then
  echo "No CPU4 temperature sensor detected."
  IS_CPU4_TEMPERATURE_SENSOR_PRESENT=false
fi

# Output new line if any sensor was missing
if ! $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT || ! $IS_CPU2_TEMPERATURE_SENSOR_PRESENT || ! $IS_CPU3_TEMPERATURE_SENSOR_PRESENT || ! $IS_CPU4_TEMPERATURE_SENSOR_PRESENT; then
  echo ""
fi

###############################################################################
#                               MAIN LOOP
###############################################################################
while true; do
  sleep "$CHECK_INTERVAL" &
  SLEEP_PROCESS_PID=$!

  echo "=== DEBUG: retrieve_temperatures call in loop with 4 arguments ==="
  echo "  IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT=$IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT"
  echo "  IS_CPU2_TEMPERATURE_SENSOR_PRESENT=$IS_CPU2_TEMPERATURE_SENSOR_PRESENT"
  echo "  IS_CPU3_TEMPERATURE_SENSOR_PRESENT=$IS_CPU3_TEMPERATURE_SENSOR_PRESENT"
  echo "  IS_CPU4_TEMPERATURE_SENSOR_PRESENT=$IS_CPU4_TEMPERATURE_SENSOR_PRESENT"
  retrieve_temperatures \
    "$IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT" \
    "$IS_CPU2_TEMPERATURE_SENSOR_PRESENT" \
    "$IS_CPU3_TEMPERATURE_SENSOR_PRESENT" \
    "$IS_CPU4_TEMPERATURE_SENSOR_PRESENT"

  # Debugging: show the CPU temperature variables after retrieving
  echo "=== DEBUG: After retrieve_temperatures ==="
  echo "INLET_TEMPERATURE='$INLET_TEMPERATURE'"
  echo "EXHAUST_TEMPERATURE='$EXHAUST_TEMPERATURE'"
  echo "CPU1_TEMPERATURE='$CPU1_TEMPERATURE'"
  echo "CPU2_TEMPERATURE='$CPU2_TEMPERATURE'"
  echo "CPU3_TEMPERATURE='$CPU3_TEMPERATURE'"
  echo "CPU4_TEMPERATURE='$CPU4_TEMPERATURE'"

  # Initialize a variable to store the comment displayed if the fan control profile changes
  COMMENT=" -"

  # 1) Check for CPU1 overheating
  if CPU1_OVERHEATING; then
    apply_Dell_fan_control_profile
    if ! $IS_DELL_FAN_CONTROL_PROFILE_APPLIED; then
      IS_DELL_FAN_CONTROL_PROFILE_APPLIED=true
      if $IS_CPU2_TEMPERATURE_SENSOR_PRESENT && CPU2_OVERHEATING; then
        COMMENT="CPU 1 and CPU 2 temperatures are too high, Dell default dynamic fan control profile applied for safety"
      else
        COMMENT="CPU 1 temperature is too high, Dell default dynamic fan control profile applied for safety"
      fi
    fi

  # 2) If CPU2 sensor exists, check CPU2 overheating
  elif $IS_CPU2_TEMPERATURE_SENSOR_PRESENT && CPU2_OVERHEATING; then
    apply_Dell_fan_control_profile
    if ! $IS_DELL_FAN_CONTROL_PROFILE_APPLIED; then
      IS_DELL_FAN_CONTROL_PROFILE_APPLIED=true
      COMMENT="CPU 2 temperature is too high, Dell default dynamic fan control profile applied for safety"
    fi

  # 3) If not overheated, maybe “heating” for interpolation
  elif CPU1_HEATING || { $IS_CPU2_TEMPERATURE_SENSOR_PRESENT && CPU2_HEATING; }; then
    # Find highest CPU among CPU1 / CPU2
    HIGHEST_CPU_TEMPERATURE=$CPU1_TEMPERATURE
    if $IS_CPU2_TEMPERATURE_SENSOR_PRESENT; then
      # Use 'max' function from functions.sh if it exists
      HIGHEST_CPU_TEMPERATURE=$(max "$CPU1_TEMPERATURE" "$CPU2_TEMPERATURE")
    fi
    apply_user_fan_control_profile 2 \
      "$(calculate_interpolated_fan_speed \
          "$HIGHEST_CPU_TEMPERATURE" \
          "$CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION" \
          "$CPU_TEMPERATURE_THRESHOLD" \
          "$DECIMAL_FAN_SPEED" \
          "$DECIMAL_HIGH_FAN_SPEED")"

  # 4) Otherwise use the user’s static fan speed
  else
    apply_user_fan_control_profile 1 "$DECIMAL_FAN_SPEED"
    if $IS_DELL_FAN_CONTROL_PROFILE_APPLIED; then
      IS_DELL_FAN_CONTROL_PROFILE_APPLIED=false
      COMMENT="CPU temperature decreased and is now OK (<= $CPU_TEMPERATURE_THRESHOLD°C), user's fan control profile applied."
    fi
  fi

  # If Gen 13 or older, manage third-party PCIe card default cooling response
  if ! $DELL_POWEREDGE_GEN_14_OR_NEWER; then
    if $DISABLE_THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE; then
      disable_third_party_PCIe_card_Dell_default_cooling_response
      THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE_STATUS="Disabled"
    else
      enable_third_party_PCIe_card_Dell_default_cooling_response
      THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE_STATUS="Enabled"
    fi
  fi

  # Periodically print a header row
  if [ $i -eq $TABLE_HEADER_PRINT_INTERVAL ]; then
    echo "                     ------- Temperatures -------"
    echo "    Date & time      Inlet  CPU 1  CPU 2  CPU 3  CPU 4  Exhaust          Active fan speed profile          PCIe card cooling  Comment"
    i=0
  fi

  # Print the row of data
  printf "%19s  %3d°C  %3d°C  %3s°C  %3s°C  %3s°C  %5s°C  %40s  %12s  %9s\n" \
    "$(date +"%d-%m-%Y %T")" \
    "${INLET_TEMPERATURE:-0}" \
    "${CPU1_TEMPERATURE:-0}" \
    "${CPU2_TEMPERATURE:-}" \
    "${CPU3_TEMPERATURE:-}" \
    "${CPU4_TEMPERATURE:-}" \
    "${EXHAUST_TEMPERATURE:-}" \
    "$CURRENT_FAN_CONTROL_PROFILE" \
    "$THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE_STATUS" \
    "$COMMENT"

  ((i++))
  wait "$SLEEP_PROCESS_PID"
done
