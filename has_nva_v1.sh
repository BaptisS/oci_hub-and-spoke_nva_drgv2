#!/bin/sh
echo " DRGv2 - HUB AND SPOKE WITH NVA SOLUTION DEPLOYMENT "
echo "Please wait while the resources are being deployed (approx. 4 mins)"
echo ""
echo ""
#export compocid="ocid1.compartment.oc1..axxxx"
#export ssh_public_key="ssh-rsa AAAABabcdefghij"
#export myadminsrcipv4="0.0.0.0/0"



export vcn_shared_cidrs='["172.16.100.0/24"]'
export vcn_shared_displayname="HUB_VCN"
export vcn_shared_dnslabel="hubvcn"
export vcn_shared_rt_drgattach_displayname="DRG-ATTACH-RT"
export vcn_shared_subnet1_cidr="172.16.100.0/27"
export vcn_shared_subnet1_displayname="Public_Subnet_1"

export drg1_displayname="HUB_DRG"
export drg1_rt_sharedvcn_displayname="DRG_RT_HUB_VCN"
export drg1_rd_sharedvcn_displayname="DRG_RD_HUB_VCN"
#export drg1_rd_sharedvcn_statements='[{"action":"ACCEPT","matchCriteria":[{"attachmentType":"VIRTUAL_CIRCUIT","matchType":"DRG_ATTACHMENT_TYPE"}],"priority":"3"}]'
export drg1_rd_sharedvcn_statements='[{"action":"ACCEPT","matchCriteria":[],"priority":"1"}]'
export drg1_attach_sharedvcn_displayname="DRG_ATTACH_HUB_VCN"

date > output.log

####  SHARED VCN ####

#VCN Creation
vcn_shared=$(oci network vcn create --compartment-id $compocid --cidr-blocks $vcn_shared_cidrs --display-name $vcn_shared_displayname --dns-label $vcn_shared_dnslabel)
export vcn_shared_ocid=$(echo $vcn_shared | jq -r .data.id)
echo vcn_shared_ocid=$vcn_shared_ocid >> output.log

#Subnet Creation
vcn_shared_subnet1=$(oci network subnet create --cidr-block $vcn_shared_subnet1_cidr --compartment-id $compocid --vcn-id $vcn_shared_ocid --display-name $vcn_shared_subnet1_displayname --prohibit-public-ip-on-vnic false)
export vcn_shared_subnet1_ocid=$(echo $vcn_shared_subnet1 | jq -r .data.id)
echo vcn_shared_subnet1_ocid=$vcn_shared_subnet1_ocid >> output.log

#Internet Gateway Creation
vcn_shared_ig=$(oci network internet-gateway create --compartment-id $compocid --vcn-id $vcn_shared_ocid --display-name "IGW" --is-enabled "true")
export vcn_shared_ig_ocid=$(echo $vcn_shared_ig | jq -r .data.id)
echo vcn_shared_ig_ocid=$vcn_shared_ig_ocid >> output.log

#GET Default SL (VCN SHARED) 
vcn_shared_sl_default=$(oci network security-list list --compartment-id $compocid --vcn-id $vcn_shared_ocid) 
export vcn_shared_sl_default_ocid=$(echo $vcn_shared_sl_default | jq .data | jq -r '.[] | ."id"')
echo vcn_shared_sl_default_ocid=$vcn_shared_sl_default_ocid >> output.log

#GET Default RT (VCN SHARED) 
vcn_shared_rt_default=$(oci network route-table list --compartment-id $compocid --vcn-id $vcn_shared_ocid) 
export vcn_shared_rt_default_ocid=$(echo $vcn_shared_rt_default | jq .data | jq -r '.[] | ."id"')
echo vcn_shared_rt_default_ocid=$vcn_shared_rt_default_ocid >> output.log

####  NVA VM  ####

# NVA VM Creation (oracle Linux 8 with Ip forwarding enabled)
export ad=$(oci iam availability-domain list --query 'data[0].name' --raw-output)
export vmshape=$(oci compute shape list --compartment-id $compocid --all --query 'data[?"memory-in-gbs" == `15.0`] | [0].shape' --raw-output)
export imageocid=$(oci compute image list --compartment-id $compocid --operating-system 'Oracle Linux' --operating-system-version '7.9' --shape $vmshape --query 'data[0].id' --raw-output)

export vmname="NVA-VM-1"
echo $ssh_public_key > sshkeyfile.pub
export ssh_auth_keys_file="./sshkeyfile.pub"

rm -f cloudinit_nva.sh
  wget https://raw.githubusercontent.com/BaptisS/oci_hub-and-spoke_nva_drgv2/main/cloudinit_nva.sh
  chmod +rx cloudinit_nva.sh 

vm=$(oci compute instance launch \
    --compartment-id $compocid \
    --availability-domain $ad \
    --display-name $vmname \
    --image-id $imageocid \
    --shape $vmshape \
    --subnet-id $vcn_shared_subnet1_ocid \
    --skip-source-dest-check true \
    --assign-public-ip true \
    --user-data-file "./cloudinit_nva.sh" \
    --ssh-authorized-keys-file "${ssh_auth_keys_file}")

export vmocid=$(echo $vm | jq -r .data.id)
echo vmocid=$vmocid >> output.log

sleep 10

vnicattach=$(oci compute vnic-attachment list --compartment-id $compocid --instance-id $vmocid)
export vnicocid=$(echo $vnicattach | jq .data | jq -r '.[] | ."vnic-id"')
privip=$(oci network private-ip list --vnic-id $vnicocid)
export privipocid=$(echo $privip | jq .data | jq -r '.[] | ."id"')
echo privipocid=$privipocid >> output.log

####  HUB DRG  ####

#DRG Creation
drg1=$(oci network drg create --compartment-id $compocid --display-name $drg1_displayname --wait-for-state AVAILABLE --wait-interval-seconds 1)
export drg1_ocid=$(echo $drg1 | jq -r .data.id)
echo drg1_ocid=$drg1_ocid >> output.log

####  DRG ROUTE TABLE (HUB VCN ATTACH)  ####

#DRG Route Distribution Creation (Shared VCN) 
drg1_rd_sharedvcn=$(oci network drg-route-distribution create --distribution-type "IMPORT" --drg-id $drg1_ocid --display-name $drg1_rd_sharedvcn_displayname)
export drg1_rd_sharedvcn_ocid=$(echo $drg1_rd_sharedvcn | jq -r .data.id)
echo drg1_rd_sharedvcn_ocid=$drg1_rd_sharedvcn_ocid >> output.log

#DRG Route Distribution Statement Creation 
drg1_rd_sharedvcn_stat=$(oci network drg-route-distribution-statement add --route-distribution-id $drg1_rd_sharedvcn_ocid --statements $drg1_rd_sharedvcn_statements)
export drg1_rd_sharedvcn_stat_id=$(echo $drg1_rd_sharedvcn_stat | jq .data | jq -r '.[] | ."id"')
echo drg1_rd_sharedvcn_stat_id=$drg1_rd_sharedvcn_stat_id >> output.log

#DRG Route Table Creation (Shared VCN)
drg1_rt_sharedvcn=$(oci network drg-route-table create --drg-id $drg1_ocid --display-name $drg1_rt_sharedvcn_displayname --import-route-distribution-id $drg1_rd_sharedvcn_ocid --wait-for-state AVAILABLE --wait-interval-seconds 1)
export drg1_rt_sharedvcn_ocid=$(echo $drg1_rt_sharedvcn | jq -r .data.id)
echo drg1_rt_sharedvcn_ocid=$drg1_rt_sharedvcn_ocid >> output.log

#VCN Route Table Creation (Shared VCN DRG-ATTACH-RT)
#sharedvcnrtdrg=$(oci network route-table create --compartment-id $compocid --vcn-id $vcnocid --display-name $sharedvcnrtdrgname --route-rules '[{"cidrBlock":"10.0.0.0/8","networkEntityId":"ocid1.internetgateway.oc1.phx.aaaaaaaaxtfqb2srw7hoi5cmdum4n6ow2xm2zhrzqqypmlteiiebtmvl75ya"}]')
#vcn_shared_rt_drgattach=$(oci network route-table create --compartment-id $compocid --vcn-id $vcn_shared_ocid --display-name $vcn_shared_rt_drgattach_displayname --route-rules '[{"cidrBlock":"10.0.0.0/8","networkEntityId":"'$privipocid'","description":"RFC1918"},{"cidrBlock":"172.16.0.0/12","networkEntityId":"'$privipocid'","description":"RFC1918"},{"cidrBlock":"192.168.0.0/16","networkEntityId":"'$privipocid'","description":"RFC1918"}]')
vcn_shared_rt_drgattach=$(oci network route-table create --compartment-id $compocid --vcn-id $vcn_shared_ocid --display-name $vcn_shared_rt_drgattach_displayname --route-rules '[{"cidrBlock":"0.0.0.0/0","networkEntityId":"'$privipocid'","description":"Default Route To NVA"}]')
export vcn_shared_rt_drgattach_ocid=$(echo $vcn_shared_rt_drgattach | jq -r .data.id)
echo vcn_shared_rt_drgattach_ocid=$vcn_shared_rt_drgattach_ocid >> output.log

#DRG Attachment
drg1_attach_sharedvcn=$(oci network drg-attachment create --drg-id $drg1_ocid --display-name $drg1_attach_sharedvcn_displayname --drg-route-table-id $drg1_rt_sharedvcn_ocid --route-table-id $vcn_shared_rt_drgattach_ocid --vcn-id $vcn_shared_ocid --wait-for-state ATTACHED --wait-interval-seconds 1)
export drg1_attach_sharedvcn_ocid=$(echo $drg1_attach_sharedvcn | jq -r .data.id)
echo drg1_attach_sharedvcn_ocid=$drg1_attach_sharedvcn_ocid >> output.log

####  SECURITY LIST (PUBLIC SUBNET - VCN SHARED)  ####
#Public Subnet SL Creation (VCN SHARED) (Public-Subnet-SL)
export vcn_shared_sl_pubsub_displayname="Public_Subnet_SL"
export vcn_shared_sl_pubsub_secrules_egress='[{"destination":"0.0.0.0/0","protocol":"all","isStateless":"false"}]'
export vcn_shared_sl_pubsub_secrules_ingress='[{"source":"'$myadminsrcipv4'","protocol":"6","isStateless":true,"tcpOptions":{"destinationPortRange":{"max":22,"min":22}}},{"source":"172.16.0.0/16","protocol":"1","isStateless":true}]'

vcn_shared_sl_pubsub=$(oci network security-list create --compartment-id $compocid --vcn-id $vcn_shared_ocid --display-name $vcn_shared_sl_pubsub_displayname --egress-security-rules $vcn_shared_sl_pubsub_secrules_egress --ingress-security-rules $vcn_shared_sl_pubsub_secrules_ingress)
export vcn_shared_sl_pubsub_ocid=$(echo $vcn_shared_sl_pubsub | jq -r .data.id)
echo vcn_shared_sl_pubsub_ocid=$vcn_shared_sl_pubsub_ocid >> output.log

#Assign PubSub-SL to Subnet1 
oci network subnet update --subnet-id $vcn_shared_subnet1_ocid --security-list-ids '["'$vcn_shared_sl_pubsub_ocid'"]' --force

####  VCN ROUTE TABLE (PUBLIC SUBNET - VCN SHARED)  ####

#VCN SHARED Route Table Creation (Public-Subnet-RT)
export vcn_shared_rt_pubsub_displayname="Public_Subnet_RT"

vcn_shared_rt_pubsub=$(oci network route-table create --compartment-id $compocid --vcn-id $vcn_shared_ocid --display-name $vcn_shared_rt_pubsub_displayname --route-rules '[{"cidrBlock":"0.0.0.0/0","networkEntityId":"'$vcn_shared_ig_ocid'","description":"Default route to internet"},{"cidrBlock":"10.0.0.0/8","networkEntityId":"'$drg1_ocid'","description":"RFC1918"},{"cidrBlock":"172.16.0.0/12","networkEntityId":"'$drg1_ocid'","description":"RFC1918"},{"cidrBlock":"192.168.0.0/16","networkEntityId":"'$drg1_ocid'","description":"RFC1918"}]')
export vcn_shared_rt_pubsub_ocid=$(echo $vcn_shared_rt_pubsub | jq -r .data.id)
echo vcn_shared_rt_pubsub_ocid=$vcn_shared_rt_pubsub_ocid >> output.log

#Assign PubSub-RT to Subnet1
oci network subnet update --subnet-id $vcn_shared_subnet1_ocid --route-table-id $vcn_shared_rt_pubsub_ocid

####  DRG ROUTE TABLE (SPOKES VCN ATTACH)  ####

export drg1_rt_spokesvcn_displayname="DRG_RT_SPOKES_VCN"
export drg1_rd_spokesvcn_displayname="DRG_RD_SPOKES_VCN"
export drg1_rd_spokesvcn_statements='[{"action":"ACCEPT","matchCriteria":[{"drgAttachmentId":"'$drg1_attach_sharedvcn_ocid'","matchType":"DRG_ATTACHMENT_ID"}],"priority":"1"}]'

#DRG Route Distribution Creation (SPOKE VCN) 
drg1_rd_spokesvcn=$(oci network drg-route-distribution create --distribution-type "IMPORT" --drg-id $drg1_ocid --display-name $drg1_rd_spokesvcn_displayname)
export drg1_rd_spokesvcn_ocid=$(echo $drg1_rd_spokesvcn | jq -r .data.id)
echo drg1_rd_spokesvcn_ocid=$drg1_rd_spokesvcn_ocid >> output.log

#DRG Route Distribution Statement Creation (SPOKE VCN)
drg1_rd_spokesvcn_stat=$(oci network drg-route-distribution-statement add --route-distribution-id $drg1_rd_spokesvcn_ocid --statements $drg1_rd_spokesvcn_statements)
#drgrdspokestat=$(oci network drg-route-distribution-statement add --route-distribution-id $drgrdspokeocid --statements '[{"action":"ACCEPT","matchCriteria":[{"drgAttachmentId":"'$drgattachocid'","matchType":"DRG_ATTACHMENT_ID"}],"priority":"1"}]')
export drg1_rd_spokesvcn_stat_id=$(echo $drg1_rd_spokesvcn_stat | jq .data | jq -r '.[] | ."id"')
echo drg1_rd_spokesvcn_stat_id=$drg1_rd_spokesvcn_stat_id >> output.log

#DRG Route Table Creation (SPOKE VCN)
drg1_rt_spokesvcn=$(oci network drg-route-table create --drg-id $drg1_ocid --display-name $drg1_rt_spokesvcn_displayname --import-route-distribution-id $drg1_rd_spokesvcn_ocid --wait-for-state AVAILABLE --wait-interval-seconds 1)
export drg1_rt_spokesvcn_ocid=$(echo $drg1_rt_spokesvcn | jq -r .data.id)
echo drg1_rt_spokesvcn_ocid=$drg1_rt_spokesvcn_ocid >> output.log

#Set DRG_RT_SPOKES as default for VCNs
oci network drg update --drg-id $drg1_ocid --default-drg-route-tables '{"vcn":"'$drg1_rt_spokesvcn_ocid'"}' --force


####  SPOKE VCN 1  ####

export vcn_spoke1_cidrs='["172.16.101.0/24"]'
export vcn_spoke1_subnet_1_cidr="172.16.101.0/27"
export vcn_spoke1_displayname="SPOKE_VCN_1"
export vcn_spoke1_dnslabel="spokevcn1"
export drg1_attach_spoke1_displayname="DRG_ATTACH_SPOKE_VCN_1"

#VCN Creation
vcn_spoke1=$(oci network vcn create --compartment-id $compocid --cidr-blocks $vcn_spoke1_cidrs --display-name $vcn_spoke1_displayname --dns-label $vcn_spoke1_dnslabel)
export vcn_spoke1_ocid=$(echo $vcn_spoke1 | jq -r .data.id)
echo vcn_spoke1_ocid=$vcn_spoke1_ocid >> output.log

#Subnet Creation
vcn_spoke1_subnet1=$(oci network subnet create --cidr-block $vcn_spoke1_subnet_1_cidr --compartment-id $compocid --vcn-id $vcn_spoke1_ocid --prohibit-public-ip-on-vnic false)
export vcn_spoke1_subnet1_ocid=$(echo $vcn_spoke1_subnet1 | jq -r .data.id)
echo vcn_spoke1_subnet1_ocid=$vcn_spoke1_subnet1_ocid >> output.log

#Internet Gateway Creation
vcn_spoke1_ig=$(oci network internet-gateway create --compartment-id $compocid --vcn-id $vcn_spoke1_ocid --display-name "IGW" --is-enabled "true")
export vcn_spoke1_ig_ocid=$(echo $vcn_spoke1_ig | jq -r .data.id)
echo vcn_spoke1_ig_ocid=$vcn_spoke1_ig_ocid >> output.log

#DRG Attachment
drg1_attach_spoke1=$(oci network drg-attachment create --drg-id $drg1_ocid --display-name $drg1_attach_spoke1_displayname --vcn-id $vcn_spoke1_ocid)
export drg1_attach_spoke1_ocid=$(echo $drg1_attach_spoke1 | jq -r .data.id)
echo drg1_attach_spoke1_ocid=$drg1_attach_spoke1_ocid >> output.log

####  SECURITY LIST (PUBLIC SUBNET - VCN SPOKE 1)  ####

#Get Default SL (VCN SPOKE1) 
vcn_spoke1_sl_default=$(oci network security-list list --compartment-id $compocid --vcn-id $vcn_spoke1_ocid) 
export vcn_spoke1_sl_default_ocid=$(echo $vcn_spoke1_sl_default | jq .data | jq -r '.[] | ."id"')
echo vcn_spoke1_sl_default_ocid=$vcn_spoke1_sl_default_ocid >> output.log

export vcn_spoke1_sl_pubsub_displayname="Public_Subnet_SL"
export vcn_spoke1_sl_pubsub_secrules_egress='[{"destination":"0.0.0.0/0","protocol":"all","isStateless":"false"}]'
export vcn_spoke1_sl_pubsub_secrules_ingress='[{"source":"'$myadminsrcipv4'","protocol":"6","isStateless":true,"tcpOptions":{"destinationPortRange":{"max":22,"min":22}}},{"source":"172.16.0.0/16","protocol":"1","isStateless":true}]'

vcn_spoke1_sl_pubsub=$(oci network security-list create --compartment-id $compocid --vcn-id $vcn_spoke1_ocid --display-name $vcn_spoke1_sl_pubsub_displayname --egress-security-rules $vcn_spoke1_sl_pubsub_secrules_egress --ingress-security-rules $vcn_spoke1_sl_pubsub_secrules_ingress)
export vcn_spoke1_sl_pubsub_ocid=$(echo $vcn_spoke1_sl_pubsub | jq -r .data.id)
echo vcn_spoke1_sl_pubsub_ocid=$vcn_spoke1_sl_pubsub_ocid >> output.log

#Assign PubSub-SL to Subnet1 
oci network subnet update --subnet-id $vcn_spoke1_subnet1_ocid --security-list-ids '["'$vcn_spoke1_sl_pubsub_ocid'"]' --force

####  VCN ROUTE TABLE (PUBLIC SUBNET - VCN SPOKE 1)  ####

#GET Default RT (VCN SPOKE 1) 
vcn_spoke1_rt_default=$(oci network route-table list --compartment-id $compocid --vcn-id $vcn_spoke1_ocid) 
export vcn_spoke1_rt_default_ocid=$(echo $vcn_spoke1_rt_default | jq .data | jq -r '.[] | ."id"')
echo vcn_spoke1_rt_default_ocid=$vcn_spoke1_rt_default_ocid >> output.log

#VCN SPOKE1 Route Table Creation (Public-Subnet-RT)
export vcn_spoke1_rt_pubsub_displayname="Public_Subnet_RT"

vcn_spoke1_rt_pubsub=$(oci network route-table create --compartment-id $compocid --vcn-id $vcn_spoke1_ocid --display-name $vcn_spoke1_rt_pubsub_displayname --route-rules '[{"cidrBlock":"0.0.0.0/0","networkEntityId":"'$vcn_spoke1_ig_ocid'","description":"Default route to Internet"},{"cidrBlock":"10.0.0.0/8","networkEntityId":"'$drg1_ocid'","description":"RFC1918"},{"cidrBlock":"172.16.0.0/12","networkEntityId":"'$drg1_ocid'","description":"RFC1918"},{"cidrBlock":"192.168.0.0/16","networkEntityId":"'$drg1_ocid'","description":"RFC1918"}]')
export vcn_spoke1_rt_pubsub_ocid=$(echo $vcn_spoke1_rt_pubsub | jq -r .data.id)
echo vcn_spoke1_rt_pubsub_ocid=$vcn_spoke1_rt_pubsub_ocid >> output.log

#Assign PubSub-RT to Subnet1
oci network subnet update --subnet-id $vcn_spoke1_subnet1_ocid --route-table-id $vcn_spoke1_rt_pubsub_ocid


####  SPOKE VCN 2  ####
 
export vcn_spoke2_cidrs='["172.16.102.0/24"]'
export vcn_spoke2_subnet_1_cidr="172.16.102.0/27"
export vcn_spoke2_displayname="SPOKE_VCN_2"
export vcn_spoke2_dnslabel="spokevcn2"
export drg1_attach_spoke2_displayname="DRG_ATTACH_SPOKE_VCN_2"

#VCN Creation
vcn_spoke2=$(oci network vcn create --compartment-id $compocid --cidr-blocks $vcn_spoke2_cidrs --display-name $vcn_spoke2_displayname --dns-label $vcn_spoke2_dnslabel)
export vcn_spoke2_ocid=$(echo $vcn_spoke2 | jq -r .data.id)
echo vcn_spoke2_ocid=$vcn_spoke2_ocid >> output.log

#Subnet Creation
vcn_spoke2_subnet1=$(oci network subnet create --cidr-block $vcn_spoke2_subnet_1_cidr --compartment-id $compocid --vcn-id $vcn_spoke2_ocid --prohibit-public-ip-on-vnic false)
export vcn_spoke2_subnet1_ocid=$(echo $vcn_spoke2_subnet1 | jq -r .data.id)
echo vcn_spoke2_subnet1_ocid=$vcn_spoke2_subnet1_ocid >> output.log

#Internet Gateway Creation
vcn_spoke2_ig=$(oci network internet-gateway create --compartment-id $compocid --vcn-id $vcn_spoke2_ocid --display-name "IGW" --is-enabled "true")
export vcn_spoke2_ig_ocid=$(echo $vcn_spoke2_ig | jq -r .data.id)
echo vcn_spoke2_ig_ocid=$vcn_spoke2_ig_ocid >> output.log

#DRG Attachment
drg1_attach_spoke2=$(oci network drg-attachment create --drg-id $drg1_ocid --display-name $drg1_attach_spoke2_displayname --vcn-id $vcn_spoke2_ocid)
export drg1_attach_spoke2_ocid=$(echo $drg1_attach_spoke2 | jq -r .data.id)
echo drg1_attach_spoke2_ocid=$drg1_attach_spoke2_ocid >> output.log

####  SECURITY LIST (PUBLIC SUBNET - VCN SPOKE 2)  ####

#GET Default SL (VCN SPOKE2) 
vcn_spoke2_sl_default=$(oci network security-list list --compartment-id $compocid --vcn-id $vcn_spoke2_ocid) 
export vcn_spoke2_sl_default_ocid=$(echo $vcn_spoke2_sl_default | jq .data | jq -r '.[] | ."id"')
echo vcn_spoke2_sl_default_ocid=$vcn_spoke2_sl_default_ocid >> output.log

#Public Subnet SL Creation (VCN SPOKE1) (Public-Subnet-SL)
export vcn_spoke2_sl_pubsub_displayname="Public_Subnet_SL"
export vcn_spoke2_sl_pubsub_secrules_egress='[{"destination":"0.0.0.0/0","protocol":"all","isStateless":"false"}]'
export vcn_spoke2_sl_pubsub_secrules_ingress='[{"source":"'$myadminsrcipv4'","protocol":"6","isStateless":true,"tcpOptions":{"destinationPortRange":{"max":22,"min":22}}},{"source":"172.16.0.0/16","protocol":"1","isStateless":true}]'

vcn_spoke2_sl_pubsub=$(oci network security-list create --compartment-id $compocid --vcn-id $vcn_spoke2_ocid --display-name $vcn_spoke2_sl_pubsub_displayname --egress-security-rules $vcn_spoke2_sl_pubsub_secrules_egress --ingress-security-rules $vcn_spoke2_sl_pubsub_secrules_ingress)
export vcn_spoke2_sl_pubsub_ocid=$(echo $vcn_spoke2_sl_pubsub | jq -r .data.id)
echo vcn_spoke2_sl_pubsub_ocid=$vcn_spoke2_sl_pubsub_ocid >> output.log

#Assign PubSub-SL to Subnet1 
oci network subnet update --subnet-id $vcn_spoke2_subnet1_ocid --security-list-ids '["'$vcn_spoke2_sl_pubsub_ocid'"]' --force

####  VCN ROUTE TABLE (PUBLIC SUBNET - VCN SPOKE 2)  ####

#GET Default RT (VCN SPOKE 2) 
vcn_spoke2_rt_default=$(oci network route-table list --compartment-id $compocid --vcn-id $vcn_spoke2_ocid) 
export vcn_spoke2_rt_default_ocid=$(echo $vcn_spoke2_rt_default | jq .data | jq -r '.[] | ."id"')
echo vcn_spoke2_rt_default_ocid=$vcn_spoke2_rt_default_ocid >> output.log

#VCN SPOKE2 Route Table Creation (Public-Subnet-RT)
export vcn_spoke2_rt_pubsub_displayname="Public_Subnet_RT"

vcn_spoke2_rt_pubsub=$(oci network route-table create --compartment-id $compocid --vcn-id $vcn_spoke2_ocid --display-name $vcn_spoke2_rt_pubsub_displayname --route-rules '[{"cidrBlock":"0.0.0.0/0","networkEntityId":"'$vcn_spoke2_ig_ocid'","description":"Default route to Internet"},{"cidrBlock":"10.0.0.0/8","networkEntityId":"'$drg1_ocid'","description":"RFC1918"},{"cidrBlock":"172.16.0.0/12","networkEntityId":"'$drg1_ocid'","description":"RFC1918"},{"cidrBlock":"192.168.0.0/16","networkEntityId":"'$drg1_ocid'","description":"RFC1918"}]')
export vcn_spoke2_rt_pubsub_ocid=$(echo $vcn_spoke2_rt_pubsub | jq -r .data.id)
echo vcn_spoke2_rt_pubsub_ocid=$vcn_spoke2_rt_pubsub_ocid >> output.log

#Assign PubSub-RT to Subnet1
oci network subnet update --subnet-id $vcn_spoke2_subnet1_ocid --route-table-id $vcn_spoke2_rt_pubsub_ocid


####  DRG ROUTE TABLE (FC ATTACH)  ####

#Create FastConnect DRG-RT and DRG-RD

export drg1_rd_fc_displayname="DRG_IRD_FC-RPC-IPSEC"
export drg1_rt_fc_displayname="DRG_RT_FC-RPC-IPSEC"
export drg1_rd_fc_statements='[{"action":"ACCEPT","matchCriteria":[{"drgAttachmentId":"'$drg1_attach_sharedvcn_ocid'","matchType":"DRG_ATTACHMENT_ID"}],"priority":"1"}]'

#DRG Route Distribution Creation (DRG-RD-FC) 
drg1_rd_fc=$(oci network drg-route-distribution create --distribution-type "IMPORT" --drg-id $drg1_ocid --display-name $drg1_rd_fc_displayname)
export drg1_rd_fc_ocid=$(echo $drg1_rd_fc | jq -r .data.id)
echo drg1_rd_fc_ocid=$drg1_rd_fc_ocid >> output.log

#DRG Route Distribution Statement Creation (DRG-RD-FC)
drg1_rd_fc_stat=$(oci network drg-route-distribution-statement add --route-distribution-id $drg1_rd_fc_ocid --statements $drg1_rd_fc_statements)
#drgrdspokestat=$(oci network drg-route-distribution-statement add --route-distribution-id $drgrdspokeocid --statements '[{"action":"ACCEPT","matchCriteria":[{"drgAttachmentId":"'$drgattachocid'","matchType":"DRG_ATTACHMENT_ID"}],"priority":"1"}]')
export drg1_rd_fc_stat_id=$(echo $drg1_rd_fc_stat | jq .data | jq -r '.[] | ."id"')
echo drg1_rd_fc_stat_id=$drg1_rd_fc_stat_id >> output.log

#DRG Route Table Creation (DRG-RT-FC)
#drgrtfc=$(oci network drg-route-table create --drg-id $drgocid --display-name $drgfcrtname --import-route-distribution-id $drgrdfcocid --wait-for-state AVAILABLE --wait-interval-seconds 1)
drg1_rt_fc=$(oci network drg-route-table create --drg-id $drg1_ocid --display-name $drg1_rt_fc_displayname --wait-for-state AVAILABLE --wait-interval-seconds 1)
export drg1_rt_fc_ocid=$(echo $drg1_rt_fc | jq -r .data.id)
echo drg1_rt_fc_ocid=$drg1_rt_fc_ocid >> output.log

export vcn_spoke1_cidrs_norm=$(echo $vcn_spoke1_cidrs | sed 's/^..//' | sed 's/..$//')
export vcn_spoke2_cidrs_norm=$(echo $vcn_spoke2_cidrs | sed 's/^..//' | sed 's/..$//')
oci network drg-route-rule add --drg-route-table-id $drg1_rt_fc_ocid --route-rules '[{"destination":"'$vcn_spoke1_cidrs_norm'","destinationType":"CIDR_BLOCK","nextHopDrgAttachmentId":"'$drg1_attach_sharedvcn_ocid'","routeType":"STATIC"},{"destination":"'$vcn_spoke2_cidrs_norm'","destinationType":"CIDR_BLOCK","nextHopDrgAttachmentId":"'$drg1_attach_sharedvcn_ocid'","routeType":"STATIC"}]'

#Set DRG_RT_FC as default for VC, IPSEC, RPC
oci network drg update --drg-id $drg1_ocid --default-drg-route-tables '{"virtual-circuit":"'$drg1_rt_fc_ocid'","ipsec-tunnel":"'$drg1_rt_fc_ocid'","remote-peering-connection":"'$drg1_rt_fc_ocid'"}' --force

####  UPDATE DRG RT ATTACH  ####

#export drgsharedrdstats='[{"action":"ACCEPT","matchCriteria":[{"attachmentType":"VCN","matchType":"DRG_ATTACHMENT_TYPE"}],"priority":"1"}]'
#--->
#export drg1_rd_sharedvcn_statements_post='[{"action":"ACCEPT","matchCriteria":[{"drgAttachmentId":"'$drg1_attach_spoke2_ocid'","matchType":"DRG_ATTACHMENT_ID"}],"priority":"2"},{"action":"ACCEPT","matchCriteria":[{"drgAttachmentId":"'$drg1_attach_spoke1_ocid'","matchType":"DRG_ATTACHMENT_ID"}],"priority":"1"}]'

#drg1_rd_sharedvcn_stat_post=$(oci network drg-route-distribution-statement add --route-distribution-id $drg1_rd_sharedvcn_ocid --statements $drg1_rd_sharedvcn_statements_post)
#export drg1_rd_sharedvcn_stat_post_id=$(echo $drg1_rd_sharedvcn_stat_post | jq .data | jq -r '.[] | ."id"')


####  SPOKE 1 VM  ####

# VM SPOKE1 Creation
# oci iam availability-domain list
#export ad="fyxu:eu-amsterdam-1-AD-1"
#export imageocid="ocid1.image.oc1.eu-amsterdam-1.aaaaaaaazfzdd7xsbfnojjdnwul4zm4hwzb2ulja3ln6o7bglf4n6nfb3dma"
#export vmshape="VM.Standard.E2.1"
export vmspoke1name="VM-SPOKE-1"

spoke1vm=$(oci compute instance launch --compartment-id $compocid --availability-domain $ad --display-name $vmspoke1name --image-id $imageocid --shape $vmshape --subnet-id $vcn_spoke1_subnet1_ocid --skip-source-dest-check false --assign-public-ip true --ssh-authorized-keys-file "${ssh_auth_keys_file}")
export vmspoke1ocid=$(echo $spoke1vm | jq -r .data.id)
echo vmspoke1ocid=$vmspoke1ocid >> output.log


####  SPOKE 2 VM  ####

# VM SPOKE2 Creation
# oci iam availability-domain list
#export ad="fyxu:eu-amsterdam-1-AD-1"
#export imageocid="ocid1.image.oc1.eu-amsterdam-1.aaaaaaaazfzdd7xsbfnojjdnwul4zm4hwzb2ulja3ln6o7bglf4n6nfb3dma"
#export vmshape="VM.Standard.E2.1"
export vmspoke2name="VM-SPOKE-2"

spoke2vm=$(oci compute instance launch --compartment-id $compocid --availability-domain $ad --display-name $vmspoke2name --image-id $imageocid --shape $vmshape --subnet-id $vcn_spoke2_subnet1_ocid --skip-source-dest-check false --assign-public-ip true --ssh-authorized-keys-file "${ssh_auth_keys_file}")
export vmspoke2ocid=$(echo $spoke2vm | jq -r .data.id)
echo vmspoke2ocid=$vmspoke2ocid >> output.log

date >> output.log
rm -f sshkeyfile.pub
rm -f cloudinit_nva.sh

echo #--------------------------------------------------
cat output.log
echo #--------------------------------------------------
