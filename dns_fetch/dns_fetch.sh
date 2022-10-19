#!/bin/sh

prog_name=${0##*/}
version=0.1
version_text="DNS Record Fetch Script v$version"
options="h q v V o: s: d: " # basic opts
help_text="Usage: $prog_name [-s <service>] [-d <domain>] [-o <field>] [-hqvV] [record type]...
  ${version_text}
    -s <service>   Service to use, default to all configured
    -d <domain>    Domain to retrieve, default to all available
    -o <field>     Output specific field (name, content, or type), default to json of all fields
    -h             Display this help text and exit
    -q             Quiet
    -v             Verbose mode
    -V             Display version information and exit
"

# TODO
#=======
# Add more services
# Add configuration JSON file as an option rather than just environment variables?
# Figure out output format options/design and add error checking

main() {
	set_defaults # nl/cr/tab/esc & traps
	parse_options "$@"
	shift $((OPTIND - 1))
	# If we want to use `getopts` again, this has to be set to 1.
	OPTIND=1

	# shellcheck disable=2154
	{
		$opt_h && usage
		$opt_V && version
		$opt_q && info() { :; }
		$opt_v || verbose() { :; }
	}

	# space separated list of supported service names
	supported_services="cloudflare"

	# shellcheck disable=2154
	if [ "${opt_s}" = "true" ] && ! (printf "%s" "${supported_services}" | grep -Pq "(^|\s)${val_s}(\s|$)"); then
		error 1 "Service ${val_s} not supported"
	fi

	types_filter=$(generate_type_filter "${@}")

	# Calculate filters using command line arguments
	for _service in $supported_services; do
		# shellcheck disable=2154
		if [ "${opt_s}" = "false" ] && eval "${_service}_configured" || [ "${val_s}" = "${_service}" ]; then
			# Only run if there is a prepare command present
			if command -v "${_service}_prepare" >/dev/null; then
				eval "${_service}_prepare \"\$@\""
			fi
		fi
	done
	unset _service

	# Get records for all services or just the specified service
	for _service in $supported_services; do
		# shellcheck disable=2154
		if [ "${opt_s}" = "false" ] && eval "${_service}_configured" || [ "${val_s}" = "${_service}" ]; then
			records="${records}$(eval "${_service}_records")"
		fi
	done
	unset _service

	final_query="."

	# Filter records by type if specified
	if [ -n "${types_filter}" ]; then
		final_query="${final_query} | map(select(${types_filter}))"
	fi

	# Add output formats here
	# shellcheck disable=2154
	if [ "${opt_o}" = "true" ] && ! [ "${val_o}" = "json" ]; then
		final_query="${final_query} | map(.${val_o}) | .[]"
	fi

	# Filter final records and print them if not quiet
	records=$(printf "%s" "${records}" | jq -sr "${final_query}")
	info "$records"
}

#######################################
# Generate jq filter to filter records based on DNS record type
#######################################
generate_type_filter() {
	_i=1
	for _type; do
		if [ ${_i} -ne 1 ]; then
			separator=" or "
		fi
		types_filter="${types_filter}${separator}.type == \"${_type}\""
		_i=$((_i + 1))
	done
	if [ ${_i} -eq 1 ]; then
		types_filter=""
	fi
	unset _i _type
	printf "%s" "${types_filter}"
}

#-------------------------------------------------------------------------
# EXAMPLE TEST SERVICE MODULES
#-------------------------------------------------------------------------

# If there is any sort of preparation necessary with access to the array of record types
test_prepare() { verbose "Prepare function with array of types: ${*}"; }
# Test source is always configured
test_configured() { verbose "Test source is configured"; }
# Return a hard coded record
test_records() { printf '{ "name": "text_record.test.com", "type": "TXT", "content": "IGNORE THIS RECORD" }'; }

#-------------------------------------------------------------------------
# CLOUDFLARE MODULES
#-------------------------------------------------------------------------

CLOUDFLARE_URL="https://api.cloudflare.com/client/v4"

#######################################
# Checks if the cloudflare service is configured. Either by CLOUDFLARE_TOKEN being set
# or by CLOUDFLARE_EMAIL and CLOUDFLARE_KEY being set.
#
# Returns 0 if Cloudflare is configured and 1 if Cloudflare is not configured
#
# Globals:
#   CLOUDFLARE_EMAIL
#   CLOUDFLARE_KEY
#   CLOUDFLARE_TOKEN
#######################################
cloudflare_configured() {
	if [ -n "${CLOUDFLARE_EMAIL}" ] && [ -n "${CLOUDFLARE_KEY}" ] || [ -n "${CLOUDFLARE_TOKEN}" ]; then
		return 0
	fi
	return 1
}

#######################################
# Helper function for running a Cloudflare API GET request with the necessary authentication headers
# Arguments:
#   endpoint The Cloudflare API v4 endpoint
#######################################
cloudflare_api() {
	endpoint="${1}"
	if [ -n "${CLOUDFLARE_TOKEN}" ]; then
		set -- -H "Authorization: Bearer ${CLOUDFLARE_TOKEN}" -H "Content-Type: application/json"
	elif [ -n "${CLOUDFLARE_EMAIL}" ] && [ -n "${CLOUDFLARE_KEY}" ]; then
		set -- -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" -H "X-Auth-Key: ${CLOUDFLARE_KEY}" -H "Content-Type: application/json"
	else
		error 1 "Cloudflare token or email+auth key are not provided. Please set the necessary environment variables"
	fi

	response=$(curl -X GET "${CLOUDFLARE_URL}/${endpoint}" "$@" 2>/dev/null)

	if [ "$(printf "%s" "${response}" | jq .success)" = "false" ]; then
		error 1 "Cloudflare login failed"
	fi

	printf "%s" "$response"
}

#######################################
# Get all the records from Cloudflare as a JSON array where each item is of the
# structure `{ name: string, type: string, content: string }`
#######################################
cloudflare_records() {
	raw_zones=$(cloudflare_api "zones")
	zones=$(printf "%s" "${raw_zones}" | jq ".result | map({(.name): .id}) | add")
	# shellcheck disable=2154
	if [ "${opt_d}" = "true" ] && [ "$(printf "%s" "${zones}" | jq "has(\"${val_d}\")")" = "false" ]; then
		error 1 "Cloudflare zone ${val_d} does not exist"
	fi
	for _zone in $(printf "%s" "${zones}" | jq -r "keys[]"); do
		# shellcheck disable=2154
		if [ "${opt_d}" = "false" ] || [ "${val_d}" = "${_zone}" ]; then
			zone_id=$(printf "%s" "${zones}" | jq -r ".\"${_zone}\"")
			# Get zone records using zone id
			records=$(cloudflare_api "zones/${zone_id}/dns_records/")
			printf "%s" "${records}" | jq -r ".result | map({name,type,content}) | .[]"
		fi
	done
	unset _zone
}

#-------------------------------------------------------------------------

# TODO add more services here....
# They just need to implement X_configured, X_prepare (optional), and X_records functions where X is the service name

##########################################################################

# shellcheck disable=2034,2046
set_defaults() {
	set -e # Automatically exit on failed command
	trap 'clean_exit' EXIT TERM
	trap 'clean_exit HUP' HUP
	trap 'clean_exit INT' INT
	IFS=' '
	set -- $(printf '\n \r \t \033')
	nl=$1 cr=$2 tab=$3 esc=$4
	IFS=\ $tab
	IFS=\ $nl
}

# For a given optstring, this function sets the variables
# "opt_<optchar>" to true/false and val_<optchar> to its parameter.
parse_options() {
	for _opt in $options; do
		# The POSIX spec does not say anything about spaces in the
		# optstring, so lets get rid of them.
		_optstring=$_optstring$_opt
		eval "opt_${_opt%:}=false"
	done

	while getopts ":$_optstring" _opt; do
		case $_opt in
		:) usage "option '$OPTARG' requires a value" ;;
		\?) usage "unrecognized option '$OPTARG'" ;;
		*)
			eval "opt_$_opt=true"
			[ -n "$OPTARG" ] &&
				eval "val_$_opt=\$OPTARG"
			;;
		esac
	done
	unset _opt _optstring OPTARG
}

info() { printf '%b\n' "$*"; }
stderr() { info 'ERROR: ' "$*" >&2; }
verbose() { info 'VERBOSE: ' "$*" >&2; }

error() {
	_error=${1:-1}
	shift
	stderr "$*"
	exit "$_error"
}

version() {
	info "$version_text"
	exit
}

usage() {
	[ $# -ne 0 ] && {
		exec >&2
		printf '%s: %s\n\n' "$prog_name" "$*"
	}
	printf %s\\n "$help_text"
	exit ${1:+1}
}

clean_exit() {
	_exit_status=$?
	trap - EXIT

	[ $# -ne 0 ] && {
		trap - "$1"
		kill -s "$1" -$$
	}
	exit "$_exit_status"
}

main "$@"
