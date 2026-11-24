#!/usr/bin/env bash
# Builds linux/amd64 binary natively on a temporary t3.small (cgo/sqlite3 needs a native toolchain), smoke-tests TLS, then cleans up.
set -uo pipefail
cd "$(dirname "$0")"; source ./creds.sh
OUT=${1:-../../redis-full-check-linux-amd64}
P=rfc-x86; T="Key=Project,Value=$P"; ACC=$(aws sts get-caller-identity --query Account --output text); B=$P-$ACC
aws s3api create-bucket --bucket $B --create-bucket-configuration LocationConstraint=ap-northeast-1 >/dev/null
aws s3api put-public-access-block --bucket $B --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3 cp /tmp/rfc-src.tgz s3://$B/src.tgz --quiet; URL=$(aws s3 presign s3://$B/src.tgz --expires-in 3600)
VPC=$(aws ec2 create-vpc --cidr-block 10.78.0.0/16 --tag-specifications "ResourceType=vpc,Tags=[{$T}]" --query Vpc.VpcId --output text)
IGW=$(aws ec2 create-internet-gateway --tag-specifications "ResourceType=internet-gateway,Tags=[{$T}]" --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC
S=$(aws ec2 create-subnet --vpc-id $VPC --cidr-block 10.78.1.0/24 --tag-specifications "ResourceType=subnet,Tags=[{$T}]" --query Subnet.SubnetId --output text)
RT=$(aws ec2 create-route-table --vpc-id $VPC --tag-specifications "ResourceType=route-table,Tags=[{$T}]" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id $RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW >/dev/null
aws ec2 associate-route-table --route-table-id $RT --subnet-id $S >/dev/null
aws ec2 modify-subnet-attribute --subnet-id $S --map-public-ip-on-launch
SG=$(aws ec2 create-security-group --group-name $P --description "$P no ingress" --vpc-id $VPC --query GroupId --output text)
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)
IID=$(aws ec2 run-instances --image-id $AMI --instance-type t3.small --subnet-id $S --security-group-ids $SG --iam-instance-profile Name=ssm --metadata-options HttpTokens=required --tag-specifications "ResourceType=instance,Tags=[{$T}]" --query 'Instances[0].InstanceId' --output text)
echo "IID=$IID VPC=$VPC"
for i in $(seq 1 40); do [ "$(aws ssm describe-instance-information --filters Key=InstanceIds,Values=$IID --query 'InstanceInformationList[0].PingStatus' --output text)" = Online ] && break; sleep 10; done
cat > /tmp/x86_remote.sh <<EOS
set -ex
export HOME=/root GOCACHE=/root/.cache/go GOPATH=/root/go
dnf install -y -q golang gcc valkey openssl >/dev/null 2>&1
mkdir -p /opt/rfc && cd /opt/rfc && curl -sS -o src.tgz '$URL' && tar xzf src.tgz 2>/dev/null
cd src/full_check && go build -o /usr/local/bin/redis-full-check . && file /usr/local/bin/redis-full-check | cut -c1-120
cd /opt/rfc && openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 2 -subj "/CN=ca" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout s.key -out s.csr -subj "/CN=localhost" 2>/dev/null; echo "subjectAltName=DNS:localhost,IP:127.0.0.1" > san.ext
openssl x509 -req -in s.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out s.crt -days 2 -extfile san.ext 2>/dev/null
valkey-server --port 6400 --daemonize yes --save "" >/dev/null
valkey-server --port 0 --tls-port 6401 --tls-cert-file s.crt --tls-key-file s.key --tls-ca-cert-file ca.crt --tls-auth-clients no --daemonize yes --save "" >/dev/null; sleep 2
for i in \$(seq 1 300); do echo "SET k\$i v\$i"; done > d.cmds
valkey-cli -p 6400 < d.cmds >/dev/null; valkey-cli --tls --cacert ca.crt -p 6401 < d.cmds >/dev/null
redis-full-check -d r.db -m 1 --comparetimes 1 -s 127.0.0.1:6400 -t localhost:6401 --targettls --targettlscacert ca.crt --log f.log 2>&1 | tail -1
valkey-cli --tls --cacert ca.crt -p 6401 set k5 X >/dev/null
redis-full-check -d r.db -m 1 --comparetimes 1 -s 127.0.0.1:6400 -t localhost:6401 --targettls --targettlscacert ca.crt --log f2.log 2>&1 | tail -1
aws s3 cp /usr/local/bin/redis-full-check s3://$B/rfc-amd64 --quiet
EOS
CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript --parameters "$(python3 -c 'import json;print(json.dumps({"commands":[open("/tmp/x86_remote.sh").read()],"executionTimeout":["900"]}))')" --query Command.CommandId --output text)
for i in $(seq 1 100); do ST=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query Status --output text 2>/dev/null); case $ST in Success|Failed|Cancelled|TimedOut) break;; esac; sleep 6; done
aws ssm get-command-invocation --command-id $CID --instance-id $IID --query '[Status,StandardOutputContent,StandardErrorContent]' --output text | grep -v xattr | tail -12
aws s3 cp s3://$B/rfc-amd64 $OUT --quiet && chmod +x $OUT && echo "saved $OUT"
# cleanup
aws ec2 terminate-instances --instance-ids $IID >/dev/null; aws ec2 wait instance-terminated --instance-ids $IID
aws s3 rb s3://$B --force >/dev/null
for i in 1 2 3 4 5 6; do aws ec2 delete-security-group --group-id $SG 2>/dev/null && break; sleep 10; done
for a in $(aws ec2 describe-route-tables --route-table-ids $RT --query 'RouteTables[].Associations[].RouteTableAssociationId' --output text); do aws ec2 disassociate-route-table --association-id $a; done
aws ec2 delete-route-table --route-table-id $RT; aws ec2 delete-subnet --subnet-id $S
aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC; aws ec2 delete-internet-gateway --internet-gateway-id $IGW; aws ec2 delete-vpc --vpc-id $VPC
echo "left: vpcs=$(aws ec2 describe-vpcs --filters Name=tag:Project,Values=$P --query 'length(Vpcs)')"
