# ansible-k8s

Deploy kubernetes cluster using ansible

## 机器规划

示例：

| Role       |   Host   |       IP       |    K8S |
| :--------- | :------: | :------------: | -----: |
| ntp_server | master01 | 10.128.170.231 | 1.23.6 |
| k8s_master | master01 | 10.128.170.231 | 1.23.6 |
| k8s_master | master02 | 10.128.170.232 | 1.23.6 |
| k8s_master | master03 | 10.128.170.233 | 1.23.6 |
| k8s_worker | worker01 | 10.128.170.21  | 1.23.6 |
| k8s_worker | worker02 | 10.128.170.22  | 1.23.6 |
| k8s_worker | worker03 | 10.128.170.23  | 1.23.6 |

## Rocky Linux 8.6

### 环境准备

**全部机器均需要执行以下配置，具体配置内容需根据实际情况而定。**

#### 配置静态 IP

编辑以下配置文件

```shell
vi /etc/sysconfig/network-scripts/ifcfg-ens18
```

文件配置修改如下

```text
TYPE=Ethernet
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=static
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
IPV6INIT=yes
IPV6_AUTOCONF=yes
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
NAME=ens18
UUID=65cccf47-7fbb-4263-bedb-ec07ffe462d7
DEVICE=ens18
ONBOOT=yes
IPADDR=10.128.170.231
NETMASK=255.255.255.0
GATEWAY=10.128.170.254
DNS1=114.114.114.114
DNS2=8.8.8.8
```

重启网络服务

```shell
systemctl restart NetworkManager
```

查看 IP 地址

```shell
[root@localhost ~]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: ens18: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether fe:fc:fe:5d:3f:0e brd ff:ff:ff:ff:ff:ff
    inet 10.128.170.231/24 brd 10.128.170.255 scope global noprefixroute ens18
       valid_lft forever preferred_lft forever
    inet6 fe80::fcfc:feff:fe5d:3f0e/64 scope link noprefixroute
       valid_lft forever preferred_lft forever
```

#### 合并 /home 分区到 / 分区（可选）

- 合并前查看分区

  ```shell
  [root@master01 ~]# df -h
  Filesystem           Size  Used Avail Use% Mounted on
  devtmpfs             3.8G     0  3.8G   0% /dev
  tmpfs                3.8G     0  3.8G   0% /dev/shm
  tmpfs                3.8G  8.5M  3.8G   1% /run
  tmpfs                3.8G     0  3.8G   0% /sys/fs/cgroup
  /dev/mapper/rl-root   70G  2.5G   68G   4% /
  /dev/mapper/rl-home   50G  383M   49G   1% /home
  /dev/sda1           1014M  188M  827M  19% /boot
  tmpfs                777M     0  777M   0% /run/user/0
  ```

- 卸载 /home

  ```shell
  [root@master01 ~]# umount /home
  ```

- 取消开机自检 /home

  ```shell
  [root@master01 ~]# sed -i 's/^\/dev\/mapper\/rl-home/#&/' /etc/fstab
  ```

- 删除 /home 所在的 lv

  ```shell
  [root@master01 ~]# lvremove /dev/mapper/rl-home
  Do you really want to remove active logical volume rl/home? [y/n]: y
    Logical volume "home" successfully removed.
  ```

- 扩展 /root 所在的 lv

  ```shell
  [root@master01 ~]# lvextend -l +100%FREE /dev/mapper/rl-root
    Size of logical volume rl/root changed from 70.00 GiB (17920 extents) to 119.10 GiB (30490 extents).
    Logical volume rl/root successfully resized.
  ```

- 扩展 /root 文件系统

  ```shell
  [root@master01 ~]# xfs_growfs /dev/mapper/rl-root
  meta-data=/dev/mapper/rl-root    isize=512    agcount=4, agsize=4587520 blks
           =                       sectsz=512   attr=2, projid32bit=1
           =                       crc=1        finobt=1, sparse=1, rmapbt=0
           =                       reflink=1    bigtime=0 inobtcount=0
  data     =                       bsize=4096   blocks=18350080, imaxpct=25
           =                       sunit=0      swidth=0 blks
  naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
  log      =internal log           bsize=4096   blocks=8960, version=2
           =                       sectsz=512   sunit=0 blks, lazy-count=1
  realtime =none                   extsz=4096   blocks=0, rtextents=0
  data blocks changed from 18350080 to 31221760
  ```

- 合并后查看分区

  ```shell
  [root@master01 ~]# df -h
  Filesystem           Size  Used Avail Use% Mounted on
  devtmpfs             3.8G     0  3.8G   0% /dev
  tmpfs                3.8G     0  3.8G   0% /dev/shm
  tmpfs                3.8G  8.5M  3.8G   1% /run
  tmpfs                3.8G     0  3.8G   0% /sys/fs/cgroup
  /dev/mapper/rl-root  120G  2.8G  117G   3% /
  /dev/sda1           1014M  188M  827M  19% /boot
  tmpfs                777M     0  777M   0% /run/user/0
  ```

#### 关闭 swap

```shell
sed -i 's/^\/dev\/mapper\/rl-swap/#&/' /etc/fstab
```

### 部署步骤

#### 修改 production 清单文件

根据规划，在清单文件中配置需要部署 K8S 的主机 IP

- k8s_master 高可用必须 3 个节点，非高可用必须 1 个节点
- k8s_worker 至少一个以上
- k8s_master 和 k8s_worker 节点不能重复

#### 安装设置 ansible

只需在只执行剧本的节点执行即可，这里在 master01 执行。

```shell
chmod +x setup_ansible.sh && ./setup_ansible.sh --password "root password"
```

该脚本将会安装 ansible，同时设置节点间免密登录。

#### 节点基础设置

```shell
ansible-playbook -i production playbooks/setup.yml \
    --ssh-common-args "-o StrictHostKeyChecking=no"
```

#### 重启系统

重启系统使配置生效

```shell
reboot
```

#### 安装设置 docker

```shell
ansible-playbook -i production playbooks/install_docker.yml
```

docker 磁盘挂载

| 变量                 |  类型  |              说明              | 默认                                                                           |
| :------------------- | :----: | :----------------------------: | :----------------------------------------------------------------------------- |
| docker_imagefs_dev   | string |    /var/lib/docker 挂载设备    | 无文件系统系统时会初始化 ext4，默认不开启                                      |
| docker_imagefs_label | string | docker_imagefs_dev文件系统标签 | 默认 docker-imagefs                                                            |
| docker_imagefs_opts  | string | docker_imagefs_dev文件系统选项 | 默认 -L {{ docker_imagefs_label }}，一般情况不需要设置，除非你知道自己在做什么 |

#### 安装 kubernetes

##### 高可用部署

```shell
ansible-playbook -i production playbooks/install_k8s.yml \
    -e k8s_ha_enable=true \
    -e k8s_apiserver_vip=10.128.170.20 \
    -e k8s_apiserver_vmask=24
```

##### 非高可用部署

```shell
ansible-playbook -i production playbooks/install_k8s.yml
```

## CentOS Linux 7.9

## systemd 资源控制

- [systemd.slice](http://www.jinbuguo.com/systemd/systemd.slice.html)
- [systemd.resource-control](http://www.jinbuguo.com/systemd/systemd.resource-control.html)
- [systemd.unit](http://www.jinbuguo.com/systemd/systemd.unit.html)
- [systemd.service](http://www.jinbuguo.com/systemd/systemd.service.html)
- [从 init 系统说起](https://www.cnblogs.com/sparkdev/p/8448237.html)
- [Cgroups 与 Systemd](https://www.cnblogs.com/sparkdev/p/9523194.html)
- [systemd攻略之三：如何利用systemd控制cgroup,实战](https://developer.aliyun.com/article/810635)
- [Systemd and Cgroup](https://www.sobyte.net/post/2022-09/systemd-and-cgroup/)

通过将 cgroup 层级系统与 systemd unit 树绑定，systemd 可以把资源管理的设置从进程级别移至应用程序级别。

- 创建一个 slice

  ```shell
  cat >/usr/lib/systemd/system/kubernetes.slice <<"EOF"
  [Unit]
  Description=kubernetes slice
  DefaultDependencies=no
  Wants=-.slice

  [Slice]
  EOF
  ```

- 启动 slice

  ```shell
  systemctl daemon-reload
  systemctl start kubernetes.slice
  ```

- 查看 slice 状态

  ```shell
  [root@localhost ~]# systemctl status kubernetes.slice
  ● kubernetes.slice - kubernetes slice
     Loaded: loaded (/usr/lib/systemd/system/kubernetes.slice; static; vendor preset: disabled)
     Active: active since Thu 2022-09-08 00:09:12 CST; 7s ago

  Sep 08 00:09:12 localhost systemd[1]: Created slice kubernetes slice.
  ```

- 创建一个 service

  ```shell
  cat >/usr/lib/systemd/system/top.service <<"EOF"
  [Unit]
  Description=top

  [Service]
  ExecStart=/usr/bin/top -b
  Slice=kubernetes.slice

  [Install]
  WantedBy=multi-user.target
  EOF
  ```

- 启动 service

  ```shell
  systemctl daemon-reload
  systemctl start top.slice
  ```

- 查看 service 状态

  ```shell
  [root@dev235 ansible-k8s]# systemctl status top.service
  ● top.service - top
     Loaded: loaded (/usr/lib/systemd/system/top.service; disabled; vendor preset: disabled)
     Active: active (running) since Thu 2022-09-08 00:27:48 CST; 11s ago
   Main PID: 20056 (top)
     CGroup: /kubernetes.slice/top.service
             └─20056 /usr/bin/top -b

  ...
  [root@dev235 ansible-k8s]# systemctl status kubernetes.slice
  ● kubernetes.slice - kubernetes slice
     Loaded: loaded (/usr/lib/systemd/system/kubernetes.slice; static; vendor preset: disabled)
     Active: active since Thu 2022-09-08 00:26:09 CST; 3min 11s ago
     CGroup: /kubernetes.slice
             └─top.service
               └─20056 /usr/bin/top -b

  ...
  ```

- 查看 systemctl status

  ```shell
  [root@localhost ~]# systemctl status
  ● localhost
      State: running
       Jobs: 0 queued
     Failed: 0 units
      Since: Thu 2022-08-18 15:21:06 CST; 2 weeks 6 days ago
     CGroup: /
             ├─1 /usr/lib/systemd/systemd --switched-root --system --deserialize 22
             ├─kubernetes.slice
             │ └─top.service
             │   └─20056 /usr/bin/top -b
             ├─user.slice
             │ └─user-0.slice
             ...
             └─system.slice
               ├─rsyslog.service
               │ └─1745 /usr/sbin/rsyslogd -n
               ...
  ```

## References

[https://github.com/ralish/bash-script-template](https://github.com/ralish/bash-script-template)
