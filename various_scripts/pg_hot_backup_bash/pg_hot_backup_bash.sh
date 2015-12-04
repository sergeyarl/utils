#!/bin/bash

# PostgreSQL hot backup script.
# step by step description can be found here:
# http://www.postgresql.org/docs/9.2/static/continuous-archiving.html
# "24.3.6.1. Standalone Hot Backups" section

ssh='/usr/bin/ssh'
tar='/bin/tar'

host='pg_host'
port='22'
user='postgres'

pg_version='9.4'
pg_dir="/var/lib/postgresql/${pg_version}"

# debug: 1: debug is on - full output
#        2: debug is off - output in case of an error
debug='1'

umask 0077

# we're going to handle output and errors with this function
error_handle()
{
  # status: 1: error
  #         2: success
  local status=1

  # ok_codes: space separated list of allowed exit codes
  # retval: command exit code
  # op_message: message to display
  # cleanup: 1: perform cleanup
  #          2: do not perform cleanup
  # op_output: stderr + stdout of a command
  # dbg: 1: debug is on
  #      2: debug is off
  local ok_codes=("$1")
  local retval=$2
  local op_message=$3
  local cleanup=$4
  local op_output="$5"
  local dbg=$6

  # check if exit code is allowed
  for code in ${ok_codes[@]}
  do
    if (($code == $retval)); then
      local status=2
      break
    fi
  done

  if (($status == 2)); then
    if (($debug == 1)); then
      echo "* ${op_message} : success."
      [ -z "$op_output" ] || echo "$op_output"
    fi
  else
    echo "* ${op_message} : FAILURE!!!"
    echo "* ${op_message} : exit code: $retval"
    if (($cleanup == 1)); then
      echo "Performing cleanup..."
      # execute pg_stop_backup()
      $ssh -p $port ${user}@${host} "psql postgres -c \"select pg_stop_backup();\""
      # remove backup_in_progress file
      $ssh -p $port ${user}@${host} "rm -f ${pg_dir}/main/backup_in_progress"
    fi
    echo "Overall backup status: FAILURE!!!"
    exit 1
  fi
}

if (($debug == 1)); then
  echo "Backup started: $(date '+%Y-%m-%d %H:%M:%S')"
fi

# check if backup_in_progress file exists
out=$(($ssh -p $port ${user}@${host} \
         "test -f ${pg_dir}/main/backup_in_progress && exit 1 || exit 0") 2>&1)
error_handle "0" $? 'check if backup_in_progress file exists' 2 "$out" $debug

# create backup_in_progress file
out=$(($ssh -p $port ${user}@${host} "touch ${pg_dir}/main/backup_in_progress") 2>&1)
error_handle "0" $? 'create backup_in_progress file' 1 "$out" $debug

# clean wal-archive dir
out=$(($ssh -p $port ${user}@${host} "rm -fr ${pg_dir}/wal-archive/*") 2>&1)
error_handle "0" $? 'clean wal-archive dir' 1 "$out" $debug

# execute pg_start_backup()
out=$(($ssh -p $port ${user}@${host} \
  "psql postgres -c \"select pg_start_backup('general_backup', true);\"") 2>&1)
error_handle "0" $? 'execute pg_start_backup()' 1 "$out" $debug

# backup db data dir
out=$(($ssh -p $port ${user}@${host} \
         "$tar --exclude='pg_xlog/*' \
               --exclude='backup_in_progress' \
               --warning=no-file-changed -zcf - ${pg_dir}/main/" > db_data.tar.gz) 2>&1)
error_handle "0 1" $? 'backup db data dir' 1 "$out" $debug

# execute pg_stop_backup()
out=$(($ssh -p $port ${user}@${host} "psql postgres -c \"select pg_stop_backup();\"") 2>&1)
error_handle "0" $? 'execute pg_stop_backup()' 1 "$out" $debug

# remove backup_in_progress file
out=$(($ssh -p $port ${user}@${host} "rm -f ${pg_dir}/main/backup_in_progress") 2>&1)
error_handle "0" $? 'remove backup_in_progress file' 1 "$out" $debug

# backup wal-archive dir
out=$(($ssh -p $port ${user}@${host} \
         "$tar -zcf - ${pg_dir}/wal-archive/" > wal_data.tar.gz) 2>&1)
error_handle "0" $? 'backup wal-archive dir' 1 "$out" $debug

if (($debug == 1)); then
  echo "Backup complete: $(date '+%Y-%m-%d %H:%M:%S'). Status: SUCCESS."
fi
