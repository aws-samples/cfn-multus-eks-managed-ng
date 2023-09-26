# Multus-ready Amazon EKS Managed Node Group 

## Related references

Please find further detail on Multus support in EKS for baseline information. 

[1] https://aws.amazon.com/blogs/containers/amazon-eks-now-supports-multus-cni/ 

[2] https://github.com/aws-samples/eks-install-guide-for-multus

[3] https://github.com/aws-samples/eks-automated-ipmgmt-multus-pods

In the above guiding documents, the "self-managed" nodegroup (as opposed to Amazon EKS managed-nodegroup) is being used. However, this GitHub guide is intended to show how we can apply similar techniques to EKS managed nodegroups. For more information about the differences between a self-managed nodegroup and an EKS-managed nodegroup, please refer to the following [link](https://docs.aws.amazon.com/eks/latest/userguide/eks-compute.html).



## Introduction

This AWS sample repository is a guide on how to implement Multus-ready EKS-managed node group using 2 different ways; 1/ Amazon Lambda Function (similar to the previous self-managed nodegroup case) and EC2 resource tag and 2/ EC2 userData (without using a Lambda ).  Each method has a pros and cons (analyzed in sections followed), so you can select either of option according to your environment and requirement. 

### Prerequisites

* To start exploring each option, you have to have proper VPC and EKS environment in your AWS account. The sample environment can be created by running CloudFormation stack creationg using  `vpc-infra.yaml` from the template folder.
* This CFN creates below environment and AWS VPC resources (subnets, route tables, EKS cluster, IGW, NAT-GW ) along with EKS cluster.  
* As guided in [2] (https://github.com/aws-samples/eks-install-guide-for-multus/blob/main/cfn/templates/nodegroup/README.md), you have to consider clear separation between multus interface(ENI)'s primary IP address space and Pods' multus IP address space. This will be further explained in each approach section of below.  

![EksMngInfra.drawio](./image/EksMngInfra.drawio.png)

Figure 1. environment created by vpc-infra.yaml CloudFormation



## Approach 1: Using Lambda and EC2 Resource Tag

This is similar to the original approach of self-managed node group that uses Lambda function[1,2]. 

### How it works 

1. This artifact uses EventBridge event rule for LifeCycleHook action (`instant-launching`) to trigger Lambda function. 
2. In Lambda function, it looks up `Tag` of each node, whether to proceed to attach multus ENI or not. 
   * This Lambda supports 2 AZs (as an example, but you can add more AZ support) and multiple subnets from each AZ. This Lambda is inherited from previous [GitHub repo](https://github.com/raghs-aws/eks-install-guide-for-multus/blob/main/cfn/templates/nodegroup/lambda_function.zip).
3. If a node has a matching EC2 resource `Tag`, then first it looks up AZ of primary K8s interface. Based on this result, it takes one of the list for multus-subnet (between 2 lists defined for 2 AZs), and attaches interfac(es) from chosen list of subnet(s). 
4. Afterward action is identical to original Lambda function created in https://github.com/aws-samples/cfn-nodegroup-for-multus-cni/blob/main/lambda/lambda_function.py Also, like previous raghs-aws@'s [work](https://github.com/raghs-aws/eks-install-guide-for-multus/blob/main/cfn/templates/nodegroup/lambda_function.zip), it supports enhanced logic for IP assignment to multus interface so as to start assigning the available one closest to start address (e.g. from 10.0.4.4/24, 10.0.4.5/24, 10.0.4.6/24... in case of 10.0.4.0/24 subnet)

### Considerations on Approach1

Approach1 supports various patterns of ASG deployment - 1/ ASG confined within one AZ (same as self-managed node group) and 2/ ASG spanning across multiple AZ. 

* **Pattern1** - Node Group within one AZ. (please refer to Figure 2.)
  * In this case, you can use `eks.amazonaws.com/nodegroup=NODE_GROUP_NAME` , as a nodeSelector to place pod to a dedicated MNG. 
* **Pattern2** - Node Group spanning across multi-AZs (refer to Figure 3.)
  * In this case, you can use `topology.kubernetes.io/zone=YOUR_EC2_AZ` as a nodeSelector to place a pod to the AZ where you configure NetworkAttachmentDefinition along with subnets of the AZ. 
  * In addition, You can configure floating service(virtual) IP (VIP) for the multus interface across 2 AZs as guided in this [GitHub  repo](https://github.com/aws-samples/eks-nonintrusive-automated-ipmgmt-multus-pods). 
  * In this model, you have to give 2 lists of multus-subnets (for each AZ) when you run the CFN for Lambda, and then you have to create EKS MNG over 2 subnets (one each from one AZ). 

![EksMngInfra-final-config.drawio](./image/EksMngInfra-final-config-2ngs.drawio.png)

Figure 2. Approach1-Deployment Pattern1, a node group at each AZ

![EksMngInfra-final-config.drawio](./image/EksMngInfra-final-config-1ng.drawio.png)

Figure 3. Approach1-Deployment Pattern2, a node group spanning across multi-AZs

* Pros & Cons of Approach1:
  * Pros:
    * Also as aforementioned, Approach1 supports 2 patterns of deployment, especially it supports a node group spanning across AZs. 
    * Because Approach1 uses same Lambda function with [2], both of options (option1 and option2) in [the link](https://github.com/aws-samples/eks-install-guide-for-multus/blob/main/cfn/templates/nodegroup/README.md) are available. (Lambda in this GitHub supports `useIPsFromStartOfSubnet: true` through the CFN creation). Likewise, Lambda generally gives more flexible options to add/modify other capabilities than Approach2 of using userData. 
  * Cons:
    * This uses a Lambda function which requires additional cost (comparing to Approach2). 



## Approach 2. Using userData without Lambda

This is inspired by another *coming-soon* project (*Karpenter for Multus worker*) - big thanks to contributors of this project. Idea is to implement API calls for ENI attachment inside of the [userData](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html) of EC2. 

### How it works

 At the instantiation of an EKS worker EC2, it carries out shell-script in the userData including ENI attachment before kubelet comes effective. Inside of this shell-script, EC2 retrieves multus subnet ID and security group ID (from the resource Tag definition) from API and metadata, and calls appropriate API sets (create/attach ENI) to the EC2 instance. 

### Considerations on Approach2

Unlikely to Approach1, this approach2 doesn't work for the case when an EKS worker node group needs to span across multi-AZs, and this only works for the case when the node group is confined wihtin one AZ. Also to avoid conflict between IP assignment from EC2 for the primary IP of ENI and multus Pod's IP address from K8s, you can only use option2 of [the link](https://github.com/aws-samples/eks-install-guide-for-multus/blob/main/cfn/templates/nodegroup/README.md). (you have to use VPC CIDR reservation). 

* Pros & Cons of Approach1:

  * Pros:
    * This doesn't require Lambda (no cost of Lambda). It is simple and straighforward to use.

  * Cons:

    * It doesn't support the deployment pattern for a node group to span across multi-AZs.  
    * It has less programmability than Lambda based approach. 

    

## License 

This library is licensed under the MIT-0 License. See the LICENSE file.



## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.


## Usage 

### Steps for Approach1 

1. Create environment using `vpc-infra.yaml` or you can use your existing environment (VPC and EKS cluster). 

2. Create a S3 bucket to store Lambda code. 

3. Find `upload-lambda.sh` from Lambda directory. After you give excutable permission to this shell script, run this with your S3 bucket name.

   `````
   ./upload-lambda.sh crosscom-my-lambda
   `````

   This script will make zip file of `lambda_function.py` and upload it to your own S3 bucket. Please make sure you are running this shell script in the machine where you have a S3 access permission. Shell sciprt generates zip file as default name of  `eks-mng-multus-lambda.zip` (but you can change file name if you want by editing the shell script). You have to use this s3 bucket name and s3 key name while you create Lambda by CFN in step 4.

4. Create LaunchTemplate using the CFN of `eks-mng-lct.yaml`. You have to select your own 'tag' which has to be matching to the one you will give in Lambda creation of step 4.

   * You can define instance type/size, ssh key pair, and tag for each node. 

   * Among parameters, the `MultusTriggerTagKey` is the most important, since Lambda is attaching additoinal multus interfaces to the worker node based on matching this resource Tag information. 

5. Create Lambda using the CFN of `amazon-lambda-for-eksmng-multus.yaml`.
   * *MultusSbunetsAz1* - list of subnets to create multus interfaces at AZ1. 
   * *MultusSbunetsAz2* - list of subnets to create multus interfaces at AZ2. 
   * *MultusSecurityGroupIds* - Security Group (or list of Security Groups) applied to multus interface(s).
   * *EksNodeGroupTagKey* - Tag Key that will trigger Lambda AttachENI action. (e.g. `multus-ng`).
   * *LambdaS3Bucket* - S3 bucket name where `eks-mng-multus-lambda.zip` is uploaded.
   * *LambdaS3Key* - Lambda file name (e.g. `eks-mng-multus-lambda.zip` unless you didn't change it).
   * *useIPsFromStartOfSubnet* - whether to use IP assignment logic of Lambda (to start from smaller number available in the subnet). 
   * *MultusInterfaceTags* - This is optional, if you want to add a Tag to the multus interface (e.g. with CNF name).  

6. Create NodeGroup from EKS console or CLI using LauncthTemplate created by step 3. 

   * In Amazon EKS console, go to your EKS cluster. And then select **Compute** section and then click **Add node group** to create an EKS managed node group. 

   * At *Configure node group*, enable to use *Launch Template*, and select LauncTemplate created by  `eks-mng-lct.yaml`. 
   * In *Sepcify networking* section, please select only primary K8s network subnet(s) for *Subnets*. (Multus subnets will be picked up by Lambda (input by CFN parameters in step 5)).



### Steps for Approach2

1. Create environment using `vpc-infra.yaml` or you can use your existing environment (VPC and EKS cluster). 
2. (Optional) It is recommended to reserve IPs for multus Pods using below commands (this is the case to reserve 10.0.4.129\~254, 10.0.6.129\~254 ranges for using multus Pod IP addresses).

````
aws ec2 create-subnet-cidr-reservation --subnet-id [YOUR_MULTUS_SUBNET1] --cidr 10.0.4.128/25 --reservation-type explicit
aws ec2 create-subnet-cidr-reservation --subnet-id [YOUR_MULTUS_SUBNET2] --cidr 10.0.6.128/25 --reservation-type explicit
````
3. Through the CloudFormation console, create a LaunchTeamplte using `eks-mng-lct-userdata.yaml`. This CFN template would create LaunchTemplate for the EKS managed nodegroup. 
   * You can define instance type/size, ssh key pair, and tag for each node. 
   * *MultusSubnets* - list of subnets to create multus interfaces from. 
   * *MultusSecurityGroupIds* - Security Group (or list of Security Groups) applied to multus interface(s). Note that, the number of MultusSecurityGroupIds doesn't match with number of MultusSubnets you selected, then only the first Security Group will be used for all Multus subnets listed. If you want to implement each individual Security Group for each Multus subnet, then you have to match selected numbers of Security Groups and Multus Subnets.

   JFYI, LaunchTemplate CFN has a specific userData to create ENI(s) and attach it to the instance before kubelet runs. 
````
UserData:
Fn::Base64: !Sub 
- |
  Content-Type: multipart/mixed; boundary="==BOUNDARY=="
  MIME-Version: 1.0

  --==BOUNDARY==
  Content-Type: text/x-shellscript; charset="us-ascii"
  #!/bin/bash
  set -o xtrace
  # List your multus subnets and Security Group
  subnetids="${SubnetIds}"
  secgrpids="${SecGrpIds}"
  IFS=' ' read -ra subnetList <<< "$subnetids"
  IFS=' ' read -ra secGrpList <<< "$secgrpids"
  subnetListLen=${!#subnetList[@]}
  secGrpListLen=${!#secGrpList[@]}

  # If just one security group is defined, then use it for every subnet
  if [ $subnetListLen != $secGrpListLen ]; then
      x=0
      for subnet in "${!subnetList[@]}";
      do
          secGrpList[${!x}]="${!secGrpList[0]}"
          x=$((x+1))
      done
  fi 

  # create and attach multus interfaces as requested
  n=0
  for subnetId in "${!subnetList[@]}";
  do
      secGrpId="${!secGrpList[n]}" 
      ### Get ipv6 cidr if any
      subnetipv6=`aws ec2 describe-subnets --subnet-ids ${!subnetId}\
      --query "Subnets[*].Ipv6CidrBlockAssociationSet[*].Ipv6CidrBlock" --output text`

      ### Create and attach interfaces, multus subnets and security groups are identified using tag Name:Value, 
      ### checks if subnet has IPV6 if true provisioned ENI with IPv6 else only IPv4
      if [ -n "$subnetipv6" ]; then
          multusId=$(aws ec2 create-network-interface --subnet-id ${!subnetId} \
          --description "VRF$((n+1))" --groups ${!secGrpId} --ipv6-address-count 1 \
          --tag-specifications "ResourceType="network-interface",\
          Tags=[{Key="node.k8s.amazonaws.com/no_manage",Value="true"}]" | jq -r '.NetworkInterface.NetworkInterfaceId');
      else
          multusId=$(aws ec2 create-network-interface --subnet-id ${!subnetId} \
          --description "VRF$((n+1))" --groups ${!secGrpId} \
          --tag-specifications "ResourceType="network-interface",\
          Tags=[{Key="node.k8s.amazonaws.com/no_manage",Value="true"}]" | jq -r '.NetworkInterface.NetworkInterfaceId');
      fi

      ### Attach the multus interface to EC2 worker, adjust device-index incrementally for every new attachment
      attachmentId=$(aws ec2 attach-network-interface --network-interface-id ${!multusId} \
      --instance-id `curl -s http://169.254.169.254/latest/meta-data/instance-id` \
      --output text --device-index $((n+1 )) )
      aws ec2 modify-network-interface-attribute --network-interface-id ${!multusId} --no-source-dest-check
      aws ec2 modify-network-interface-attribute --attachment "AttachmentId"="${!attachmentId}","DeleteOnTermination"="True" \
      --network-interface-id ${!multusId}
      n=$((n+1))
  done
  echo "net.ipv4.conf.default.rp_filter = 0" | tee -a /etc/sysctl.conf
  echo "net.ipv4.conf.all.rp_filter = 0" | tee -a /etc/sysctl.conf
  sudo sysctl -p
  ls /sys/class/net/ > /tmp/ethList;cat /tmp/ethList |while read line ; do sudo ifconfig $line up; done
  grep eth /tmp/ethList |while read line ; do echo "ifconfig $line up" >> /etc/rc.d/rc.local; done
  systemctl enable rc-local
  chmod +x /etc/rc.d/rc.local

  # For kubelet arg input
  cat << EOF > /etc/systemd/system/kubelet.service.d/90-kubelet-extra-args.conf
  [Service]
  Environment='USERDATA_EXTRA_ARGS=${KubeletExtraArguments}'
  EOF
   # this kubelet.service update is for the version below than EKS 1.24 (e.g. up to 1.23)
  # but still you can keep the line even if you use EKS 1.24 or higher
  sed -i 's/KUBELET_EXTRA_ARGS/KUBELET_EXTRA_ARGS $USERDATA_EXTRA_ARGS/' /etc/systemd/system/kubelet.service
  # this update is for the EKS 1.24 or higher.
  sed -i 's/KUBELET_EXTRA_ARGS/KUBELET_EXTRA_ARGS $USERDATA_EXTRA_ARGS/' /etc/eks/containerd/kubelet-containerd.service
  --==BOUNDARY==--

- SubnetIds: !Join [ " ", !Ref MultusSubnets ]
  SecGrpIds: !Join [ " ", !Ref MultusSecurityGroupIds ]
````

4. In Amazon EKS console, go to your EKS cluster. And then select **Compute** section and then click **Add node group** to create an EKS managed node group. 
   * At *Configure node group*, enable to use *Launch Template*, and select LauncTemplate created by  `eks-mng-lct-userdata.yaml`. 
   * In *Sepcify networking* section, please select only primary K8s network subnet(s) for *Subnets*. (Multus subnets will be picked up by userData (using resource tag name of the subnet)).
