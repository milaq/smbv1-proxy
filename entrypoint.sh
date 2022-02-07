#!/bin/bash

PROXY_DIR=/srv/smbproxy
PROXY_LOCAL_USERS="smbproxy"

mkdir "$PROXY_DIR"
chattr +i "$PROXY_DIR"
mount -t cifs //$PROXY_SERVER/$PROXY_SHARENAME -o username="$PROXY_USER",domain="$PROXY_DOMAIN",password="$PROXY_PASSWORD",iocharset=utf8 $PROXY_DIR
if [[ $? -ne 0 ]]; then
  echo "Error: Mounting remote share failed"
  exit 1
fi

rm /etc/samba/smb.conf
cp /etc/samba/smb.conf.preset /etc/samba/smb.conf
echo -e "[$PROXY_SHARENAME]\npath = $PROXY_DIR\nwriteable = yes\nbrowseable = yes\n" >> /etc/samba/smb.conf

groupadd "$PROXY_LOCAL_USERS"
useradd -d /nonexistent -M -s /usr/sbin/nologin -g "$PROXY_LOCAL_USERS" "${PROXY_LOCAL_USERS}_${PROXY_USER}"
(echo "$PROXY_PASSWORD"; echo "$PROXY_PASSWORD") | smbpasswd -s -a "${PROXY_LOCAL_USERS}_${PROXY_USER}"

/usr/sbin/smbd -F -S