#!/bin/sh

prog_name=${0##*/}
version=0.1
version_text="DNS Verification Script v$version"
options="h q v V d S s: " # basic opts
help_text="Usage: $prog_name [-s <file>] [-hqvSV] [<file_or_domain>]...
  ${version_text}
    -s <file>  JSON file of take-down services and a string to check for
    -S         Skip takedown service checking
    -h         Display this help text and exit
    -q         Quiet
    -d         Debug mode (log the entire checking process)
    -v         Verbose mode (show passing domains)
    -V         Display version information and exit
"

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
		$opt_d || debug() { :; }
	}

	ret=0
	_i=1
	for _file; do
		if ! verify_argument "$_file"; then ret=1; fi
		_i=$((_i + 1))
	done
	if [ -p /dev/stdin ]; then
		while IFS= read -r line; do
			if ! verify_argument "${line}"; then ret=1; fi
			_i=$((_i + 1))
		done
	fi
	if [ ${_i} -eq 1 ]; then
		usage
	fi
	unset _i _file

	if [ $ret -ne 0 ]; then
		error $ret "Some domains could not be verified"
	fi
}

verify_argument() (
	file=$1
	ret=0
	# if argument is a file then check all lines as a domain
	if [ -f "$file" ]; then
		while read -r domain; do
			if ! check_domain "${domain}"; then
				ret=1
			fi
		done <"${file}"
	# if argument is not a file act just check it
	else
		if ! check_domain "${file}"; then ret=1; fi
	fi
	return $ret
)

# check if dns entry is resolvable
dns_exists() (nslookup "${1}" >/dev/null)

# fully check a domain
check_domain() (
	orig_domain=${1}
	if [ -z "${orig_domain}" ] || [ ! "${orig_domain}" = "${orig_domain#\#}" ]; then return 0; fi
	debug "Checking ${orig_domain}"

	domain_existence=$(dig "${orig_domain}" +short soa 2>/dev/null)
	if [ -z "${domain_existence}" ]; then
		info "ERROR: ${orig_domain} is not a valid domain"
		return 1
	fi

	domain=$(echo "${orig_domain}" | sed "s/*/potatocannon/")

	# Check to see if all CNAME records are resolvable
	cnames=$(dig CNAME "${domain}" +short)
	for ip in ${cnames}; do
		if ! dns_exists "${ip}"; then
			info "ERROR: ${orig_domain}: Dangling CNAME record ${ip}"
			return 1
		fi
	done

	# Check for take-over abilities
	# shellcheck disable=2154
	if [ "${opt_s}" = "false" ] && [ "${opt_S}" = "false" ]; then
		error 1 "Services file not provided"
	elif [ "${opt_S}" = "false" ]; then
		if [ -f "${val_s}" ]; then
			page_content=$(curl --connect-timeout 5 -L "${domain}" 2>/dev/null)
			services=$(jq -r 'keys[]' "${val_s}")
			for service in ${services}; do
				error_pattern=$(jq -r ".${service}" "${val_s}")
				debug "${service}: Testing for ${error_pattern}"
				if echo "${page_content}" | grep -q "${error_pattern}"; then
					info "ERROR: ${orig_domain}: ${service} vulnerable to DNS take-over"
					return 1
				fi
			done
		else
			error 1 "Services file ${val_s} does not exist!"
		fi
	fi

	# shellcheck disable=2154
	$opt_v && info "${orig_domain}: PASSED"
	return 0
)

##########################################################################

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
debug() { info 'DEBUG: ' "$*" >&2; }

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

error() {
	_error=${1:-1}
	shift
	printf '%s: Error: %s\n' "$prog_name" "$*" >&2
	exit "$_error"
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
