#!/bin/bash

# ! ATTENTION: Functions prefixed with `__` are not meant to be called in tests.

# ! -------------------------------------------------------------------
# ? >> Miscellaneous initialization functionality

function __load_bats_helper() {
  load "${REPOSITORY_ROOT}/test/test_helper/bats-support/load"
  load "${REPOSITORY_ROOT}/test/test_helper/bats-assert/load"
}

__load_bats_helper

# ? << Miscellaneous initialization functionality
# ! -------------------------------------------------------------------
# ? >> Functions to execute commands inside a container

# Execute a command inside a container with an explicit name.
#
# @param ${1} = container name
# @param ...  = command to execute
function _exec_in_container_explicit() {
  local CONTAINER_NAME=${1:?Container name must be provided when using explicit}
  shift 1
  docker exec "${CONTAINER_NAME}" "${@}"
}

# Execute a command inside the container with name ${CONTAINER_NAME}.
#
# @param ...  = command to execute
function _exec_in_container() {
  _exec_in_container_explicit "${CONTAINER_NAME:?Container name must be provided}" "${@}"
}

# Execute a command inside a container with an explicit name. The command is run with
# BATS' `run` so you can check the exit code and use `assert_`.
#
# @param ${1} = container name
# @param ...  = command to execute
function _run_in_container_explicit() {
  local CONTAINER_NAME=${1:?Container name must be provided when using explicit}
  shift 1
  run _exec_in_container_explicit "${CONTAINER_NAME:?Container name must be provided}" "${@}"
}

# Execute a command inside the container with name ${CONTAINER_NAME}. The command
# is run with BATS' `run` so you can check the exit code and use `assert_`.
#
# @param ...  = command to execute
function _run_in_container() {
  _run_in_container_explicit "${CONTAINER_NAME:?Container name must be provided}" "${@}"
}

# Execute a command inside the container with name ${CONTAINER_NAME}. Moreover,
# the command is run by Bash with `/bin/bash -c`.
#
# @param ...  = Bash command to execute
function _exec_in_container_bash() { _exec_in_container /bin/bash -c "${@}" ; }

# Execute a command inside the container with name ${CONTAINER_NAME}. The command
# is run with BATS' `run` so you can check the exit code and use `assert_`. Moreover,
# the command is run by Bash with `/bin/bash -c`.
#
# @param ...  = Bash command to execute
function _run_in_container_bash() { _run_in_container /bin/bash -c "${@}" ; }

# ? << Functions to execute commands inside a container
# ! -------------------------------------------------------------------
# ? << Functions about executing commands with timeouts

# Repeats a given command inside a container (${2}) until the timeout (${1}) is over.
#
# @param ${1} = timeout
# @param ${2} = container name
# @param ...  = test command for container
function _repeat_in_container_until_success_or_timeout() {
  local TIMEOUT="${1:?Timeout duration must be provided}"
  local CONTAINER_NAME="${2:?Container name must be provided}"
  shift 2

  _repeat_until_success_or_timeout \
    --fatal-test "_container_is_running ${CONTAINER_NAME}" \
    "${TIMEOUT}" \
    _exec_in_container "${@}"
}

# Repeats a given command until the timeout (${1}) is over.
#
# @option --fatal-test <COMMAND EVAL STRING> = additional test whose failure aborts immediately
# @param ${1} = timeout
# @param ...  = test to run
function _repeat_until_success_or_timeout() {
  local FATAL_FAILURE_TEST_COMMAND

  if [[ "${1:-}" == "--fatal-test" ]]
  then
    FATAL_FAILURE_TEST_COMMAND="${2:?Provided --fatal-test but no command}"
    shift 2
  fi

  local TIMEOUT=${1:?Timeout duration must be provided}
  shift 1

  if ! [[ "${TIMEOUT}" =~ ^[0-9]+$ ]]
  then
    echo "First parameter for timeout must be an integer, received \"${TIMEOUT}\""
    return 1
  fi

  local STARTTIME=${SECONDS}

  until "${@}"
  do
    if [[ -n ${FATAL_FAILURE_TEST_COMMAND} ]] && ! eval "${FATAL_FAILURE_TEST_COMMAND}"
    then
      echo "\`${FATAL_FAILURE_TEST_COMMAND}\` failed, early aborting repeat_until_success of \`${*}\`" >&2
      return 1
    fi

    sleep 1

    if [[ $(( SECONDS - STARTTIME )) -gt ${TIMEOUT} ]]
    then
      echo "Timed out on command: ${*}" >&2
      return 1
    fi
  done
}

# Like `_repeat_until_success_or_timeout` . The command is run with BATS' `run`
# so you can check the exit code and use `assert_`.
#
# @param ${1} = timeout
# @param ...  = test command to run
function _run_until_success_or_timeout() {
  local TIMEOUT=${1:?Timeout duration must be provided}
  shift 1

  if [[ ! ${TIMEOUT} =~ ^[0-9]+$ ]]
  then
    echo "First parameter for timeout must be an integer, received \"${TIMEOUT}\""
    return 1
  fi

  local STARTTIME=${SECONDS}

  until run "${@}" && [[ ${status} -eq 0 ]]
  do
    sleep 1

    if (( SECONDS - STARTTIME > TIMEOUT ))
    then
      echo "Timed out on command: ${*}" >&2
      return 1
    fi
  done
}

# ? << Functions about executing commands with timeouts
# ! -------------------------------------------------------------------
# ? >> Functions to wait until a condition is met

# Wait until a port is ready.
#
# @param ${1} = port
# @param ${2} = container name
function _wait_for_tcp_port_in_container() {
  local PORT=${1:?Port number must be provided}
  local CONTAINER_NAME=${2:?Container name must be provided}

  _repeat_until_success_or_timeout \
    --fatal-test "_container_is_running ${CONTAINER_NAME}" \
    "${TEST_TIMEOUT_IN_SECONDS}" \
    _exec_in_container_bash "nc -z 0.0.0.0 ${PORT}"
}

# Wait for SMTP port (25) to become ready.
#
# @param ${1} = name of the container
function _wait_for_smtp_port_in_container() {
  _wait_for_tcp_port_in_container 25 "${1:?Container name must be provided}"
}

# Wait for Amavis' port (10024) to become ready.
#
# @param ${1} = name of the container
function wait_for_amavis_port_in_container() {
  _wait_for_tcp_port_in_container 10024 "${1:?Container name must be provided}"
}

# Wait until the SMPT port (25) can respond.
#
# @param ${1} = name of the container
function _wait_for_smtp_port_in_container_to_respond() {
  local CONTAINER_NAME=${1:?Container name must be provided}

  local COUNT=0
  until [[ $(_exec_in_container timeout 10 /bin/bash -c 'echo QUIT | nc localhost 25') == *'221 2.0.0 Bye'* ]]
  do
    if [[ ${COUNT} -eq 20 ]]
    then
      echo "Unable to receive a valid response from 'nc localhost 25' within 20 seconds"
      return 1
    fi

    sleep 1
    (( COUNT += 1 ))
  done
}

# Checks whether a service is running inside a container (${1}).
#
# @param ${1} = container name
# @param ${2} = service name
function __container_has_service_running() {
  local CONTAINER_NAME=${1:?Container name must be provided}
  local SERVICE_NAME="${2:?Service name must be provided}"

  _exec_in_container /usr/bin/supervisorctl status "${SERVICE_NAME}" | grep 'RUNNING' &>/dev/null
}

# Wait until a service is running.
#
# @param ${1} = container name
# @param ${2} = name of the service to wait for
function _wait_for_service() {
  local CONTAINER_NAME=${1:?Container name must be provided}
  local SERVICE_NAME="${2:?Service name must be provided}"

  _repeat_until_success_or_timeout \
    --fatal-test "_container_is_running ${CONTAINER_NAME}" \
    "${TEST_TIMEOUT_IN_SECONDS}" \
    __container_has_service_running "${CONTAINER_NAME}" "${SERVICE_NAME}"
}

# TODO documentation @polarathene
#
# NOTE: Relies on ENV `LOG_LEVEL=debug` or higher
#
# @param ${1} = container name
# @param ${2} = expected count [OPTIONAL]
function _wait_until_expected_count_is_matched() {
  function __get_count() {
    _exec_in_container grep --count "${MATCH_CONTENT}" "${MATCH_IN_LOG}"
  }

  # WARNING: Keep in mind it is a '>=' comparison.
  # If you provide an explict count to match, ensure it is not too low to cause a false-positive.
  function __has_expected_count() {
    # shellcheck disable=2317
    [[ $(__get_count) -ge "${EXPECTED_COUNT}" ]]
  }

  local CONTAINER_NAME=${1:?Container name must be provided}
  local EXPECTED_COUNT=${2:-}

  # Ensure the container is configured with the required `LOG_LEVEL` ENV:
  assert_regex \
    "$(_exec_in_container env | grep '^LOG_LEVEL=')" \
    '=(debug|trace)$'

  # Default behaviour is to wait until one new match is found (eg: incremented),
  # unless explicitly set (useful for waiting on a min count to be reached):
  #
  #                             +1 of starting count:
  [[ -z ${EXPECTED_COUNT} ]] && EXPECTED_COUNT=$(bc <<< "$(__get_count) + 1")

  repeat_until_success_or_timeout 20 __has_expected_count
}

# An account added to `postfix-accounts.cf` must wait for the `changedetector` service
# to process the update before Dovecot creates the mail account and associated storage dir.
#
# @param ${1} = container name
function _wait_until_account_maildir_exists() {
  local CONTAINER_NAME=${1:?Container name must be provided}
  local MAIL_ACCOUNT=${2:?Mail account must be provided}

  local LOCAL_PART="${MAIL_ACCOUNT%@*}"
  local DOMAIN_PART="${MAIL_ACCOUNT#*@}"
  local MAIL_ACCOUNT_STORAGE_DIR="/var/mail/${DOMAIN_PART}/${LOCAL_PART}"

  _repeat_in_container_until_success_or_timeout 60 "${CONTAINER_NAME}" \
    /bin/bash -c "[[ -d ${MAIL_ACCOUNT_STORAGE_DIR} ]]"
}

# Wait until the mail queue is empty inside a container (${1}).
#
# @param ${1} = container name
function _wait_for_empty_mail_queue_in_container() {
  local CONTAINER_NAME=${1:?Container name must be provided}
  local TIMEOUT=${TEST_TIMEOUT_IN_SECONDS}

  # shellcheck disable=SC2016
  _repeat_in_container_until_success_or_timeout \
    "${TIMEOUT}" \
    "${CONTAINER_NAME}" \
    /bin/bash -c '[[ $(mailq) == *"Mail queue is empty"* ]]'
}

# ? << Functions to wait until a condition is met
# ! -------------------------------------------------------------------
# ? >> Miscellaneous helper functions

# Adds a mail account and waits for the associated files to be created.
#
# @param ${1} = container name
# @param ${2} = account name
# @param ${3} = password [OPTIONAL]
function _add_mail_account_then_wait_until_ready() {
  local CONTAINER_NAME=${1:?Container name must be provided}
  local MAIL_ACCOUNT=${2:?Mail account must be provided}
  # Password is optional (omit when the password is not needed during the test)
  local MAIL_PASS="${3:-password_not_relevant_to_test}"

  _run_in_container setup email add "${MAIL_ACCOUNT}" "${MAIL_PASS}"
  assert_success

  _wait_until_account_maildir_exists "${CONTAINER_NAME}" "${MAIL_ACCOUNT}"
}

# Assert that the number of lines output by a previous command matches the given
# amount (${1}). `lines` is a special BATS variable updated via `run`.
#
# @param ${1} = number of lines that the output should have
function _should_output_number_of_lines() {
  assert_equal "${#lines[@]}" "${1}"
}

# Reloads the postfix service.
#
# @param ${1} = container name [OPTIONAL]
function _reload_postfix() {
  local CONTAINER_NAME=${1:-${CONTAINER_NAME}}

  # Reloading Postfix config after modifying it in <2 sec will cause Postfix to delay, workaround that:
  _exec_in_container touch -d '2 seconds ago' /etc/postfix/main.cf
  _exec_in_container postfix reload
}

# Check if a process inside the container (${2}) is running.
#
# @param ${1} = program name
# @param ${2} = container name [OPTIONAL]
function _check_if_process_is_running() {
  local PROGRAM_NAME=${1:?Program name must be provided explicitly}
  local CONTAINER_NAME=${2:-${CONTAINER_NAME}}

  _exec_in_container pgrep "${PROGRAM_NAME}"
}

# Get the IP of the container (${1}).
#
# @param ${1} = container name [OPTIONAL]
function _get_container_ip() {
  local TARGET_CONTAINER_NAME=${1:-${CONTAINER_NAME}}
  docker inspect --format '{{ .NetworkSettings.IPAddress }}' "${TARGET_CONTAINER_NAME}"
}

# Check if a container is running.
#
# @param ${1} = container name
function _container_is_running() {
  local TARGET_CONTAINER_NAME=${1:?Container name must be provided}
  [[ $(docker inspect -f '{{.State.Running}}' "${TARGET_CONTAINER_NAME}") == 'true' ]]
}

# ? << Miscellaneous helper functions
# ! -------------------------------------------------------------------
