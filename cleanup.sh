#!/bin/sh
oci network drg-attachment delete --drg-attachment-id $sp2drgattachocid --force
oci network drg-attachment delete --drg-attachment-id $sp1drgattachocid --force
oci network drg-attachment delete --drg-attachment-id $drgattachocid --force

oci network drg delete --drg-id $drgocid --force

oci network subnet delete --subnet-id $sp2subnetocid --force
oci network internet-gateway delete --ig-id $sp2igocid --force
oci network vcn delete --vcn-id $sp2vcnocid --force

oci network subnet delete --subnet-id $sp1subnetocid --force
oci network internet-gateway delete --ig-id $sp1igocid --force
oci network vcn delete --vcn-id $sp1vcnocid --force


oci compute instance terminate --instance-id $vmocid --preserve-boot-volume false --force --wait-for-state TERMINATED --wait-interval-seconds 1

oci network subnet delete --subnet-id $subnetocid --force
oci network internet-gateway delete --ig-id $igocid --force
oci network route-table delete --rt-id $sharedvcnrtdrgocid --force
oci network vcn delete --vcn-id $vcnocid --force
