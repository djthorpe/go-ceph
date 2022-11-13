ARG BUILDPLATFORM
ARG VERSION
FROM --platform=${BUILDPLATFORM} quay.io/ceph/ceph:${VERSION} AS go-ceph
COPY entrypoint.sh /entrypoint.sh
COPY etc/ceph.conf /usr/share/ceph/ceph.conf
ENTRYPOINT ["/entrypoint.sh"]
