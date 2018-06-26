# Debian Images Maker
## Overview

dim is a shell script that wrap around debootstrap to create custom images.

```
dim: Debian image maker
dim [-a|--activity ACT] [-l|--list] [-b|--begin MIN] [-e|--end MAX] [-o|--only ONLY] [-h|--help] [-d|--device DEVICE] [-t|--template TMPLT] [-D|--dist DIST] [-M|--mirror MIRROR] [-H|--hostname HNAME] [-p|--password PASS] [-T|--target TARGET]
dim [ACT]
-a|--activity ACT        : Select the activity to run
-l|--list                : List all available tasks
-b|--begin MIN           : Begin at that task
-e|--end MAX             : End at that task
-o|--only ONLY           : Only run this step
-h|--help                : Show this help text
-d|--device DEVICE       : Target device type           (DEFAULT: rock64)
-t|--template TMPLT      : Template to use for the image(DEFAULT: none)
-D|--dist DIST           : Debian disribution           (DEFAULT: buster)
-M|--mirror MIRROR       : Debian mirror                (DEFAULT: http://192.168.6.13:3142/debian)
-H|--hostname HNAME      : Hostname                     (DEFAULT: defaulthost)
-p|--password PASS       : root password                (DEFAULT: password)
-T|--target TARGET       : The device to flash to       (DEFAULT: /dev/sdb)

Available values for ACT (Select the activity to run):
setup                    : Setup the system to build images
create                   : Create an image
load                     : Load the image

Available values for DEVICE (Target device type         (DEFAULT: rock64)):
kvm                      : KVM vm images templates
pyra                     : Pyra (pyra-handheld.com) images
rock64                   : Rock64 (www.pine64.org) images

Available values for TMPLT (Template to use for the image(DEFAULT: none)):
ceph                     : A docker VM using the docker official repo
docker                   : A docker VM using the docker official repo
etcd                     : etcd server
cloud                    : Infra node
jenkins                  : A Jenkins server
k8s                      : A kubernetes node unconfigured using officials repos
pacemaker                : Pacemaker install
```

## Running instruction
For lisibility i'm using this variable bellow :
```
    dim="path/to/dim"
```
Beside evrything is done by root...

### initial setup
Edit the conf/dim.conf file to your linking, then :
```
    $dim -a setup
```
to install all the requiered packages and bootstrap the rootfs.

### create your first VM
```
    $dim -H first
```
