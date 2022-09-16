#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace # Trace the execution of the script (debug)
fi

# Only enable these shell behaviours if we're not being sourced
# Approach via: https://stackoverflow.com/a/28776166/8787985
if ! (return 0 2>/dev/null); then
    # A better class of script...
    set -o errexit  # Exit on most errors (see the manual)
    set -o nounset  # Disallow expansion of unset variables
    set -o pipefail # Use last non-zero exit code in a pipeline
fi

# Enable errtrace or the error trap handler will not work as expected
set -o errtrace # Ensure the error trap handler is inherited

set -e

VERBOSE=false
# 当前文件目录的绝对路径
# https://www.cnblogs.com/sunfie/p/5943979.html
CURRENT=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
# ansible 清单文件路径
# https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html
INVENTORY=$CURRENT/inventory
# ssh 连接密码
PASSWORD=

function setup_repo() {
    echo -e "\n************************ Setup Repo Begin ***********************"
    # https://stackoverflow.com/questions/6363441/check-if-a-file-exists-with-a-wildcard-in-a-shell-script
    if ! compgen -G "/etc/yum.repos.d/CentOS-*.repo.bak" >/dev/null; then
        # shellcheck disable=SC2016
        sed -e 's|^mirrorlist=|#mirrorlist=|g' \
            -e 's|^#baseurl=http://mirror.centos.org|baseurl=https://mirrors.tuna.tsinghua.edu.cn|g' \
            -i.bak \
            /etc/yum.repos.d/CentOS-*.repo

        yum makecache
    fi
    echo "************************* Setup Repo End ************************"
}

function reset_repo() {
    echo -e "\n************************ Reset Repo Begin ***********************"
    # shellcheck disable=SC2016
    rm -f /etc/yum.repos.d/CentOS-*.repo
    rename '.bak' '' /etc/yum.repos.d/CentOS-*.bak

    yum makecache
    echo "************************* Reset Repo End ************************"
}

function setup_ansible() {
    echo -e "\n********************** Setup Ansible Begin **********************"
    yum install epel-release -y
    yum install ansible -y
    ansible --version

    echo -e "\nDownload default ansible.cfg from github"
    # 初始化 ansible 配置
    # Ansible Configuration Settings
    # https://docs.ansible.com/ansible/2.9/reference_appendices/config.html
    # https://github.com/ansible/ansible/blob/stable-2.9/examples/ansible.cfg
    # https://curl.se/docs/manpage.html
    curl -k -C - https://cdn.jsdelivr.net/gh/ansible/ansible@stable-2.9/examples/ansible.cfg \
        -o /etc/ansible/ansible.cfg

    # 打印每个 task 执行时间
    # Ansible callback plugin for timing individual tasks and overall execution time.
    # https://docs.ansible.com/ansible/latest/collections/ansible/posix/profile_tasks_callback.html
    sed -i 's/.*callback_whitelist.*/callback_whitelist = profile_tasks/g' \
        /etc/ansible/ansible.cfg
    echo "*********************** Setup Ansible End ***********************"
}

function setup_sshkey() {
    echo -e "\n*********************** Setup sshkey Begin **********************"
    yum install expect -y

    # shellcheck disable=SC2016
    command='
    set timeout 60

    spawn ansible-playbook -k \
    --ssh-common-args "-o StrictHostKeyChecking=no" \
    -i $env(inventory) \
    $env(current)/playbooks/setup_sshkey.yml

    expect "SSH password:" {send "$env(password)\n"}

    set result 0
    expect {
        "unreachable=\[1-9]" {set result 1}
        "failed=\[1-9]" {set result 2}
    }
    exit "$result"
    '

    set +e

    local idx=0
    local retries=3
    while true; do
        current="$CURRENT" password="$PASSWORD" inventory="$INVENTORY" \
            expect -c "$command"

        # shellcheck disable=SC2181
        if [[ $? -eq 0 ]]; then
            break
        elif [[ $? -eq 1 ]]; then
            ((idx++)) || true
        else
            echo "Unknown Error!!! Exit!"
            exit 1
        fi

        if [[ $idx -gt $retries ]]; then
            echo "Wrong Password! Retry limit exceeded! Exit!"
            exit 1
        fi

        echo -e "\nWrong Password! Please enter again!"
        echo "NOTE: All nodes' password must be the same!!!"
        if ! read -rs -t 30 -p "SSH password: " PASSWORD; then
            echo "No Input!!! Exit!"
            exit 1
        fi
    done

    set -e
    echo "************************ Setup sshkey End ***********************"
}

# DESC: Usage help
# ARGS: None
# OUTS: None
function script_usage() {
    cat <<EOF
Usage:
    ${BASH_SOURCE[0]} --password 123456

      -h|--help                          Displays this help
      -v|--verbose                       Displays verbose output
         --password PASSWORD             SSH password of root user
EOF
}

# DESC: Parameter parser
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: Variables indicating command-line parameters and options
function parse_params() {
    local param
    while [[ $# -gt 0 ]]; do
        param="$1"
        shift
        case $param in
        -h | --help)
            script_usage
            exit 0
            ;;
        -v | --verbose)
            VERBOSE=true
            ;;
        --password)
            # https://unix.stackexchange.com/questions/463034/bash-throws-error-line-8-1-unbound-variable
            # In particular, one could use [ -n "${1-}" ]
            # (that is, with an empty default value) to see
            # if the parameter is set and non-empty;
            # or [ "${1+x}" = x ] to see if it's set, even if empty.
            PASSWORD="${1-}"
            varify_password "$PASSWORD"
            shift
            ;;
        *)
            script_exit "Invalid parameter was provided: $param" 1
            ;;
        esac
    done

    if [[ -z $PASSWORD ]]; then
        echo '"--password" is required'
        exit 1
    fi
}

function main() {
    # trap script_trap_err ERR
    # trap script_trap_exit EXIT

    script_init "$@"
    parse_params "$@"
    cron_init
    colour_init
    #lock_init system

    if [[ "$VERBOSE" = true ]]; then
        set -x
    fi

    setup_repo
    setup_ansible
    setup_sshkey
    reset_repo
}

# shellcheck disable=SC1091
source "$CURRENT/common.sh"
# shellcheck disable=SC1091
source "$CURRENT/validator.sh"

# Invoke main with args if not sourced
# Approach via: https://stackoverflow.com/a/28776166/8787985
if ! (return 0 2>/dev/null); then
    main "$@"
fi
