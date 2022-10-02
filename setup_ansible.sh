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
INVENTORY=$CURRENT/hosts.ini
# ssh 连接密码
SSH_PASSWORD=

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

get_distribution() {
    local lsb_dist=""
    # Every system that we officially support has /etc/os-release
    if [[ -r /etc/os-release ]]; then
        # shellcheck source=/dev/null
        lsb_dist="$(. /etc/os-release && echo "$ID")"
    fi

    # perform some very rudimentary platform detection
    lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

    # Returning an empty string here should be alright since the
    # case statements don't act unless you provide an actual value
    echo "$lsb_dist"
}

function setup_repo() {
    logger info "************************ Setup Repo Begin ***********************"
    lsb_dist=$(get_distribution)

    # Run setup for each distro accordingly
    case "$lsb_dist" in
    centos)
        # https://stackoverflow.com/questions/6363441/check-if-a-file-exists-with-a-wildcard-in-a-shell-script
        if ! compgen -G "/etc/yum.repos.d/CentOS-*.repo.bak" >/dev/null; then
            # shellcheck disable=SC2016
            sed -e 's|^mirrorlist=|#mirrorlist=|g' \
                -e 's|^#baseurl=http://mirror.centos.org|baseurl=http://mirrors.aliyun.com|g' \
                -i.bak \
                /etc/yum.repos.d/CentOS-*.repo

            # shellcheck disable=SC2016
            # sed -e 's|^mirrorlist=|#mirrorlist=|g' \
            #     -e 's|^#baseurl=http://mirror.centos.org|baseurl=https://mirrors.tuna.tsinghua.edu.cn|g' \
            #     -i.bak \
            #     /etc/yum.repos.d/CentOS-*.repo

            yum makecache
        fi
        ;;
    rocky)
        # https://stackoverflow.com/questions/6363441/check-if-a-file-exists-with-a-wildcard-in-a-shell-script
        if ! compgen -G "/etc/yum.repos.d/Rocky-*.repo.bak" >/dev/null; then
            # shellcheck disable=SC2016
            sed -e 's|^mirrorlist=|#mirrorlist=|g' \
                -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.aliyun.com/rockylinux|g' \
                -i.bak \
                /etc/yum.repos.d/Rocky-*.repo

            # shellcheck disable=SC2016
            # sed -e 's|^mirrorlist=|#mirrorlist=|g' \
            #     -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.nju.edu.cn/rocky|g' \
            #     -i.bak \
            #     /etc/yum.repos.d/Rocky-*.repo

            dnf makecache
        fi
        ;;
    *)
        logger info "" && logger error "Unsupported distribution '$lsb_dist'"
        exit 1
        ;;
    esac
    logger info "************************* Setup Repo End ************************"
}

function reset_repo() {
    logger info "************************ Reset Repo Begin ***********************"
    lsb_dist=$(get_distribution)

    # Run setup for each distro accordingly
    case "$lsb_dist" in
    centos)
        # https://stackoverflow.com/questions/6363441/check-if-a-file-exists-with-a-wildcard-in-a-shell-script
        if compgen -G "/etc/yum.repos.d/CentOS-*.repo.bak" >/dev/null; then
            # shellcheck disable=SC2016
            rm -f /etc/yum.repos.d/CentOS-*.repo
            rename '.bak' '' /etc/yum.repos.d/CentOS-*.bak

            yum makecache
        fi
        ;;
    rocky)
        # https://stackoverflow.com/questions/6363441/check-if-a-file-exists-with-a-wildcard-in-a-shell-script
        if ! compgen -G "/etc/yum.repos.d/Rocky-*.repo.bak" >/dev/null; then
            # shellcheck disable=SC2016
            rm -f /etc/yum.repos.d/Rocky-*.repo
            rename '.bak' '' /etc/yum.repos.d/Rocky-*.bak

            dnf makecache
        fi
        ;;
    *)
        logger info "" && logger error "Unsupported distribution '$lsb_dist'"
        exit 1
        ;;
    esac
    logger info "************************* Reset Repo End ************************"
}

function setup_ansible() {
    logger info "********************** Setup Ansible Begin **********************"
    lsb_dist=$(get_distribution)

    # Run setup for each distro accordingly
    case "$lsb_dist" in
    centos | rocky)
        yum install -y epel-release
        yum install -y \
            git \
            libffi-devel \
            openssl-devel \
            sshpass \
            expect \
            python3-devel \
            python3-pip

        # ansible [core 2.11.12]
        pip3 install -i https://mirrors.aliyun.com/pypi/simple/ -U pip
        pip3 install -i https://mirrors.aliyun.com/pypi/simple/ ansible==4.10.0

        # ansible [core 2.11.12]
        # pip3 install -i https://pypi.tuna.tsinghua.edu.cn/simple -U pip
        # pip3 install -i https://pypi.tuna.tsinghua.edu.cn/simple ansible==4.10.0
        ;;
    *)
        logger info "" && logger error "Unsupported distribution '$lsb_dist'"
        exit 1
        ;;
    esac

    # logger info "Download default ansible.cfg from github"

    # Ansible Configuration Settings
    # https://docs.ansible.com/ansible/latest/reference_appendices/config.html
    # https://docs.ansible.com/ansible/latest/installation_guide/intro_configuration.html
    # https://github.com/ansible/ansible/blob/devel/examples/ansible.cfg
    # https://github.com/ansible/ansible/blob/stable-2.11/examples/ansible.cfg
    # curl -k -C - https://cdn.jsdelivr.net/gh/ansible/ansible@stable-2.11/examples/ansible.cfg \
    #     -o /etc/ansible/ansible.cfg

    # Ansible callback plugin for timing individual tasks and overall execution time.
    # https://docs.ansible.com/ansible/latest/collections/ansible/posix/profile_tasks_callback.html
    # sed -i 's/.*callbacks_enabled.*/callbacks_enabled = profile_tasks/g' \
    #     /etc/ansible/ansible.cfg
    # sed -i 's/.*forks.*/forks           = 6/g' \
    #     /etc/ansible/ansible.cfg
    # sed -i 's/.*host_key_checking.*/host_key_checking = False/g' \
    #     /etc/ansible/ansible.cfg
    # sed -i 's/.*deprecation_warnings.*/deprecation_warnings = False/g' \
    #     /etc/ansible/ansible.cfg

    ansible --version
    logger info "*********************** Setup Ansible End ***********************"
}

function setup_sshkey() {
    logger info "*********************** Setup sshkey Begin **********************"

    # shellcheck disable=SC2016
    command='
    set timeout 60

    spawn ansible-playbook -k \
    -i $env(inventory) \
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
        current="$CURRENT" ssh_password="$SSH_PASSWORD" inventory="$INVENTORY" \
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
            logger info "" && logger error "No Input!!! Exit!"
            exit 1
        fi
    done

    set -o errexit
    logger info "************************ Setup sshkey End ***********************"
}

function varify_inventory() {
    local inventory=$1
    if [[ -z "${inventory}" ]]; then
        logger error '"INVENTORY" can not be empty!'
        exit 1
    fi
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

    Optional:
      -v|--verbose                          Displays verbose output
      -i|--inventory                        Specify inventory host path

    Required:
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
        -i | --inventory)
            INVENTORY="${1-}"
            varify_inventory "$INVENTORY"
            shift
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

    setup_repo
    setup_ansible
    setup_sshkey
    # reset_repo
}

# Invoke main with args if not sourced
# Approach via: https://stackoverflow.com/a/28776166/8787985
if ! (return 0 2>/dev/null); then
    main "$@"
fi
