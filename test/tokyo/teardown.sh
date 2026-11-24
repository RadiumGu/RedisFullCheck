#!/usr/bin/env bash
# Deletes everything created by setup.sh (only resources recorded in env.sh / named rfc-tls-*).
set -uo pipefail
export AWS_REGION=ap-northeast-1 AWS_DEFAULT_REGION=ap-northeast-1
for i in 1 2 3 4 5; do
  if C=$(AWS_PROFILE=aws aws configure export-credentials --format env 2>/dev/null); then eval "$C"; unset AWS_PROFILE; break; fi; sleep 3
done
aws sts get-caller-identity --query Account --output text | grep -qx <ACCOUNT_ID> || { echo "wrong/no creds"; exit 1; }
cd "$(dirname "$0")"; source ./env.sh
for g in rfc-tls-r70-std rfc-tls-r70-cls rfc-tls-v90-std rfc-tls-v90-cls; do aws elasticache delete-replication-group --replication-group-id $g >/dev/null; done
aws ec2 terminate-instances --instance-ids $IID >/dev/null; aws ec2 wait instance-terminated --instance-ids $IID
for g in rfc-tls-r70-std rfc-tls-r70-cls rfc-tls-v90-std rfc-tls-v90-cls; do aws elasticache wait replication-group-deleted --replication-group-id $g; done
aws elasticache delete-cache-subnet-group --cache-subnet-group-name rfc-tls
aws ec2 delete-security-group --group-id $CSG; aws ec2 delete-security-group --group-id $EC2SG
for a in $(aws ec2 describe-route-tables --route-table-ids $RT --query 'RouteTables[].Associations[].RouteTableAssociationId' --output text); do aws ec2 disassociate-route-table --association-id $a; done
aws ec2 delete-route-table --route-table-id $RT; aws ec2 delete-subnet --subnet-id $S1; aws ec2 delete-subnet --subnet-id $S2
aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC; aws ec2 delete-internet-gateway --internet-gateway-id $IGW; aws ec2 delete-vpc --vpc-id $VPC
