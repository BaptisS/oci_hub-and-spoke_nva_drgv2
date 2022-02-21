#!/bin/sh

date > cleanoutput.log

oci network drg-attachment delete --drg-attachment-id $drg1_attach_spoke2_ocid --force
oci network drg-attachment delete --drg-attachment-id $drg1_attach_spoke1_ocid --force
oci network drg-attachment delete --drg-attachment-id $drg1_attach_sharedvcn_ocid --force

oci network drg delete --drg-id $drg1_ocid --force

oci compute instance terminate --instance-id $vmspoke2ocid --preserve-boot-volume false --force --wait-for-state TERMINATED --wait-interval-seconds 1

# oci network route-table update --rt-id $vcn_spoke2_rt_pubsub_ocid --route-rules '[]' --force
oci network subnet update --subnet-id $vcn_spoke2_subnet1_ocid --route-table-id $vcn_spoke2_rt_default_ocid --security-list-ids '["'$vcn_spoke2_sl_default_ocid'"]' --force
oci network security-list delete --security-list-id $vcn_spoke2_sl_pubsub_ocid --force
oci network route-table delete --rt-id $vcn_spoke2_rt_pubsub_ocid --force

oci network internet-gateway delete --ig-id $vcn_spoke2_ig_ocid --force
oci network subnet delete --subnet-id $vcn_spoke2_subnet1_ocid --force
oci network vcn delete --vcn-id $vcn_spoke2_ocid --force

oci compute instance terminate --instance-id $vmspoke1ocid --preserve-boot-volume false --force --wait-for-state TERMINATED --wait-interval-seconds 1

#oci network route-table update --rt-id $vcn_spoke1_rt_pubsub_ocid --route-rules '[]' --force
oci network subnet update --subnet-id $vcn_spoke1_subnet1_ocid --route-table-id $vcn_spoke1_rt_default_ocid --security-list-ids '["'$vcn_spoke1_sl_default_ocid'"]' --force
oci network security-list delete --security-list-id $vcn_spoke1_sl_pubsub_ocid --force

oci network route-table delete --rt-id $vcn_spoke1_rt_pubsub_ocid --force

oci network internet-gateway delete --ig-id $vcn_spoke1_ig_ocid --force
oci network subnet delete --subnet-id $vcn_spoke1_subnet1_ocid --force
oci network vcn delete --vcn-id $vcn_spoke1_ocid --force

oci compute instance terminate --instance-id $vmocid --preserve-boot-volume false --force --wait-for-state TERMINATED --wait-interval-seconds 1

#oci network route-table update --rt-id $vcn_shared_rt_pubsub_ocid --route-rules '[]' --force
oci network subnet update --subnet-id $vcn_shared_subnet1_ocid --route-table-id $vcn_shared_rt_default_ocid --security-list-ids '["'$vcn_shared_sl_default_ocid'"]' --force
oci network security-list delete --security-list-id $vcn_shared_sl_pubsub_ocid --force
oci network route-table delete --rt-id $vcn_shared_rt_pubsub_ocid --force

oci network subnet delete --subnet-id $vcn_shared_subnet1_ocid --force
oci network internet-gateway delete --ig-id $vcn_shared_ig_ocid --force
oci network route-table delete --rt-id $vcn_shared_rt_drgattach_ocid --force
oci network vcn delete --vcn-id $vcn_shared_ocid --force

date >> cleanoutput.log
cat cleanoutput.log
