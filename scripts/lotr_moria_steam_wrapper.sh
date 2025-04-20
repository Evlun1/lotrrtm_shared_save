#!/bin/bash

# Wrapper script to launch Lord of the Ring: Return to Moria game via Steam
# and seemlessly download/upload a common save file
# Usage: In the steam game settings run the following command
#   bash <path/to/script>/lotr_moria_wrapper.sh "%command%"

# Originaly authored by @MoaMoaK
# https://gitlab.com/-/snippets/4832002

# Web server parameters
BASE_URL='REDACTED'
DOWNLOAD_SAVE_URL="${BASE_URL}/get"
UPLOAD_SAVE_URL="${BASE_URL}/post"
USERNAME='REDACTED'
PASSWORD='REDACTED'

# Local save parameters
LOCAL_SAVE_DIR='REDACTED/Moria/Saved/SaveGamesSteam'
LOCAL_SAVE_FILENAME="${LOCAL_SAVE_DIR}/REDACTED.sav"

# Debug parameters
DEBUG=1
DEBUG_FILE='REDACTED/lotr_rtm_wrapper_debug.log'
DEBUG_DELETE_PREV=1





init_logs() {
  if [ "${DEBUG}" -eq 1 ] && [ "${DEBUG_DELETE_PREV}" -eq 1 ]; then
    echo "" > ${DEBUG_FILE}
  fi
}

log() {
  # Usage: log <message>
  if [ "${DEBUG}" -eq 1 ]; then
    echo "$(date '+[%F %T]') $@" >> ${DEBUG_FILE}
  fi
}

notify_user() {
  # Usage: notify_user <title> <message>
  log "=> Call: $FUNCNAME $@"
  notify-send \
    --app-name 'LOTR: RtM - Wrapper DL' \
    "$1" \
    "$2" >/dev/null 2>&1
}

get_error_msg() {
  # Usage : get_error_msg <file_with_json_response>
  log "=> Call: $FUNCNAME $@"
  cat "$f" | jq .'detail'
}

call_api() {
  # Usage: call_api <method> <uri> [curl_options ...]
  # Returns: "<http_code>:<filepath_with_http_response>"
  log "=> Call: $FUNCNAME $@"

  method="$1"; shift
  uri="$1"; shift
  
  f=$(mktemp)
  log "[$FUNCNAME] Created temp file $f"

  log "[$FUNCNAME] Calling API: ${uri} (${method})"
  http_code=$(curl -X "${method}" "${uri}" "$@" \
    -H 'accept: application/json' \
    -s -o "$f" -w "%{http_code}")
  log "[$FUNCNAME] Got HTTP response code: ${http_code}"

  echo "${http_code}:${f}"
}

download_save_file() {
  log "=> Call: $FUNCNAME $@"

  log "[$FUNCNAME] Downloading save file"
  r=$(call_api "GET" "${DOWNLOAD_SAVE_URL}?who_are_you=${USERNAME}&password=${PASSWORD}")
  http_code="$(echo $r | cut -d':' -f1)"; f="$(echo $r | cut -d':' -f2)"
  log "[$FUNCNAME] Save file downloaded (${http_code}): $f"

  if [ "${http_code}" == "200" ]; then
    log "[$FUNCNAME] Considering file download was a success"
    notify_user "Save file successfully downloaded"
    log "[$FUNCNAME] Copying file from $f to ${LOCAL_SAVE_FILENAME}"
    cp -f "$f" "${LOCAL_SAVE_FILENAME}"
    log "[$FUNCNAME] File copied"
    echo "OK"
  elif [ "${http_code}" == "403" ]; then
    log "[$FUNCNAME] Considering incorrect provided password"
    notify_user "Incorrect password" "$(get_error_msg "$f")"
    echo "UNAUTHORIZED"
  elif [ "${http_code}" == "409" ]; then
    log "[$FUNCNAME] Considering file is locked"
    notify_user "Save file locked" "$(get_error_msg "$f")"
    echo "LOCKED"
  else
    log "[$FUNCNAME] Unknown error during file download"
    notify_user "Error: Unknwown http code: $http_code" "For details, see $f"
    echo "KO"
  fi
}

upload_save_file() {
  log "=> Call: $FUNCNAME $@"

  log "[$FUNCNAME] Uploading save file"
  r=$(call_api "POST" "${UPLOAD_SAVE_URL}?who_are_you=${USERNAME}&password=${PASSWORD}" \
    -H 'Content-Type: multipart/form-data' -F "file=@${LOCAL_SAVE_FILENAME}")
  http_code="$(echo $r | cut -d':' -f1)"; f="$(echo $r | cut -d':' -f2)"
  log "[$FUNCNAME] Save file uploaded (${http_code}): $f"
  
  if [ "${http_code}" == "200" ]; then
    log "[$FUNCNAME] Considering file upload was a success"
    notify_user "Save file successfully uploaded"
    echo "OK"
  elif [ "${http_code}" == "403" ]; then
    log "[$FUNCNAME] Considering incorrect provided password"
    notify_user "Incorrect password" "$(get_error_msg "$f")"
    echo "UNAUTHORIZED"
  elif [ "${http_code}" == "409" ]; then
    log "[$FUNCNAME] Considering file upload was a "
    notify_user "Save file locked" "$(get_error_msg "$f")"
    echo "KO"
  else
    log "[$FUNCNAME] Unknown error during file upload"
    notify_user "Error: Unknwown http code: $http_code" "For details, see $f"
    echo "KO"
  fi
}

run_game() {
  # Usage run_game <steam_cmd>
  log "=> Call: $FUNCNAME $@"

  log "[$FUNCNAME] Executing steam command $1"
  eval "$1"
}

main() {
  log "=> Call: $FUNCNAME $@"

  # Try to download the save file
  dl_result="$(download_save_file)"

  if [ "${dl_result}" == "OK" ]; then
    run_game "$1"
    # Try to upload back the file
    if [ "$(upload_save_file)" == "OK" ]; then
      return 0
    else
      return 1
    fi
  elif [ "${dl_result}" == "LOCKED" ]; then
    run_game "$1"
    return 0
  else
    log "[$FUNCNAME] Result of download: '${dl_result}'"
    return 1
  fi
}

init_logs
main "$1"
