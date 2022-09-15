#!/usr/bin/env bash

errorExit() {
    echo "*** $*" 1>&2
    exit 1
}

curl --silent \
    --max-time 2 \
    --insecure "https://localhost:{{ k8s_apiserver_vport }}/" \
    -o /dev/null || errorExit "Error GET https://localhost:{{ k8s_apiserver_vport }}/"
if ip addr | grep -q "{{ k8s_apiserver_vip }}"; then
    curl --silent \
        --max-time 2 \
        --insecure "https://{{ k8s_apiserver_vip }}:{{ k8s_apiserver_vport }}/" \
        -o /dev/null || errorExit "Error GET https://{{ k8s_apiserver_vip }}:{{ k8s_apiserver_vport }}/"
fi
