#!/bin/env bash
rake -t protocol_test &
until netstat -tlpn 2>/dev/null | grep -q 8081; do
  sleep 1;
done
PROTO_VERSION=$(ruby -r "./lib/sockjs/version.rb" -e "print SockJS::PROTOCOL_VERSION_STRING")
protocol/venv/bin/python protocol/sockjs-protocol-${PROTO_VERSION}.py $*
kill -9 %rake
