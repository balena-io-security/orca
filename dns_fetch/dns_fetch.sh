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
# Figure out what expected error codes should be, right now always returns 0
# Add error checking for if Cloudflare token is incorrect
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
	supported_services="cloudflare sample"

	types_filter=$(generate_type_filter "${@}")

	# Calculate filters using command line arguments
	for _service in $supported_services; do
		# Source service functions
		# shellcheck source=services/sample disable=1091
		. "$(dirname "$0")/services/${_service}"
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
	records=$(echo "${records}" | jq -sr "${final_query}")
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
	echo "${types_filter}"
}

# shellcheck disable=2034,2046
set_defaults() {
	# set -e # Automatically exit on failed command
	set +e # Don't exit on failed command
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
verbose() { info 'VERBOSE: ' "$*" >&2; }

error() {
	_error=${1:-1}
	shift
	printf '%s: Error: %s\n' "$prog_name" "$*" >&2
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
