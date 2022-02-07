FROM debian:bullseye

MAINTAINER milaq
LABEL build_version="Build-date:- ${BUILD_DATE}"

ARG DEBIAN_FRONTEND="noninteractive"
COPY dpkg_excludes /etc/dpkg/dpkg.cfg.d/excludes

RUN apt-get update && apt-get install --no-install-recommends -y \
    samba \
    cifs-utils \
    && \
    apt-get clean

COPY smb_global.conf /etc/samba/smb.conf.preset
COPY entrypoint.sh /usr/bin/entrypoint.sh

EXPOSE 445/tcp 445/tcp
ENTRYPOINT ["entrypoint.sh"]
