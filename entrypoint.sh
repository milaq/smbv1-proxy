#!/bin/bash

PROXY_DIR=/srv/smbproxy
PROXY_ARCHIVE=${PROXY_DIR}_archive

function watch_proxy_dir() {
  mkdir "$PROXY_DIR"
  if [[ $? -ne 0 ]]; then
    echo "Error: Could not create proxy dir or it already exists (did you mount it inside the container without specifying the local proxy UID?)"
    exit 1
  fi
  mkdir "$PROXY_ARCHIVE"

  echo "Getting remote folder list"
  folderlist=$(smbclient //$PROXY_SERVER/$PROXY_SHARENAME -U $PROXY_USER%$PROXY_PASSWORD -c "recurse; ls")
  if [[ $? -ne 0 ]]; then
    echo "Error: Could not connect to remote share"
    exit 1
  fi
  for line in $folderlist; do
    if [[ ${line:0:1} == "\\"  ]]; then
      folder=${line:1}
      smbclient //$PROXY_SERVER/$PROXY_SHARENAME -U $PROXY_USER%$PROXY_PASSWORD -c "ls $folder" > /dev/null
      if [[ $? -ne 0 ]]; then
        echo "Error: Could not get remote folders: $folder"
        exit 1
      fi
      echo "Creating proxy folder: $folder"
      mkdir -p $PROXY_DIR/$folder
      chmod 777 $PROXY_DIR/$folder
    fi
  done

  cd $PROXY_DIR
  inotifywait -m -q -r --format '%w%f' -e CLOSE_WRITE . | while read line; do
    file=$(echo $line | sed 's/\.\///g')
    smbclient //$PROXY_SERVER/$PROXY_SHARENAME -U $PROXY_USER%$PROXY_PASSWORD -c "put $file"
    if [[ $? -ne 0 ]]; then
      echo "Error: Uploading failed. Moving file to archive: $file"
      relfolder=$(dirname $file)
      mkdir -p $PROXY_ARCHIVE/$relfolder
      mv $file $PROXY_ARCHIVE/$relfolder/
    else
      rm $file
    fi
  done
  echo "Stopped watching for file uploads"
}

function start_proxy_smb() {
  echo "Starting Proxy server"
  /usr/sbin/smbd -F -S
  echo "Proxy server stopped"
}

rm /etc/samba/smb.conf
cp /etc/samba/smb.conf.preset /etc/samba/smb.conf

start_sync=0
if [[ -d $PROXY_DIR ]] && [[ -n $PROXY_USER_UID ]]; then
  if [[ -z $PROXY_USER_GID ]]; then
    PROXY_USER_GID=$PROXY_USER_UID
  fi
  echo "Mounted proxy directory and set proxy user IDs detected. Using ${PROXY_USER_UID}:${PROXY_USER_GID} for files."
  groupadd -g $PROXY_USER_GID proxyuser
  useradd -d /nonexistent -M -s /usr/sbin/nologin -u $PROXY_USER_UID -g proxyuser "${PROXY_USER}"
else
  echo "Using smbclient syncing"
  start_sync=1
  useradd -d /nonexistent -M -s /usr/sbin/nologin -g nogroup "${PROXY_USER}"
fi
echo -e "[$PROXY_SHARENAME]\npath = $PROXY_DIR\nwriteable = yes\nbrowseable = yes\n" >> /etc/samba/smb.conf
(echo "$PROXY_PASSWORD"; echo "$PROXY_PASSWORD") | smbpasswd -s -a "${PROXY_USER}"

trap "exit 1" SIGCHLD
if [[ $start_sync -eq 1 ]]; then
  watch_proxy_dir &
fi
start_proxy_smb &

wait
