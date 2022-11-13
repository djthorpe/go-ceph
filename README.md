# go-ceph
Experiments with ceph

To make the docker image, run `make docker`. Then you can bootstrap a monitor using the following:

```
docker build --build-arg VERSION=v17 --build-arg BUILDPLATFORM=arm64 .
```

If you want to prepare a "raw" block device:

```bash
  docker run --name ceph-volume --rm \
    --volume /dev:/dev --volume /opt/ceph:/ceph \
    --net=host --privileged 
    go-ceph:v17 \
    --address 192.168.86.2 --hostname cm1 \
    create-block-device /dev/mmcblk0
```
