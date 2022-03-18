# oci_hub-and-spoke_nva_drgv2



export compocid="ocid1.compartment.oc1..axxxx"

export ssh_public_key="ssh-rsa AAAABabcdefghij"

export myadminsrcipv4="0.0.0.0/0"

----------------------------------------------------
Deployment :

wget https://raw.githubusercontent.com/BaptisS/oci_hub-and-spoke_nva_drgv2/main/has_nva_v1.sh

chmod +x has_nva_v1.sh

./has_nva_v1.sh

----------------------------------------------------

Cleanup : 

wget https://raw.githubusercontent.com/BaptisS/oci_hub-and-spoke_nva_drgv2/main/cleanup.sh

chmod +x cleanup.sh

./cleanup.sh




