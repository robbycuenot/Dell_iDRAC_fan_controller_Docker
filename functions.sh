# functions.sh

# Define global functions
# This function applies Dell's default dynamic fan control profile
function apply_Dell_fan_control_profile() {
  # Use ipmitool to send the raw command to set fan control to Dell default
  ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0x30 0x01 0x01 > /dev/null
  CURRENT_FAN_CONTROL_PROFILE="Dell default dynamic fan control profile"
}

# This function applies a user-specified static fan control profile
function apply_user_fan_control_profile() {
  # Use ipmitool to send the raw command to set fan control to user-specified value
  ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0x30 0x01 0x00 > /dev/null
  ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0x30 0x02 0xff $HEXADECIMAL_FAN_SPEED > /dev/null
  CURRENT_FAN_CONTROL_PROFILE="User static fan control profile ($DECIMAL_FAN_SPEED%)"
}

# Convert first parameter given ($DECIMAL_NUMBER) to hexadecimal
# Usage : convert_decimal_value_to_hexadecimal $DECIMAL_NUMBER
# Returns : hexadecimal value of DECIMAL_NUMBER
function convert_decimal_value_to_hexadecimal() {
  local -r DECIMAL_NUMBER=$1
  local -r HEXADECIMAL_NUMBER=$(printf '0x%02x' $DECIMAL_NUMBER)
  echo $HEXADECIMAL_NUMBER
}

# Convert first parameter given ($HEXADECIMAL_NUMBER) to decimal
# Usage : convert_hexadecimal_value_to_decimal "$HEXADECIMAL_NUMBER"
# Returns : decimal value of HEXADECIMAL_NUMBER
function convert_hexadecimal_value_to_decimal() {
  local -r HEXADECIMAL_NUMBER=$1
  local -r DECIMAL_NUMBER=$(printf '%d' $HEXADECIMAL_NUMBER)
  echo $DECIMAL_NUMBER
}

################################################################################
#   Updated retrieve_temperatures function that expects four parameters
#
#   Usage:
#      retrieve_temperatures <IS_EXHAUST_PRESENT> \
#                            <IS_CPU2_PRESENT> \
#                            <IS_CPU3_PRESENT> \
#                            <IS_CPU4_PRESENT>
#
#   - Sets CPU1_TEMPERATURE, CPU2_TEMPERATURE, CPU3_TEMPERATURE, CPU4_TEMPERATURE,
#     INLET_TEMPERATURE, and EXHAUST_TEMPERATURE (if “present” is true).
#   - Expects the global variables:
#       $IDRAC_LOGIN_STRING, $CPU1_TEMPERATURE_INDEX, $CPU2_TEMPERATURE_INDEX,
#       $CPU3_TEMPERATURE_INDEX, $CPU4_TEMPERATURE_INDEX
#   - If a sensor is not “present” or not found, we set it to "-" to avoid errors.
################################################################################
function retrieve_temperatures() {
  if [ $# -ne 4 ]; then
    print_error "Illegal number of parameters.\nUsage: retrieve_temperatures <IS_EXHAUST_PRESENT> <IS_CPU2_PRESENT> <IS_CPU3_PRESENT> <IS_CPU4_PRESENT>"
    return 1
  fi

  local -r IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT=$1
  local -r IS_CPU2_TEMPERATURE_SENSOR_PRESENT=$2
  local -r IS_CPU3_TEMPERATURE_SENSOR_PRESENT=$3
  local -r IS_CPU4_TEMPERATURE_SENSOR_PRESENT=$4

  # Clear or reset these variables to avoid stale data
  INLET_TEMPERATURE=""
  EXHAUST_TEMPERATURE=""
  CPU1_TEMPERATURE=""
  CPU2_TEMPERATURE=""
  CPU3_TEMPERATURE=""
  CPU4_TEMPERATURE=""

  # Grab all temperature sensor data from iDRAC/IPMI
  local -r DATA=$(ipmitool -I "$IDRAC_LOGIN_STRING" sdr type temperature | grep degrees)

  # On Dell servers, CPU-related sensors often have "3." in their descriptor lines
  # Then we filter out the numeric values only.
  # Example: "Temp (CPU1) ... 30 degrees" -> we want "30".
  # If your server differs, you may need to adjust the grep or parsing logic.
  local -r CPU_DATA=$(echo "$DATA" | grep "3\." | grep -Po '\d{2}')

  # CPU1 is always retrieved if found
  CPU1_TEMPERATURE=$(echo "$CPU_DATA" | awk "{print \$$CPU1_TEMPERATURE_INDEX;}")

  # CPU2 if $IS_CPU2_TEMPERATURE_SENSOR_PRESENT is true
  if $IS_CPU2_TEMPERATURE_SENSOR_PRESENT; then
    CPU2_TEMPERATURE=$(echo "$CPU_DATA" | awk "{print \$$CPU2_TEMPERATURE_INDEX;}")
    # If empty, set a dash to avoid 'unary operator expected'
    [ -z "$CPU2_TEMPERATURE" ] && CPU2_TEMPERATURE="-"
  else
    CPU2_TEMPERATURE="-"
  fi

  # CPU3 if $IS_CPU3_TEMPERATURE_SENSOR_PRESENT is true
  if $IS_CPU3_TEMPERATURE_SENSOR_PRESENT; then
    CPU3_TEMPERATURE=$(echo "$CPU_DATA" | awk "{print \$$CPU3_TEMPERATURE_INDEX;}")
    [ -z "$CPU3_TEMPERATURE" ] && CPU3_TEMPERATURE="-"
  else
    CPU3_TEMPERATURE="-"
  fi

  # CPU4 if $IS_CPU4_TEMPERATURE_SENSOR_PRESENT is true
  if $IS_CPU4_TEMPERATURE_SENSOR_PRESENT; then
    CPU4_TEMPERATURE=$(echo "$CPU_DATA" | awk "{print \$$CPU4_TEMPERATURE_INDEX;}")
    [ -z "$CPU4_TEMPERATURE" ] && CPU4_TEMPERATURE="-"
  else
    CPU4_TEMPERATURE="-"
  fi

  # Parse inlet temperature
  # (some servers label it “Inlet Temp” or “Ambient Temp,” adapt if necessary)
  INLET_TEMPERATURE=$(echo "$DATA" | grep -i Inlet | grep -Po '\d{2}' | tail -1)
  [ -z "$INLET_TEMPERATURE" ] && INLET_TEMPERATURE="-"

  # If exhaust sensor present, parse it
  if $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT; then
    EXHAUST_TEMPERATURE=$(echo "$DATA" | grep -i Exhaust | grep -Po '\d{2}' | tail -1)
    [ -z "$EXHAUST_TEMPERATURE" ] && EXHAUST_TEMPERATURE="-"
  else
    EXHAUST_TEMPERATURE="-"
  fi
}

# /!\ Use this function only for Gen 13 and older generation servers /!\
function enable_third_party_PCIe_card_Dell_default_cooling_response() {
  # We could check the current cooling response before applying but it's not very useful so let's skip the test and apply directly
  ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0xce 0x00 0x16 0x05 0x00 0x00 0x00 0x05 0x00 0x00 0x00 0x00 > /dev/null
}

# /!\ Use this function only for Gen 13 and older generation servers /!\
function disable_third_party_PCIe_card_Dell_default_cooling_response() {
  # We could check the current cooling response before applying but it's not very useful so let's skip the test and apply directly
  ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0xce 0x00 0x16 0x05 0x00 0x00 0x00 0x05 0x00 0x01 0x00 0x00 > /dev/null
}

# Returns :
# - 0 if third-party PCIe card Dell default cooling response is currently DISABLED
# - 1 if third-party PCIe card Dell default cooling response is currently ENABLED
# - 2 if the current status returned by ipmitool command output is unexpected
# function is_third_party_PCIe_card_Dell_default_cooling_response_disabled() {
#   THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE=$(ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0xce 0x01 0x16 0x05 0x00 0x00 0x00)

#   if [ "$THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE" == "16 05 00 00 00 05 00 01 00 00" ]; then
#     return 0
#   elif [ "$THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE" == "16 05 00 00 00 05 00 00 00 00" ]; then
#     return 1
#   else
#     print_error "Unexpected output: $THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE"
#     return 2
#   fi
# }

# Prepare traps in case of container exit
function graceful_exit() {
  apply_Dell_fan_control_profile

  # Reset third-party PCIe card cooling response to Dell default depending on the user's choice at startup
  if ! $KEEP_THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE_STATE_ON_EXIT; then
    enable_third_party_PCIe_card_Dell_default_cooling_response
  fi

  print_warning_and_exit "Container stopped, Dell default dynamic fan control profile applied for safety"
}

# Helps debugging when people are posting their output
function get_Dell_server_model() {
  local -r IPMI_FRU_content=$(ipmitool -I $IDRAC_LOGIN_STRING fru 2>/dev/null) # FRU stands for "Field Replaceable Unit"

  SERVER_MANUFACTURER=$(echo "$IPMI_FRU_content" | grep "Product Manufacturer" | awk -F ': ' '{print $2}')
  SERVER_MODEL=$(echo "$IPMI_FRU_content" | grep "Product Name" | awk -F ': ' '{print $2}')

  # Check if SERVER_MANUFACTURER is empty, if yes, assign value based on "Board Mfg"
  if [ -z "$SERVER_MANUFACTURER" ]; then
    SERVER_MANUFACTURER=$(echo "$IPMI_FRU_content" | tr -s ' ' | grep "Board Mfg :" | awk -F ': ' '{print $2}')
  fi

  # Check if SERVER_MODEL is empty, if yes, assign value based on "Board Product"
  if [ -z "$SERVER_MODEL" ]; then
    SERVER_MODEL=$(echo "$IPMI_FRU_content" | tr -s ' ' | grep "Board Product :" | awk -F ': ' '{print $2}')
  fi
}

# Define functions to check if CPU 1 and CPU 2 temperatures are above the threshold
function CPU1_OVERHEATING() { [ "$CPU1_TEMPERATURE" -gt "$CPU_TEMPERATURE_THRESHOLD" ] 2>/dev/null; }
function CPU2_OVERHEATING() { [ "$CPU2_TEMPERATURE" -gt "$CPU_TEMPERATURE_THRESHOLD" ] 2>/dev/null; }

function print_error() {
  local -r ERROR_MESSAGE="$1"
  printf "/!\\ Error /!\\ %s." "$ERROR_MESSAGE" >&2
}

function print_error_and_exit() {
  local -r ERROR_MESSAGE="$1"
  print_error "$ERROR_MESSAGE"
  printf " Exiting.\n" >&2
  exit 1
}

function print_warning() {
  local -r WARNING_MESSAGE="$1"
  printf "/!\\ Warning /!\\ %s." "$WARNING_MESSAGE"
}

function print_warning_and_exit() {
  local -r WARNING_MESSAGE="$1"
  print_warning "$WARNING_MESSAGE"
  printf " Exiting.\n"
  exit 0
}
