#!/usr/bin/env bash

set -o nounset
set -o errexit
#set -o xtrace

VERBOSE=false
# 当前文件目录的绝对路径
# https://www.cnblogs.com/sunfie/p/5943979.html
CURRENT=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
# ansible 清单文件路径
# https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html
HOSTS=$CURRENT/hosts.ini
# ssh 连接密码
SSH_PASSWORD=

IS_CENTOS7=false
IS_ROCKY8=false

function logger() {
    TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
    case "$1" in
    debug)
        echo -e "[$TIMESTAMP][\033[36mDEBUG\033[0m] $2"
        ;;
    info)
        echo -e "[$TIMESTAMP][\033[32mINFO\033[0m] $2"
        ;;
    warn)
        echo -e "[$TIMESTAMP][\033[33mWARN\033[0m] $2"
        ;;
    error)
        echo -e "[$TIMESTAMP][\033[31mERROR\033[0m] $2"
        ;;
    *) ;;
    esac
}

function setup_system() {
    logger info "*********************** Setup System Begin **********************"
    if [[ -f "/etc/redhat-release" ]]; then
        if grep '^CentOS Linux release 7\..*' /etc/redhat-release; then
            IS_CENTOS7=true
        fi
        if grep '^Rocky Linux release 8\..*' /etc/redhat-release; then
            IS_ROCKY8=true
        fi
    fi
    logger info "************************ Setup System End ***********************"
}

function setup_repo() {
    logger info "************************ Setup Repo Begin ***********************"
    if [[ "$IS_CENTOS7" = true ]]; then
        # https://stackoverflow.com/questions/6363441/check-if-a-file-exists-with-a-wildcard-in-a-shell-script
        if ! compgen -G "/etc/yum.repos.d/CentOS-*.repo.bak" >/dev/null; then
            # shellcheck disable=SC2016
            sed -e 's|^mirrorlist=|#mirrorlist=|g' \
                -e 's|^#baseurl=http://mirror.centos.org|baseurl=https://mirrors.tuna.tsinghua.edu.cn|g' \
                -i.bak \
                /etc/yum.repos.d/CentOS-*.repo

            yum makecache
        fi
    fi

    if [[ "$IS_ROCKY8" = true ]]; then
        # https://stackoverflow.com/questions/6363441/check-if-a-file-exists-with-a-wildcard-in-a-shell-script
        if ! compgen -G "/etc/yum.repos.d/Rocky-*.repo.bak" >/dev/null; then
            # shellcheck disable=SC2016
            sed -e 's|^mirrorlist=|#mirrorlist=|g' \
                -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.nju.edu.cn/rocky|g' \
                -i.bak \
                /etc/yum.repos.d/Rocky-*.repo

            dnf makecache
        fi
    fi
    logger info "************************* Setup Repo End ************************"
}

function reset_repo() {
    logger info "************************ Reset Repo Begin ***********************"
    if [[ "$IS_CENTOS7" = true ]]; then
        # shellcheck disable=SC2016
        rm -f /etc/yum.repos.d/CentOS-*.repo
        rename '.bak' '' /etc/yum.repos.d/CentOS-*.bak

        yum makecache
    fi

    if [[ "$IS_ROCKY8" = true ]]; then
        # shellcheck disable=SC2016
        rm -f /etc/yum.repos.d/Rocky-*.repo
        rename '.bak' '' /etc/yum.repos.d/Rocky-*.bak

        dnf makecache
    fi
    logger info "************************* Reset Repo End ************************"
}

function setup_ansible() {
    logger info "********************** Setup Ansible Begin **********************"
    if [[ "$IS_CENTOS7" = true ]]; then
        yum install epel-release -y
        yum install expect -y
        yum install ansible -y
        ansible --version

        logger info "Download default ansible.cfg from github"
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
    fi

    if [[ "$IS_ROCKY8" = true ]]; then
        dnf install epel-release -y
        dnf install expect -y
        dnf install ansible -y
        ansible --version

        # 初始化 ansible 配置
        # Ansible Configuration Settings
        # https://docs.ansible.com/ansible/latest/reference_appendices/config.html
        ansible-config init --disabled >/etc/ansible/ansible.cfg

        # 打印每个 task 执行时间
        # Ansible callback plugin for timing individual tasks and overall execution time.
        # https://docs.ansible.com/ansible/latest/collections/ansible/posix/profile_tasks_callback.html
        sed -i 's/.*callbacks_enabled.*/callbacks_enabled=profile_tasks/g' \
            /etc/ansible/ansible.cfg
    fi
    logger info "*********************** Setup Ansible End ***********************"
}

function setup_sshkey() {
    logger info "*********************** Setup sshkey Begin **********************"

    # shellcheck disable=SC2016
    command='
    set timeout 60

    spawn ansible-playbook -k \
    --ssh-common-args "-o StrictHostKeyChecking=no" \
    -i $env(hosts) \
    $env(current)/playbooks/00.sshkey.yml

    expect "SSH password:" {send "$env(ssh_password)\n"}

    set result 0
    expect {
        "unreachable=\[1-9]" {set result 1}
        "failed=\[1-9]" {set result 2}
    }
    exit "$result"
    '

    set +o errexit

    local idx=0
    local retries=3
    while true; do
        current="$CURRENT" ssh_password="$SSH_PASSWORD" hosts="$HOSTS" \
            expect -c "$command"

        # shellcheck disable=SC2181
        if [[ $? -eq 0 ]]; then
            break
        elif [[ $? -eq 1 ]]; then
            ((idx++)) || true
        else
            logger error "Unknown Error!!! Exit!"
            exit 1
        fi

        if [[ $idx -gt $retries ]]; then
            logger error "Wrong Password! Retry limit exceeded! Exit!"
            exit 1
        fi

        logger warn "Wrong Password! Please enter again!"
        logger warn "NOTE: All nodes' password must be the same!!!"
        if ! read -rs -t 30 -p "SSH password: " SSH_PASSWORD; then
            echo "" && logger error "No Input!!! Exit!"
            exit 1
        fi
    done

    set -o errexit
    logger info "************************ Setup sshkey End ***********************"
}

function varify_ssh_password() {
    local ssh_password=$1
    if [[ -z "${ssh_password}" ]]; then
        logger error '"SSH_PASSWORD" can not be empty!'
        exit 1
    fi
}

# DESC: Usage help
# ARGS: None
# OUTS: None
function script_usage() {
    cat <<EOF
Usage:
    ${BASH_SOURCE[0]} --ssh-password "root password"

      -h|--help                             Displays this help
      -v|--verbose                          Displays verbose output
         --ssh-password SSH_PASSWORD        SSH password of root user
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
        --ssh-password)
            # https://unix.stackexchange.com/questions/463034/bash-throws-error-line-8-1-unbound-variable
            # In particular, one could use [ -n "${1-}" ]
            # (that is, with an empty default value) to see
            # if the parameter is set and non-empty;
            # or [ "${1+x}" = x ] to see if it's set, even if empty.
            SSH_PASSWORD="${1-}"
            varify_ssh_password "$SSH_PASSWORD"
            shift
            ;;
        *)
            logger error "Invalid parameter was provided: $param"
            exit 1
            ;;
        esac
    done

    if [[ -z $SSH_PASSWORD ]]; then
        logger error '"--ssh-password" is required'
        exit 1
    fi
}

function main() {
    parse_params "$@"

    if [[ "$VERBOSE" = true ]]; then
        set -x
    fi

    setup_system
    setup_repo
    setup_ansible
    setup_sshkey
    reset_repo
}

# Invoke main with args if not sourced
# Approach via: https://stackoverflow.com/a/28776166/8787985
if ! (return 0 2>/dev/null); then
    main "$@"
fi
