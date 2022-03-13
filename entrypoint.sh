#!/bin/bash

PROXY_DIR=/srv/smbproxy
PROXY_ARCHIVE=${PROXY_DIR}_archive

function watch_proxy_dir() {
  mkdir -p "$PROXY_DIR"
  mkdir -p "$PROXY_ARCHIVE"

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

useradd -d /nonexistent -M -s /usr/sbin/nologin -g "nogroup" "${PROXY_USER}"
echo -e "[$PROXY_SHARENAME]\npath = $PROXY_DIR\nwriteable = yes\nbrowseable = yes\n" >> /etc/samba/smb.conf
(echo "$PROXY_PASSWORD"; echo "$PROXY_PASSWORD") | smbpasswd -s -a "${PROXY_USER}"

watch_proxy_dir &
start_proxy_smb &
trap "exit 1" SIGCHLD
wait
