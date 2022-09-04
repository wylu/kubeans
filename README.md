# ansible-k8s

Deploy kubernetes cluster using ansible

## 机器规划

示例：

| Role       |   Host   |       IP       |       OS        |  K8S   |
| :--------- | :------: | :------------: | :-------------: | :----: |
| ntp_server | master01 | 10.128.170.231 | Rocky Linux 8.6 | 1.23.6 |
| k8s_master | master01 | 10.128.170.231 | Rocky Linux 8.6 | 1.23.6 |
| k8s_master | master02 | 10.128.170.232 | Rocky Linux 8.6 | 1.23.6 |
| k8s_master | master03 | 10.128.170.233 | Rocky Linux 8.6 | 1.23.6 |
| k8s_worker | worker01 | 10.128.170.21  | Rocky Linux 8.6 | 1.23.6 |
| k8s_worker | worker02 | 10.128.170.22  | Rocky Linux 8.6 | 1.23.6 |
| k8s_worker | worker03 | 10.128.170.23  | Rocky Linux 8.6 | 1.23.6 |

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

#### 设置主机名

使用 hostnamectl 工具设置主机名

```shell
hostnamectl set-hostname master01
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

#### 重启系统

```shell
reboot
```

### 安装 ansible

只需在只执行剧本的节点安装即可，这里在 master01 执行。

#### 更换软件镜像源

参考 [https://mirror.nju.edu.cn/help/rocky](https://mirror.nju.edu.cn/help/rocky) 帮助文档

- 将所有的官方主镜像地址替换为南京大学镜像站地址，如果已经使用了其他镜像站，请相应的替换网址。
  
  ```shell
  sed -e 's|^mirrorlist=|#mirrorlist=|g' \
      -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.nju.edu.cn/rocky|g' \
      -i.bak \
      /etc/yum.repos.d/Rocky-*.repo
  ```

- 更新缓存。
  
  ```shell
  dnf makecache
  ```

- 安装 epel-release
  
  ```shell
  dnf install epel-release -y
  ```

#### 安装 ansible 2.12

```shell
dnf install ansible -y
```

查看 ansible 版本

```shell
[root@master01 ~]# ansible --version
ansible [core 2.12.2]
  config file = /etc/ansible/ansible.cfg
  configured module search path = ['/root/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
  ansible python module location = /usr/lib/python3.8/site-packages/ansible
  ansible collection location = /root/.ansible/collections:/usr/share/ansible/collections
  executable location = /usr/bin/ansible
  python version = 3.8.12 (default, May 10 2022, 23:46:40) [GCC 8.5.0 20210514 (Red Hat 8.5.0-10)]
  jinja version = 2.10.3
  libyaml = True
```

初始化 ansible 配置

[Ansible Configuration Settings](https://docs.ansible.com/ansible/latest/reference_appendices/config.html)

```shell
ansible-config init --disabled > /etc/ansible/ansible.cfg
```

### 部署步骤

#### 修改 production 清单文件

根据规划，在清单文件中配置需要部署 K8S 的主机 IP

- k8s_master 高可用必须 3 个节点，非高可用必须 1 个节点
- k8s_worker 至少一个以上
- k8s_master 和 k8s_worker 节点不能重复

#### 禁用防火墙并设置主机间免密登录

```shell
bash setup_environment.sh
```

## CentOS Linux 7.9

## References

[https://github.com/ralish/bash-script-template](https://github.com/ralish/bash-script-template)
