#!/bin/sh

export compocid="ocid1.compartment.oc1..axxxx"
export vcncidrs='["172.16.100.0/24"]'
export subnet1cidr="172.16.100.0/27"
export vcndisplayname="SHARED_VCN"
export dnslabel="sharedvcn"
export subnetname="Public_Subnet_1"
export drgattachname="DRG_ATTACH_SHARED_VCN"
export drgname="HUB_DRG"
export drgsharedrdname="DRG_RD_SHARED_VCN"
export drgsharedrtname="DRG_RT_SHARED_VCN"
#export drgsharedrdstats='[{"action":"ACCEPT","matchCriteria":[{"attachmentType":"VCN","matchType":"DRG_ATTACHMENT_TYPE"}],"priority":"1"}]'
export drgsharedrdstats='[{"action":"ACCEPT","matchCriteria":[],"priority":"1"}]'
export sharedvcnrtdrgname="DRG-ATTACH-RT"

#SHARED VCN 
#VCN Creation
vcn=$(oci network vcn create --compartment-id $compocid --cidr-blocks $vcncidrs --display-name $vcndisplayname --dns-label $dnslabel)
export vcnocid=$(echo $vcn | jq -r .data.id)
echo SHARED VCN OCID : $vcnocid

#Subnet Creation
subnet=$(oci network subnet create --cidr-block $cidr_block $subnet1cidr --compartment-id $compocid --vcn-id $vcnocid --display-name $subnetname --prohibit-public-ip-on-vnic false)
export subnetocid=$(echo $subnet | jq -r .data.id)
echo SHARED Subnet OCID : $vcnocid

#Internet Gateway Creation
ig=$(oci network internet-gateway create --compartment-id $compocid --vcn-id $vcnocid --display-name "IGW" --is-enabled "true")
export igocid=$(echo $ig | jq -r .data.id)
echo SHARED IG OCID : $igocid

#DRG Creation
drg=$(oci network drg create --compartment-id $compocid --display-name $drgname --wait-for-state AVAILABLE --wait-interval-seconds 1)
export drgocid=$(echo $drg | jq -r .data.id)
echo HUB DRG OCID : $drgocid

#------------------------------------------------------

# NVA Creation
# oci iam availability-domain list
export ad="fyxu:eu-amsterdam-1-AD-1"
export imageocid="ocid1.image.oc1.eu-amsterdam-1.aaaaaaaazfzdd7xsbfnojjdnwul4zm4hwzb2ulja3ln6o7bglf4n6nfb3dma"
export vmshape="VM.Standard.E2.1"
export vmname="NVA-VM-1"
vm=$(oci compute instance launch --compartment-id $compocid --availability-domain $ad --display-name $vmname --image-id $imageocid --shape $vmshape --subnet-id $subnetocid --skip-source-dest-check true --assign-public-ip true)
export vmocid=$(echo $vm | jq -r .data.id)
echo NVA VM OCID : $privipocid

sleep 10

vnicattach=$(oci compute vnic-attachment list --compartment-id $compocid --instance-id $vmocid)
export vnicocid=$(echo $vnicattach | jq .data | jq -r '.[] | ."vnic-id"')
privip=$(oci network private-ip list --vnic-id $vnicocid)
export privipocid=$(echo $privip | jq .data | jq -r '.[] | ."id"')
echo NVA VNIC OCID : $privipocid

#------------------------------------------------------

#DRG Route Distribution Creation (Shared VCN) 
drgrdshared=$(oci network drg-route-distribution create --distribution-type "IMPORT" --drg-id $drgocid --display-name $drgsharedrdname)
export drgrdsharedocid=$(echo $drgrdshared | jq -r .data.id)

#DRG Route Distribution Statement Creation 
drgrdsharedstat=$(oci network drg-route-distribution-statement add --route-distribution-id $drgrdsharedocid --statements $drgsharedrdstats)
export drgrdsharedstatid=$(echo $drgrdsharedstat | jq .data | jq -r '.[] | ."id"')

#DRG Route Table Creation (Shared VCN)
drgrtshared=$(oci network drg-route-table create --drg-id $drgocid --display-name $drgsharedrtname --import-route-distribution-id $drgrdsharedocid --wait-for-state AVAILABLE --wait-interval-seconds 1)
export drgrtsharedocid=$(echo $drgrtshared | jq -r .data.id)

#VCN Route Table Creation (Shared VCN DRG-ATTACH-RT)
#sharedvcnrtdrg=$(oci network route-table create --compartment-id $compocid --vcn-id $vcnocid --display-name $sharedvcnrtdrgname --route-rules '[{"cidrBlock":"10.0.0.0/8","networkEntityId":"ocid1.internetgateway.oc1.phx.aaaaaaaaxtfqb2srw7hoi5cmdum4n6ow2xm2zhrzqqypmlteiiebtmvl75ya"}]')
sharedvcnrtdrg=$(oci network route-table create --compartment-id $compocid --vcn-id $vcnocid --display-name $sharedvcnrtdrgname --route-rules '[{"cidrBlock":"10.0.0.0/8","networkEntityId":"'$privipocid'"},{"cidrBlock":"172.16.0.0/12","networkEntityId":"'$privipocid'"},{"cidrBlock":"192.168.0.0/16","networkEntityId":"'$privipocid'"}]')
export sharedvcnrtdrgocid=$(echo $sharedvcnrtdrg | jq -r .data.id)

#DRG Attachment
drgattach=$(oci network drg-attachment create --drg-id $drgocid --display-name $drgattachname --drg-route-table-id $drgrtsharedocid --route-table-id $sharedvcnrtdrgocid --vcn-id $vcnocid --wait-for-state ATTACHED --wait-interval-seconds 1)
export drgattachocid=$(echo $drgattach | jq -r .data.id)

export drgspokesrdname="DRG_RD_SPOKES_VCN"
export drgspokesrtname="DRG_RT_SPOKES_VCN"
export drgspokesrdstats='[{"action":"ACCEPT","matchCriteria":[{"drgAttachmentId":"'$drgattachocid'","matchType":"DRG_ATTACHMENT_ID"}],"priority":"1"}]'

#DRG Route Distribution Creation (SPOKE VCN) 
drgrdspoke=$(oci network drg-route-distribution create --distribution-type "IMPORT" --drg-id $drgocid --display-name $drgspokesrdname)
export drgrdspokeocid=$(echo $drgrdspoke | jq -r .data.id)

#DRG Route Distribution Statement Creation (SPOKE VCN)
drgrdspokestat=$(oci network drg-route-distribution-statement add --route-distribution-id $drgrdspokeocid --statements $drgspokesrdstats)
#drgrdspokestat=$(oci network drg-route-distribution-statement add --route-distribution-id $drgrdspokeocid --statements '[{"action":"ACCEPT","matchCriteria":[{"drgAttachmentId":"'$drgattachocid'","matchType":"DRG_ATTACHMENT_ID"}],"priority":"1"}]')
export drgrdspokestatid=$(echo $drgrdspokestat | jq .data | jq -r '.[] | ."id"')

#DRG Route Table Creation (SPOKE VCN)
drgrtspoke=$(oci network drg-route-table create --drg-id $drgocid --display-name $drgspokesrtname --import-route-distribution-id $drgrdspokeocid --wait-for-state AVAILABLE --wait-interval-seconds 1)
export drgrtspokeocid=$(echo $drgrtspoke | jq -r .data.id)

#Set DRG_RT_SPOKES as default for VCNs
oci network drg update --drg-id $drgocid --default-drg-route-tables '{"vcn":"'$drgrtspokeocid'"}' --force

#------------------------------------------------------------------------------

#SPOKE VCN 1 
export sp1vcncidrs='["172.16.101.0/24"]'
export sp1subnet1cidr="172.16.101.0/27"
export sp1vcndisplayname="SPOKE_VCN_1"
export sp1dnslabel="spokevcn1"
export sp1drgattachname="DRG_ATTACH_SPOKE_VCN_1"

#VCN Creation
sp1vcn=$(oci network vcn create --compartment-id $compocid --cidr-blocks $sp1vcncidrs --display-name $sp1vcndisplayname --dns-label $sp1dnslabel)
export sp1vcnocid=$(echo $sp1vcn | jq -r .data.id)
echo SPOKE VCN 1 OCID : $sp1vcnocid

#Subnet Creation
sp1subnet=$(oci network subnet create --cidr-block $sp1subnet1cidr --compartment-id $compocid --vcn-id $sp1vcnocid --prohibit-public-ip-on-vnic false)
export sp1subnetocid=$(echo $sp1subnet | jq -r .data.id)
echo SPOKE 1 Subnet 1 OCID : $sp1subnetocid

#Internet Gateway Creation
sp1ig=$(oci network internet-gateway create --compartment-id $compocid --vcn-id $sp1vcnocid --display-name "IGW" --is-enabled "true")
export sp1igocid=$(echo $sp1ig | jq -r .data.id)
echo SPOKE 1 IG OCID : $sp1igocid

#DRG Attachment
sp1drgattach=$(oci network drg-attachment create --drg-id $drgocid --display-name $sp1drgattachname --vcn-id $sp1vcnocid)
export sp1drgattachocid=$(echo $sp1drgattach | jq -r .data.id)

#------------------------------------------------
#SPOKE VCN 2
 
export sp2vcncidrs='["172.16.102.0/24"]'
export sp2subnet1cidr="172.16.102.0/27"
export sp2vcndisplayname="SPOKE_VCN_2"
export sp2dnslabel="spokevcn2"
export sp2drgattachname="DRG_ATTACH_SPOKE_VCN_2"


#VCN Creation
sp2vcn=$(oci network vcn create --compartment-id $compocid --cidr-blocks $sp2vcncidrs --display-name $sp2vcndisplayname --dns-label $sp2dnslabel)
export sp2vcnocid=$(echo $sp2vcn | jq -r .data.id)
echo SPOKE VCN 2 OCID : $sp2vcnocid

#Subnet Creation
sp2subnet=$(oci network subnet create --cidr-block $sp2subnet1cidr --compartment-id $compocid --vcn-id $sp2vcnocid --prohibit-public-ip-on-vnic false)
export sp2subnetocid=$(echo $sp2subnet | jq -r .data.id)
echo SPOKE 2 Subnet 1 OCID : $sp2subnetocid

#Internet Gateway Creation
sp2ig=$(oci network internet-gateway create --compartment-id $compocid --vcn-id $sp2vcnocid --display-name "IGW" --is-enabled "true")
export sp2igocid=$(echo $sp2ig | jq -r .data.id)
echo SPOKE 1 IG OCID : $sp2igocid

#DRG Attachment
sp2drgattach=$(oci network drg-attachment create --drg-id $drgocid --display-name $sp2drgattachname --vcn-id $sp2vcnocid)
export sp2drgattachocid=$(echo $sp2drgattach | jq -r .data.id)

#------------------------------------------------
#Create FastConnect DRG-RT and DRG-RD

export drgfcrdname="DRG_RD_FC_VCN"
export drgfcrtname="DRG_RT_FC_VCN"
export drgfcrdstats='[{"action":"ACCEPT","matchCriteria":[{"drgAttachmentId":"'$drgattachocid'","matchType":"DRG_ATTACHMENT_ID"}],"priority":"1"}]'

#DRG Route Distribution Creation (DRG-RD-FC) 
drgrdfc=$(oci network drg-route-distribution create --distribution-type "IMPORT" --drg-id $drgocid --display-name $drgfcrdname)
export drgrdfcocid=$(echo $drgrdfc | jq -r .data.id)

#DRG Route Distribution Statement Creation (DRG-RD-FC)
drgrdfcstat=$(oci network drg-route-distribution-statement add --route-distribution-id $drgrdfcocid --statements $drgfcrdstats)
#drgrdspokestat=$(oci network drg-route-distribution-statement add --route-distribution-id $drgrdspokeocid --statements '[{"action":"ACCEPT","matchCriteria":[{"drgAttachmentId":"'$drgattachocid'","matchType":"DRG_ATTACHMENT_ID"}],"priority":"1"}]')
export drgrdfcstatid=$(echo $drgrdfcstat | jq .data | jq -r '.[] | ."id"')

#DRG Route Table Creation (DRG-RT-FC)
#drgrtfc=$(oci network drg-route-table create --drg-id $drgocid --display-name $drgfcrtname --import-route-distribution-id $drgrdfcocid --wait-for-state AVAILABLE --wait-interval-seconds 1)
drgrtfc=$(oci network drg-route-table create --drg-id $drgocid --display-name $drgfcrtname --wait-for-state AVAILABLE --wait-interval-seconds 1)

export drgrtfcocid=$(echo $drgrtfc | jq -r .data.id)

oci network drg-route-rule add --drg-route-table-id $drgrtfcocid --route-rules '[{"destination":"172.16.101.0/24","destinationType":"CIDR_BLOCK","nextHopDrgAttachmentId":"'$drgattachocid'","routeType":"STATIC"},{"destination":"172.16.102.0/24","destinationType":"CIDR_BLOCK","nextHopDrgAttachmentId":"'$drgattachocid'","routeType":"STATIC"}]'

#Set DRG_RT_FC as default for VCNs
oci network drg update --drg-id $drgocid --default-drg-route-tables '{"virtual-circuit":"'$drgrtfcocid'"}' --force

