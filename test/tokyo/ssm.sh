# usage: ssm.sh 'shell commands'  -> runs on runner as root, prints output
source "$(dirname "$0")/creds.sh"; source "$(dirname "$0")/env.sh"
CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript --timeout-seconds 900 --parameters "$(python3 -c 'import json,sys;print(json.dumps({"commands":[sys.argv[1]],"executionTimeout":["900"]}))' "$1")" --query Command.CommandId --output text)
for i in $(seq 1 120); do
  S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query Status --output text 2>/dev/null)
  case $S in Success|Failed|Cancelled|TimedOut) break;; esac; sleep 5
done
aws ssm get-command-invocation --command-id $CID --instance-id $IID --query '[Status,StandardOutputContent,StandardErrorContent]' --output text
