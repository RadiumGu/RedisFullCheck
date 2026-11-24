#!/usr/bin/env bash
# Runs ON the Tokyo runner. Needs: VALKEY_AUTH, redis-full-check, valkey-cli, python3.
set -uo pipefail
W=/opt/rfc/work; mkdir -p $W; cd $W
H_R70_STD=master.rfc-tls-r70-std.xxxxxx.apne1.cache.amazonaws.com
H_R70_CLS=clustercfg.rfc-tls-r70-cls.xxxxxx.apne1.cache.amazonaws.com
H_V90_STD=master.rfc-tls-v90-std.xxxxxx.apne1.cache.amazonaws.com
H_V90_CLS=clustercfg.rfc-tls-v90-cls.xxxxxx.apne1.cache.amazonaws.com
CA=/etc/pki/tls/certs/ca-bundle.crt

# ---- dataset (deterministic) ----
python3 - <<'PY' > data.cmds
for i in range(1500): print(f"SET str:{i} value-{i}-" + "x"*(i%50))
for i in range(150):
    print("HSET hash:%d "%i + " ".join(f"f{j} v{j}-{i}" for j in range(8)))
    print("RPUSH list:%d "%i + " ".join(f"e{j}" for j in range(10)))
    print("SADD set:%d "%i + " ".join(f"m{j}" for j in range(10)))
    print("ZADD zset:%d "%i + " ".join(f"{j} z{j}" for j in range(10)))
PY
wc -l data.cmds

# ---- local sources: plaintext :6400, TLS+mTLS :6401 ----
if [ ! -f ca.crt ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 2 -subj "/CN=rfc-test-ca" 2>/dev/null
  openssl req -newkey rsa:2048 -nodes -keyout srv.key -out srv.csr -subj "/CN=localhost" 2>/dev/null
  printf "subjectAltName=DNS:localhost,IP:127.0.0.1" > san.ext
  openssl x509 -req -in srv.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out srv.crt -days 2 -extfile san.ext 2>/dev/null
  openssl req -newkey rsa:2048 -nodes -keyout cli.key -out cli.csr -subj "/CN=rfc-client" 2>/dev/null
  openssl x509 -req -in cli.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out cli.crt -days 2 2>/dev/null
fi
pkill valkey-server 2>/dev/null; sleep 1
valkey-server --port 6400 --daemonize yes --save "" --dir $W --logfile $W/v6400.log >/dev/null
valkey-server --port 0 --tls-port 6401 --tls-cert-file srv.crt --tls-key-file srv.key --tls-ca-cert-file ca.crt \
  --tls-auth-clients yes --daemonize yes --save "" --dir $W --logfile $W/v6401.log --pidfile $W/6401.pid >/dev/null
sleep 2
valkey-cli -p 6400 flushall >/dev/null
valkey-cli -p 6400 < data.cmds | sort | uniq -c
valkey-cli --tls --cacert ca.crt --cert cli.crt --key cli.key -p 6401 flushall >/dev/null
valkey-cli --tls --cacert ca.crt --cert cli.crt --key cli.key -p 6401 < data.cmds | sort | uniq -c

# ---- load into ElastiCache targets (TLS) ----
load() { # host auth cluster
  local a=(); [ -n "$2" ] && a=(-a "$2" --no-auth-warning); local c=(); [ "$3" = 1 ] && c=(-c)
  valkey-cli --tls --cacert $CA -h $1 -p 6379 "${a[@]}" "${c[@]}" flushall >/dev/null 2>&1
  valkey-cli --tls --cacert $CA -h $1 -p 6379 "${a[@]}" "${c[@]}" < data.cmds | sort | uniq -c
}
echo "== load r70-std"; load $H_R70_STD "" 0
echo "== load r70-cls"; load $H_R70_CLS "" 1
echo "== load v90-std"; load $H_V90_STD $VALKEY_AUTH 0
echo "== load v90-cls"; load $H_V90_CLS $VALKEY_AUTH 1

run() { # name expect(ok|diff) args...
  local name=$1 expect=$2; shift 2
  rm -f $W/res.db
  timeout 300 redis-full-check -d $W/res.db --comparemode 1 --comparetimes 2 --interval 1 --log $W/fc.log "$@" >$W/fc.out 2>&1
  local rc=$?
  local summ; summ=$(grep -h "all finish\|conflict" $W/fc.out $W/fc.log 2>/dev/null | tail -1 | cut -c1-200)
  local nd; nd=$(sqlite3 $W/res.db 'select count(*) from key' 2>/dev/null || echo "?")
  echo "[$name] rc=$rc expect=$expect :: $summ"
  if [ "$expect" = ok ] && echo "$summ" | grep -q "totally 0 key"; then echo "  PASS"; 
  elif [ "$expect" = diff ] && ! echo "$summ" | grep -q "totally 0 key" && [ -n "$summ" ]; then echo "  PASS";
  elif [ "$expect" = fail ] && [ $rc -ne 0 -o -z "$summ" ]; then echo "  PASS";
  else echo "  FAIL"; tail -5 $W/fc.out | cut -c1-250; fi
}
SRC=(-s 127.0.0.1:6400 --sourcedbtype 0)
SRCTLS=(-s 127.0.0.1:6401 --sourcedbtype 0 --sourcetls --sourcetlscacert $W/ca.crt --sourcetlscert $W/cli.crt --sourcetlskey $W/cli.key)
T_R70_STD=(-t $H_R70_STD:6379 --targetdbtype 0 --targettls)
T_R70_CLS=(-t master@$H_R70_CLS:6379 --targetdbtype 1 --targettls)
T_V90_STD=(-t $H_V90_STD:6379 --targetdbtype 0 --targettls -a $VALKEY_AUTH)
T_V90_CLS=(-t master@$H_V90_CLS:6379 --targetdbtype 1 --targettls -a $VALKEY_AUTH)

echo "=== A: plaintext source -> TLS target, should match"
run r70-std ok "${SRC[@]}" "${T_R70_STD[@]}"
run r70-cls ok "${SRC[@]}" "${T_R70_CLS[@]}"
run v90-std ok "${SRC[@]}" "${T_V90_STD[@]}"
run v90-cls ok "${SRC[@]}" "${T_V90_CLS[@]}"
echo "=== B: mTLS source (private CA) -> TLS target"
run mtls-src-r70-cls ok "${SRCTLS[@]}" "${T_R70_CLS[@]}"
run mtls-src-v90-std ok "${SRCTLS[@]}" "${T_V90_STD[@]}"
echo "=== C: TLS<->TLS both sides (cluster -> cluster, std -> std)"
run r70cls-to-v90cls ok -s master@$H_R70_CLS:6379 --sourcedbtype 1 --sourcetls "${T_V90_CLS[@]}"
run v90std-to-r70std ok -s $H_V90_STD:6379 -p $VALKEY_AUTH --sourcedbtype 0 --sourcetls "${T_R70_STD[@]}"
echo "=== D: negative: no --targettls against TLS endpoint must fail"
run notls-r70-std fail "${SRC[@]}" -t $H_R70_STD:6379 --targetdbtype 0
run notls-v90-cls fail "${SRC[@]}" -t master@$H_V90_CLS:6379 --targetdbtype 1 -a $VALKEY_AUTH
echo "=== E: negative: wrong CA with verification must fail; --targettlsinsecure must pass"
run wrongca-v90-std fail "${SRC[@]}" -t $H_V90_STD:6379 --targetdbtype 0 --targettls --targettlscacert $W/ca.crt -a $VALKEY_AUTH
run insecure-v90-std ok "${SRC[@]}" -t $H_V90_STD:6379 --targetdbtype 0 --targettls --targettlsinsecure -a $VALKEY_AUTH
echo "=== F: drift detection: mutate target, expect diffs"
A=(); 
valkey-cli --tls --cacert $CA -h $H_R70_STD -p 6379 set str:7 CHANGED >/dev/null; valkey-cli --tls --cacert $CA -h $H_R70_STD -p 6379 del str:9 hash:3 >/dev/null
valkey-cli --tls --cacert $CA -h $H_V90_CLS -p 6379 -a $VALKEY_AUTH --no-auth-warning -c set str:7 CHANGED >/dev/null; valkey-cli --tls --cacert $CA -h $H_V90_CLS -p 6379 -a $VALKEY_AUTH --no-auth-warning -c del str:9 hash:3 >/dev/null
run drift-r70-std diff "${SRC[@]}" "${T_R70_STD[@]}"
run drift-v90-cls diff "${SRC[@]}" "${T_V90_CLS[@]}"
