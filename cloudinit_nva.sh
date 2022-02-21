#!/bin/bash
sudo su
echo net.ipv4.ip_forward = 1 >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf 
