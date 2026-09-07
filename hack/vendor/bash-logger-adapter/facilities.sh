# shellcheck shell=bash

declare __bash_logger_adapter_facilities_sourced="true"

declare -r LOG_FACILITY_KERN="kern"
declare -r LOG_FACILITY_USER="user"
declare -r LOG_FACILITY_MAIL="mail"
declare -r LOG_FACILITY_DAEMON="daemon"
declare -r LOG_FACILITY_AUTH="auth"
declare -r LOG_FACILITY_SYSLOG="syslog"
declare -r LOG_FACILITY_LPR="lpr"
declare -r LOG_FACILITY_NEWS="news"
declare -r LOG_FACILITY_UUCP="uucp"
declare -r LOG_FACILITY_CRON="cron"
declare -r LOG_FACILITY_AUTHPRIV="authpriv"
declare -r LOG_FACILITY_FTP="ftp"
declare -r LOG_FACILITY_LOCAL0="local0"
declare -r LOG_FACILITY_LOCAL1="local1"
declare -r LOG_FACILITY_LOCAL2="local2"
declare -r LOG_FACILITY_LOCAL3="local3"
declare -r LOG_FACILITY_LOCAL4="local4"
declare -r LOG_FACILITY_LOCAL5="local5"
declare -r LOG_FACILITY_LOCAL6="local6"
declare -r LOG_FACILITY_LOCAL7="local7"

validate_log_facility() {
  local -n f="${1}"
  core::require_operands 1 "$@" || return 1

  local log_facilities="${LOG_FACILITY_KERN}|${LOG_FACILITY_USER}|${LOG_FACILITY_MAIL}"
  log_facilities+="|${LOG_FACILITY_DAEMON}|${LOG_FACILITY_AUTH}|${LOG_FACILITY_SYSLOG}"
  log_facilities+="|${LOG_FACILITY_LPR}|${LOG_FACILITY_NEWS}|${LOG_FACILITY_UUCP}"
  log_facilities+="|${LOG_FACILITY_CRON}|${LOG_FACILITY_AUTHPRIV}|${LOG_FACILITY_FTP}"
  log_facilities+="|${LOG_FACILITY_LOCAL0}|${LOG_FACILITY_LOCAL1}|${LOG_FACILITY_LOCAL2}"
  log_facilities+="|${LOG_FACILITY_LOCAL3}|${LOG_FACILITY_LOCAL4}|${LOG_FACILITY_LOCAL5}"
  log_facilities+="|${LOG_FACILITY_LOCAL6}|${LOG_FACILITY_LOCAL7}"

  f="${f,,}"
  if ! [[ ${f} =~ ^({log_facilities}$) ]]; then
    f="$LOG_FACILITY_DAEMON"
  fi
}

