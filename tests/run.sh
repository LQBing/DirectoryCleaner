#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="directorycleaner:tests"
PASS=0
TMP_ROOTS=()
TEST_CONTAINERS=()

cleanup() {
  if [ "${#TEST_CONTAINERS[@]}" -gt 0 ]; then
    docker rm -f "${TEST_CONTAINERS[@]}" >/dev/null 2>&1 || true
  fi
  if [ "${#TMP_ROOTS[@]}" -gt 0 ]; then
    rm -rf "${TMP_ROOTS[@]}"
  fi
}
trap cleanup EXIT

log() {
  echo "[test] $*"
}

new_case_dir() {
  local dir
  dir="$(mktemp -d)"
  TMP_ROOTS+=("$dir")
  printf '%s' "$dir"
}

assert_file() {
  if [ ! -f "$1" ]; then
    log "FAIL: expected file: $1"
    exit 1
  fi
}

assert_not_file() {
  if [ -f "$1" ]; then
    log "FAIL: unexpected file: $1"
    exit 1
  fi
}

assert_dir() {
  if [ ! -d "$1" ]; then
    log "FAIL: expected directory: $1"
    exit 1
  fi
}

assert_not_dir() {
  if [ -d "$1" ]; then
    log "FAIL: unexpected directory: $1"
    exit 1
  fi
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  if [ "$actual" != "$expected" ]; then
    log "FAIL: expected '$expected', got '$actual'"
    exit 1
  fi
}

run_container() {
  docker run --rm "$@" "$IMAGE"
}

wait_for_cron_line() {
  local container="$1"
  local expected="$2"
  local i=0
  local out
  while [ "$i" -lt 40 ]; do
    out="$(docker exec "$container" cat /var/spool/cron/crontabs/root 2>/dev/null || true)"
    case "$out" in
      *"$expected"*)
        printf '%s' "$out"
        return 0
        ;;
    esac
    i=$((i + 1))
    sleep 0.25
  done
  return 1
}

write_state_file() {
  local path="$1"
  local log_path="$2"
  local timestamp="$3"
  printf 'logrotate state -- version 2\n"%s" %s\n' "$log_path" "$timestamp" > "$path"
  chmod 600 "$path"
}

file_inode() {
  stat -c '%i' "$1" 2>/dev/null || stat -f '%i' "$1"
}

file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

yesterday_utc() {
  if date -u -v-1d +%Y-%m-%d 2>/dev/null; then
    return 0
  fi
  date -u -d 'yesterday' +%Y-%m-%d
}

two_hours_ago_utc() {
  if date -u -v-2H +%Y-%m-%d-%H:%M:%S 2>/dev/null; then
    return 0
  fi
  date -u -d '2 hours ago' +%Y-%m-%d-%H:%M:%S
}

days_ago_utc() {
  if date -u -v-"$1"d +%Y-%m-%d 2>/dev/null; then
    return 0
  fi
  date -u -d "$1 days ago" +%Y-%m-%d
}

now_utc() {
  date -u "+%Y-%m-%d-%H:%M:%S"
}

build_image() {
  log "building $IMAGE"
  docker build -t "$IMAGE" "$REPO_ROOT" >/dev/null
}

test_size_rotation_default_copytruncate() {
  log "case: default copytruncate size rotation"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs"
  dd if=/dev/zero of="$dir/logs/app.log.json" bs=1024 count=2 2>/dev/null
  local before_inode after_inode
  before_inode="$(file_inode "$dir/logs/app.log.json")"
  run_container -v "$dir/logs:/logs" -e CLEANPATH=/logs -e ROTATE=true -e ROTATESIZE=1k -e ROTATECOUNT=5
  after_inode="$(file_inode "$dir/logs/app.log.json")"
  assert_eq "$after_inode" "$before_inode"
  assert_file "$dir/logs/app.log.json.1"

  dd if=/dev/zero of="$dir/logs/app.log.json" bs=1024 count=2 2>/dev/null
  run_container -v "$dir/logs:/logs" -e CLEANPATH=/logs -e ROTATE=true -e ROTATESIZE=1k -e ROTATECOUNT=5
  assert_file "$dir/logs/app.log.json.1"
  assert_file "$dir/logs/app.log.json.2.gz"
  PASS=$((PASS + 1))
}

test_create_mode() {
  log "case: create mode rotation"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs"
  dd if=/dev/zero of="$dir/logs/app.log.json" bs=1024 count=2 2>/dev/null
  chmod 640 "$dir/logs/app.log.json"
  local before_inode after_inode
  before_inode="$(file_inode "$dir/logs/app.log.json")"
  run_container -v "$dir/logs:/logs" -e CLEANPATH=/logs -e ROTATE=true -e ROTATESIZE=1k -e ROTATEMODE=create
  after_inode="$(file_inode "$dir/logs/app.log.json")"
  if [ "$before_inode" = "$after_inode" ]; then
    log "FAIL: create mode should create a new inode"
    exit 1
  fi
  assert_file "$dir/logs/app.log.json.1"
  PASS=$((PASS + 1))
}

test_time_daily_rotation() {
  log "case: daily time rotation"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs" "$dir/tmp"
  printf 'small line\n' > "$dir/logs/time.log.json"
  chmod 666 "$dir/logs/time.log.json"
  local yesterday
  yesterday="$(yesterday_utc)"
  write_state_file "$dir/tmp/directorycleaner.logrotate.status" "/logs/time.log.json" "$yesterday-00:0:0"
  run_container -v "$dir/logs:/logs" -v "$dir/tmp:/tmp" -e ROTATESTATE=/tmp/directorycleaner.logrotate.status -e CLEANPATH=/logs -e ROTATE=true -e ROTATESIZE=100M -e ROTATEINTERVAL=daily
  assert_file "$dir/logs/time.log.json.1"
  PASS=$((PASS + 1))
}

test_time_hourly_rotation() {
  log "case: hourly time rotation"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs" "$dir/tmp"
  printf 'small line\n' > "$dir/logs/time.log.json"
  chmod 666 "$dir/logs/time.log.json"
  local hour
  hour="$(two_hours_ago_utc)"
  write_state_file "$dir/tmp/directorycleaner.logrotate.status" "/logs/time.log.json" "$hour"
  run_container -v "$dir/logs:/logs" -v "$dir/tmp:/tmp" -e ROTATESTATE=/tmp/directorycleaner.logrotate.status -e CLEANPATH=/logs -e ROTATE=true -e ROTATESIZE=100M -e ROTATEINTERVAL=hourly
  assert_file "$dir/logs/time.log.json.1"
  PASS=$((PASS + 1))
}

test_interval_maxsize_early_rotation() {
  log "case: interval plus maxsize early rotation"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs" "$dir/tmp"
  dd if=/dev/zero of="$dir/logs/big.log.json" bs=1024 count=2 2>/dev/null
  chmod 666 "$dir/logs/big.log.json"
  local now
  now="$(now_utc)"
  write_state_file "$dir/tmp/directorycleaner.logrotate.status" "/logs/big.log.json" "$now"
  run_container -v "$dir/logs:/logs" -v "$dir/tmp:/tmp" -e ROTATESTATE=/tmp/directorycleaner.logrotate.status -e CLEANPATH=/logs -e ROTATE=true -e ROTATESIZE=1k -e ROTATEINTERVAL=daily
  assert_file "$dir/logs/big.log.json.1"
  PASS=$((PASS + 1))
}

test_invalid_size_suffix() {
  log "case: invalid ROTATESIZE suffix"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs"
  printf 'x\n' > "$dir/logs/app.log.json"
  chmod 666 "$dir/logs/app.log.json"
  local out
  out="$(run_container -v "$dir/logs:/logs" -e CLEANPATH=/logs -e ROTATE=true -e ROTATESIZE=50B 2>&1 || true)"
  case "$out" in
    *"ROTATESIZE must be an integer optionally followed by k, K, M, or G"*)
      ;;
    *)
      log "FAIL: unexpected invalid size output: $out"
      exit 1
      ;;
  esac
  PASS=$((PASS + 1))
}

test_invalid_size_decimal() {
  log "case: invalid decimal ROTATESIZE"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs"
  printf 'x\n' > "$dir/logs/app.log.json"
  chmod 666 "$dir/logs/app.log.json"
  local value out
  for value in 1.5M 50.; do
    out="$(run_container -v "$dir/logs:/logs" -e CLEANPATH=/logs -e ROTATE=true -e ROTATESIZE="$value" 2>&1 || true)"
    case "$out" in
      *"ROTATESIZE must be an integer optionally followed by k, K, M, or G"*)
        ;;
      *)
        log "FAIL: unexpected invalid decimal size output for $value: $out"
        exit 1
        ;;
    esac
  done
  PASS=$((PASS + 1))
}

test_invalid_interval() {
  log "case: invalid ROTATEINTERVAL"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs"
  printf 'x\n' > "$dir/logs/app.log.json"
  chmod 666 "$dir/logs/app.log.json"
  local out
  out="$(run_container -v "$dir/logs:/logs" -e CLEANPATH=/logs -e ROTATE=true -e ROTATEINTERVAL=5m 2>&1 || true)"
  case "$out" in
    *"ROTATEINTERVAL must be off, hourly, daily, weekly, monthly, or yearly"*)
      ;;
    *)
      log "FAIL: unexpected invalid interval output: $out"
      exit 1
      ;;
  esac
  PASS=$((PASS + 1))
}

test_boolean_normalization() {
  log "case: boolean normalization"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs"
  dd if=/dev/zero of="$dir/logs/app.log.json" bs=1024 count=2 2>/dev/null
  chmod 666 "$dir/logs/app.log.json"
  run_container -v "$dir/logs:/logs" -e CLEANPATH=/logs -e ROTATE=True -e ROTATESIZE=1k
  assert_file "$dir/logs/app.log.json.1"
  PASS=$((PASS + 1))
}

test_case_insensitive_mode_and_interval() {
  log "case: case-insensitive ROTATEMODE and ROTATEINTERVAL"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs" "$dir/tmp"
  printf 'small line\n' > "$dir/logs/app.log.json"
  chmod 666 "$dir/logs/app.log.json"
  local yesterday
  yesterday="$(yesterday_utc)"
  write_state_file "$dir/tmp/directorycleaner.logrotate.status" "/logs/app.log.json" "$yesterday-00:0:0"
  run_container -v "$dir/logs:/logs" -v "$dir/tmp:/tmp" -e ROTATESTATE=/tmp/directorycleaner.logrotate.status -e CLEANPATH=/logs -e ROTATE=true -e ROTATESIZE=100M -e ROTATEMODE=CREATE -e ROTATEINTERVAL=DAILY
  assert_file "$dir/logs/app.log.json.1"
  PASS=$((PASS + 1))
}

test_rotate_disabled() {
  log "case: ROTATE=false does not rotate"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs"
  dd if=/dev/zero of="$dir/logs/app.log.json" bs=1024 count=2 2>/dev/null
  chmod 666 "$dir/logs/app.log.json"
  run_container -v "$dir/logs:/logs" -e CLEANPATH=/logs -e ROTATE=false -e ROTATESIZE=1k
  assert_not_file "$dir/logs/app.log.json.1"
  PASS=$((PASS + 1))
}

test_lock_waits_then_rotates() {
  log "case: shared lock waits then rotates"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs"
  dd if=/dev/zero of="$dir/logs/app.log.json" bs=1024 count=2 2>/dev/null
  chmod 666 "$dir/logs/app.log.json"
  docker run --rm -v "$dir/logs:/logs" -e CLEANPATH=/logs -e ROTATE=true -e ROTATESIZE=1k --entrypoint /bin/sh \
    "$IMAGE" -c 'rm -f /tmp/lock-ready; ( exec 9>/tmp/directorycleaner.run.lock; flock 9; touch /tmp/lock-ready; sleep 2 ) & while [ ! -f /tmp/lock-ready ]; do sleep 0.05; done; LOCKWAIT=10 /usr/bin/rotate; wait'
  assert_file "$dir/logs/app.log.json.1"
  PASS=$((PASS + 1))
}

test_lock_waits_then_cleans() {
  log "case: shared lock waits then cleans"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs"
  printf 'old\n' > "$dir/logs/old.txt"
  chmod 666 "$dir/logs/old.txt"
  touch -t 202001010000 "$dir/logs/old.txt"
  docker run --rm -v "$dir/logs:/logs" -e CLEANPATH=/logs -e KEEP=1 --entrypoint /bin/sh \
    "$IMAGE" -c 'rm -f /tmp/lock-ready; ( exec 9>/tmp/directorycleaner.run.lock; flock 9; touch /tmp/lock-ready; sleep 2 ) & while [ ! -f /tmp/lock-ready ]; do sleep 0.05; done; LOCKWAIT=10 /usr/bin/cleaner; wait'
  assert_not_file "$dir/logs/old.txt"
  PASS=$((PASS + 1))
}

test_lock_timeout_skips() {
  log "case: shared lock timeout skips"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs"
  dd if=/dev/zero of="$dir/logs/app.log.json" bs=1024 count=2 2>/dev/null
  chmod 666 "$dir/logs/app.log.json"
  docker run --rm -v "$dir/logs:/logs" -e CLEANPATH=/logs -e ROTATE=true -e ROTATESIZE=1k --entrypoint /bin/sh \
    "$IMAGE" -c 'rm -f /tmp/lock-ready; ( exec 9>/tmp/directorycleaner.run.lock; flock 9; touch /tmp/lock-ready; sleep 5 ) & while [ ! -f /tmp/lock-ready ]; do sleep 0.05; done; LOCKWAIT=1 /usr/bin/rotate || true; wait' >/dev/null 2>&1
  assert_not_file "$dir/logs/app.log.json.1"
  PASS=$((PASS + 1))
}

test_find_permission_error_is_reported() {
  log "case: find permission error is reported"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs/secret"
  printf 'hidden\n' > "$dir/logs/secret/hidden.log.json"
  chmod 000 "$dir/logs/secret"
  chmod 755 "$dir/logs"
  local out
  out="$(docker run --rm --user 1000 -v "$dir/logs:/logs" -e CLEANPATH=/logs -e ROTATE=true -e ROTATESIZE=1k -e ROTATECOMPRESS=false --entrypoint /bin/sh \
    "$IMAGE" -c '/usr/bin/rotate' 2>&1 || true)"
  case "$out" in
    *"rotate: failed to scan /logs"*)
      ;;
    *)
      log "FAIL: missing scan error output: $out"
      exit 1
      ;;
  esac
  PASS=$((PASS + 1))
}

test_cron_rows_updated_and_stale_rows_removed() {
  log "case: cron rows updated and stale rows removed"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs" "$dir/cron"
  printf 'x\n' > "$dir/logs/app.log.json"
  chmod 666 "$dir/logs/app.log.json"
  docker run --rm --entrypoint /bin/sh -v "$dir/cron:/var/spool/cron/crontabs" \
    "$IMAGE" -c 'mkdir -p /var/spool/cron/crontabs; printf "* * * * * /usr/bin/rotate\n*/9 * * * * /usr/bin/cleaner\n" > /var/spool/cron/crontabs/root'

  TEST_CONTAINERS+=("dc-test-cron-disabled")
  docker run -d --name dc-test-cron-disabled \
    -e CRON='0 4 * * *' -e ROTATE=false -e CLEANPATH=/logs \
    -v "$dir/logs:/logs" -v "$dir/cron:/var/spool/cron/crontabs" \
    "$IMAGE" >/dev/null
  local crontab
  if ! crontab="$(wait_for_cron_line dc-test-cron-disabled '0 4 * * * /usr/bin/cleaner')"; then
    log "FAIL: timed out waiting for cleaner row"
    exit 1
  fi
  case "$crontab" in
    *"/usr/bin/rotate"*)
      log "FAIL: stale rotate row still present: $crontab"
      exit 1
      ;;
  esac
  docker rm -f dc-test-cron-disabled >/dev/null

  printf "* * * * * /usr/bin/rotate\n*/9 * * * * /usr/bin/cleaner\n" > "$dir/cron/root"
  TEST_CONTAINERS+=("dc-test-cron-enabled")
  docker run -d --name dc-test-cron-enabled \
    -e CRON='0 5 * * *' -e ROTATECRON='*/3 * * * *' -e ROTATE=YES -e CLEANPATH=/logs \
    -v "$dir/logs:/logs" -v "$dir/cron:/var/spool/cron/crontabs" \
    "$IMAGE" >/dev/null
  if ! crontab="$(wait_for_cron_line dc-test-cron-enabled '*/3 * * * * /usr/bin/rotate')"; then
    log "FAIL: timed out waiting for rotate row"
    exit 1
  fi
  case "$crontab" in
    *"0 5 * * * /usr/bin/cleaner"*) ;;
    *)
      log "FAIL: updated cleaner row missing: $crontab"
      exit 1
      ;;
  esac
  docker rm -f dc-test-cron-enabled >/dev/null
  PASS=$((PASS + 1))
}

test_interval_alias() {
  log "case: singular ROTATEINTERVAL alias"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs" "$dir/tmp"
  printf 'small line\n' > "$dir/logs/app.log.json"
  chmod 666 "$dir/logs/app.log.json"
  local yesterday
  yesterday="$(yesterday_utc)"
  write_state_file "$dir/tmp/directorycleaner.logrotate.status" "/logs/app.log.json" "$yesterday-00:0:0"
  run_container -v "$dir/logs:/logs" -v "$dir/tmp:/tmp" -e ROTATESTATE=/tmp/directorycleaner.logrotate.status -e CLEANPATH=/logs -e ROTATE=true -e ROTATESIZE=100M -e ROTATEINTERVAL=DAY
  assert_file "$dir/logs/app.log.json.1"
  PASS=$((PASS + 1))
}

test_cleanemptyfolder_case_insensitive() {
  log "case: case-insensitive CLEANEMPTYFOLDER"
  local keep_dir del_dir
  keep_dir="$(new_case_dir)"
  mkdir -p "$keep_dir/logs/oldempty"
  touch -t 202001010000 "$keep_dir/logs/oldempty"
  run_container -v "$keep_dir/logs:/logs" -e CLEANPATH=/logs -e KEEP=1 -e CLEANEMPTYFOLDER=False
  assert_dir "$keep_dir/logs/oldempty"

  del_dir="$(new_case_dir)"
  mkdir -p "$del_dir/logs/oldempty"
  touch -t 202001010000 "$del_dir/logs/oldempty"
  run_container -v "$del_dir/logs:/logs" -e CLEANPATH=/logs -e KEEP=1 -e CLEANEMPTYFOLDER=True
  assert_not_dir "$del_dir/logs/oldempty"
  PASS=$((PASS + 1))
}

test_run_once_rotates_then_cleans() {
  log "case: run once rotates then cleans"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs"
  dd if=/dev/zero of="$dir/logs/app.log.json" bs=1024 count=2 2>/dev/null
  printf 'old\n' > "$dir/logs/old.txt"
  chmod 666 "$dir/logs/app.log.json" "$dir/logs/old.txt"
  touch -t 202001010000 "$dir/logs/old.txt"
  run_container -v "$dir/logs:/logs" -e CLEANPATH=/logs -e ROTATE=true -e ROTATESIZE=1k -e KEEP=1
  assert_file "$dir/logs/app.log.json.1"
  assert_not_file "$dir/logs/old.txt"
  PASS=$((PASS + 1))
}

test_persistent_state_path() {
  log "case: persistent ROTATESTATE path"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs" "$dir/state"
  printf 'small line\n' > "$dir/logs/app.log.json"
  chmod 666 "$dir/logs/app.log.json"
  local yesterday
  yesterday="$(yesterday_utc)"
  write_state_file "$dir/state/logrotate.status" "/logs/app.log.json" "$yesterday-00:0:0"
  run_container -v "$dir/logs:/logs" -v "$dir/state:/state" \
    -e ROTATESTATE=/state/logrotate.status -e CLEANPATH=/logs -e ROTATE=true \
    -e ROTATESIZE=100M -e ROTATEINTERVAL=daily
  assert_file "$dir/logs/app.log.json.1"
  assert_file "$dir/state/logrotate.status"
  PASS=$((PASS + 1))
}

test_same_cron_rotates_and_cleans() {
  log "case: identical CRON and ROTATECRON run both"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs"
  dd if=/dev/zero of="$dir/logs/app.log.json" bs=1024 count=2 2>/dev/null
  printf 'old\n' > "$dir/logs/old.txt"
  chmod 666 "$dir/logs/app.log.json" "$dir/logs/old.txt"
  touch -t 202001010000 "$dir/logs/old.txt"
  TEST_CONTAINERS+=("dc-test-same-cron")
  docker run -d --name dc-test-same-cron \
    -e CRON='* * * * *' -e ROTATECRON='* * * * *' \
    -e ROTATE=true -e ROTATESIZE=1k -e KEEP=1 \
    -e ROTATESTATE=/tmp/directorycleaner.logrotate.status \
    -e CLEANPATH=/logs -v "$dir/logs:/logs" \
    "$IMAGE" >/dev/null
  echo "[test] waiting for identical cron schedules..."
  sleep 70
  docker logs dc-test-same-cron 2>&1 | tail -n 20
  assert_file "$dir/logs/app.log.json.1"
  assert_not_file "$dir/logs/old.txt"
  docker rm -f dc-test-same-cron >/dev/null
  PASS=$((PASS + 1))
}

test_invalid_cron_fields() {
  log "case: invalid CRON field count"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs"
  printf 'x\n' > "$dir/logs/app.log.json"
  chmod 666 "$dir/logs/app.log.json"
  local out
  out="$(run_container -v "$dir/logs:/logs" -e CLEANPATH=/logs -e CRON='* * * *' 2>&1 || true)"
  case "$out" in
    *"CRON must have exactly 5 fields"*) ;;
    *)
      log "FAIL: invalid CRON was not rejected: $out"
      exit 1
      ;;
  esac
  PASS=$((PASS + 1))
}

test_rotatereate_attributes() {
  log "case: fixed create attributes"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs"
  dd if=/dev/zero of="$dir/logs/app.log.json" bs=1024 count=2 2>/dev/null
  chmod 644 "$dir/logs/app.log.json"
  run_container -v "$dir/logs:/logs" -e CLEANPATH=/logs -e ROTATE=true \
    -e ROTATESIZE=1k -e ROTATEMODE=create -e ROTATECREATE='0640 root root'
  assert_file "$dir/logs/app.log.json.1"
  assert_eq "$(file_mode "$dir/logs/app.log.json")" "640"
  PASS=$((PASS + 1))
}

test_path_with_spaces() {
  log "case: CLEANPATH with spaces"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs/dir with space"
  dd if=/dev/zero of="$dir/logs/dir with space/app.log.json" bs=1024 count=2 2>/dev/null
  chmod 666 "$dir/logs/dir with space/app.log.json"
  run_container -v "$dir/logs:/logs" -e "CLEANPATH=/logs/dir with space" \
    -e ROTATE=true -e ROTATESIZE=1k
  assert_file "$dir/logs/dir with space/app.log.json.1"
  PASS=$((PASS + 1))
}

test_calendar_intervals() {
  log "case: weekly/monthly/yearly rotation"
  local spec interval days
  for spec in "weekly 8" "monthly 32" "yearly 370"; do
    interval="${spec%% *}"
    days="${spec##* }"
    local dir
    dir="$(new_case_dir)"
    mkdir -p "$dir/logs" "$dir/tmp"
    printf 'small line\n' > "$dir/logs/time.log.json"
    chmod 666 "$dir/logs/time.log.json"
    write_state_file "$dir/tmp/directorycleaner.logrotate.status" \
      "/logs/time.log.json" "$(days_ago_utc "$days")-00:0:0"
    run_container -v "$dir/logs:/logs" -v "$dir/tmp:/tmp" \
      -e ROTATESTATE=/tmp/directorycleaner.logrotate.status \
      -e CLEANPATH=/logs -e ROTATE=true -e ROTATESIZE=100M \
      -e ROTATEINTERVAL="$interval"
    assert_file "$dir/logs/time.log.json.1"
  done
  PASS=$((PASS + 1))
}

test_single_file_cleanpath() {
  log "case: CLEANPATH as a single file"
  local dir
  dir="$(new_case_dir)"
  mkdir -p "$dir/logs"
  printf 'old\n' > "$dir/logs/old.log"
  chmod 666 "$dir/logs/old.log"
  touch -t 202001010000 "$dir/logs/old.log"
  run_container -v "$dir/logs:/logs" -e CLEANPATH=/logs/old.log -e KEEP=1
  assert_not_file "$dir/logs/old.log"
  PASS=$((PASS + 1))
}

main() {
  command -v docker >/dev/null 2>&1 || {
    echo "docker is required" >&2
    exit 1
  }
  build_image
  test_size_rotation_default_copytruncate
  test_create_mode
  test_rotatereate_attributes
  test_path_with_spaces
  test_time_daily_rotation
  test_time_hourly_rotation
  test_persistent_state_path
  test_interval_maxsize_early_rotation
  test_invalid_size_suffix
  test_invalid_size_decimal
  test_invalid_interval
  test_boolean_normalization
  test_case_insensitive_mode_and_interval
  test_interval_alias
  test_calendar_intervals
  test_cleanemptyfolder_case_insensitive
  test_rotate_disabled
  test_single_file_cleanpath
  test_lock_waits_then_rotates
  test_lock_waits_then_cleans
  test_lock_timeout_skips
  test_find_permission_error_is_reported
  test_cron_rows_updated_and_stale_rows_removed
  test_invalid_cron_fields
  test_same_cron_rotates_and_cleans
  echo "PASS: $PASS DirectoryCleaner test cases"
}

main "$@"
