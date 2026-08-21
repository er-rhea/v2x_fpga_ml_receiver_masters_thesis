set_global_assignment -entity "mac_24bit_ip" -library "lib_mac_24bit_ip" -name IP_TOOL_NAME "altera_mult_add"
set_global_assignment -entity "mac_24bit_ip" -library "lib_mac_24bit_ip" -name IP_TOOL_VERSION "24.1"
set_global_assignment -entity "mac_24bit_ip" -library "lib_mac_24bit_ip" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_mac_24bit_ip" -name SPD_FILE [file join $::quartus(sip_path) "mac_24bit_ip.spd"]

set_global_assignment -library "lib_mac_24bit_ip" -name MISC_FILE [file join $::quartus(sip_path) "mac_24bit_ip_sim/mac_24bit_ip.v"]
