#!/usr/bin/env bash

function varify_password() {
    local password=$1
    if [[ -z "${password}" ]]; then
        echo '"password" can not be empty!'
        exit 1
    fi
}
