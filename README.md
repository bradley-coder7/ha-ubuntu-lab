# The High-Availability Lab on Ubuntu Project.

This project was started by Bradley Hook in 2023 and first published in 2024.

The goal of the project is to produce complete, working environments that 
feature high-availability solutions from open-source software. The project grew
out of a real-world implementation and the need to document the solution for 
future administrators. It should be considered to be in an "alpha testing" 
state unless and until a future status is published. The author created this lab 
after encountering documentation and examples that were scattered and not uniform 
or compatible with each other. This brings everything together in one demo.

To use the lab, you will need a very basic KVM setup with virt-install and three 
bridged networks in your environment named "br0", "br1", and "br2".

Downloading the configurations and running "sudo ./build.sh" will attempt to 
build a fully functional replica of the lab environment. The scripts currently
expect a copy of the Ubuntu Server 22.04.3 LTS ISO to be present in the same 
directory as the build script.

Note that all published files should be relying heavily on RFC-designated 
TESTNET addresses, which are NOT routable. Future iterations of the project 
may have scripts that facilitate using real addresses without having to hand-
edit several files.

This is a lab, and so several things are insecure unless modified.

Things this project does so far:
1. It builds Ubuntu autoinstall images. These images can be written to a USB 
drive and used to do an automated installation of a system. In this project, 
they are used to completely automate the installation of multiple instances.
2. It runs virt-install to build multiple instances of Ubuntu Linux.
3. It creates a working deployment of keepalived using VRRPv3 with strict RFC
compliance and VMAC (a.k.a. macvlan) enabled. The failover target is 0.35 
seconds. NOTE: a workaround was required due to a bug in either the Linux 
Kernel or Keepalived itself.
4. It creates a working deployment of Kea-DHCP server (currently, only for 
IPv4).
5. It creates a working deployment of conntrackd to facilitate graceful 
failover while preserving stateful connections.

Future goals include building all critical network services, including name 
servers, time servers, logging servers, network monitoring servers, and 
various other components.

The scripts are fairly simple and straight-forward. Read them and look around 
to see how things work together to build a working environment.
