#!/usr/bin/env bash
# Creates an isolated test env in Tokyo (account of AWS_PROFILE=aws). Teardown: teardown.sh
set -euo pipefail
export AWS_REGION=ap-northeast-1 AWS_DEFAULT_REGION=ap-northeast-1
for i in 1 2 3 4 5; do
  if C=$(AWS_PROFILE=aws aws configure export-credentials --format env 2>/dev/null); then eval "$C"; unset AWS_PROFILE; break; fi; sleep 3
done
ACC=$(aws sts get-caller-identity --query Account --output text) || { echo "no creds"; exit 1; }
[ -n "${EXPECTED_ACCOUNT:-}" ] && [ "$ACC" != "$EXPECTED_ACCOUNT" ] && { echo "wrong account $ACC"; exit 1; }
P=rfc-tls
T="Key=Project,Value=$P"
VPC=$(aws ec2 create-vpc --cidr-block 10.77.0.0/16 --tag-specifications "ResourceType=vpc,Tags=[{$T},{Key=Name,Value=$P}]" --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-hostnames
IGW=$(aws ec2 create-internet-gateway --tag-specifications "ResourceType=internet-gateway,Tags=[{$T}]" --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC
S1=$(aws ec2 create-subnet --vpc-id $VPC --cidr-block 10.77.1.0/24 --availability-zone ap-northeast-1a --tag-specifications "ResourceType=subnet,Tags=[{$T}]" --query Subnet.SubnetId --output text)
S2=$(aws ec2 create-subnet --vpc-id $VPC --cidr-block 10.77.2.0/24 --availability-zone ap-northeast-1c --tag-specifications "ResourceType=subnet,Tags=[{$T}]" --query Subnet.SubnetId --output text)
RT=$(aws ec2 create-route-table --vpc-id $VPC --tag-specifications "ResourceType=route-table,Tags=[{$T}]" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id $RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW >/dev/null
aws ec2 associate-route-table --route-table-id $RT --subnet-id $S1 >/dev/null
aws ec2 associate-route-table --route-table-id $RT --subnet-id $S2 >/dev/null
aws ec2 modify-subnet-attribute --subnet-id $S1 --map-public-ip-on-launch
EC2SG=$(aws ec2 create-security-group --group-name $P-ec2 --description "$P ec2 (no ingress)" --vpc-id $VPC --tag-specifications "ResourceType=security-group,Tags=[{$T}]" --query GroupId --output text)
CSG=$(aws ec2 create-security-group --group-name $P-cache --description "$P cache" --vpc-id $VPC --tag-specifications "ResourceType=security-group,Tags=[{$T}]" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $CSG --protocol tcp --port 6379 --source-group $EC2SG >/dev/null
aws elasticache create-cache-subnet-group --cache-subnet-group-name $P --cache-subnet-group-description $P --subnet-ids $S1 $S2 >/dev/null
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 --query Parameter.Value --output text)
IID=$(aws ec2 run-instances --image-id $AMI --instance-type t4g.small --subnet-id $S1 --security-group-ids $EC2SG --iam-instance-profile Name=ssm --metadata-options HttpTokens=required --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=20,VolumeType=gp3,Encrypted=true}' --tag-specifications "ResourceType=instance,Tags=[{$T},{Key=Name,Value=$P-runner}]" --query 'Instances[0].InstanceId' --output text)
AUTH=$(openssl rand -hex 16)
mk() { # id engine version cluster(0/1) pg [auth]
  local args=(--replication-group-id $1 --replication-group-description "$1" --engine $2 --engine-version $3 --cache-node-type cache.t4g.micro
    --cache-subnet-group-name $P --security-group-ids $CSG --transit-encryption-enabled --cache-parameter-group-name $5 --tags $T)
  if [ $4 = 1 ]; then args+=(--num-node-groups 1 --replicas-per-node-group 0); else args+=(--num-cache-clusters 1 --no-automatic-failover-enabled); fi
  [ -n "${6:-}" ] && args+=(--auth-token "$6")
  aws elasticache create-replication-group "${args[@]}" >/dev/null
}
mk $P-r70-std redis 7.0 0 default.redis7
mk $P-r70-cls redis 7.0 1 default.redis7.cluster.on
mk $P-v90-std valkey 9.0 0 default.valkey9 $AUTH
mk $P-v90-cls valkey 9.0 1 default.valkey9.cluster.on $AUTH
cat > env.sh <<EOT
export VPC=$VPC IGW=$IGW S1=$S1 S2=$S2 RT=$RT EC2SG=$EC2SG CSG=$CSG IID=$IID
export VALKEY_AUTH=$AUTH
EOT
chmod 600 env.sh
echo "created; env.sh written"
