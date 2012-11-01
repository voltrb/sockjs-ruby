#!/bin/env bash
rake -t protocol_test &
until netstat -tlpn 2>/dev/null | grep -q 8081; do
  sleep 1;
done
protocol/venv/bin/python protocol/sockjs-protocol-0.2.1.py $*
kill %rake
