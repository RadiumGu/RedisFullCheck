# source me: loads Tokyo-account creds (retrying flaky ada helper) into env, cached 30 min
export AWS_REGION=ap-northeast-1 AWS_DEFAULT_REGION=ap-northeast-1
CF=/tmp/rfc_tls_creds.env
if [ ! -s $CF ] || [ -n "$(find $CF -mmin +30)" ]; then
  for i in 1 2 3 4 5 6; do AWS_PROFILE=aws aws configure export-credentials --format env > $CF.tmp 2>/dev/null && [ -s $CF.tmp ] && mv $CF.tmp $CF && break; sleep 4; done
fi
unset AWS_PROFILE; eval "$(cat $CF)"
