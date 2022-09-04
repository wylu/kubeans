#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
@File    :   utils.py
@Time    :   2022/09/03 16:33:44
@Author  :   wylu
@Version :   1.0
@Contact :   15wylu@gmail.com
@License :   Copyright © 2020, wylu-CHINA-SHENZHEN. All rights reserved.
@Desc    :
"""
import configparser
import os
import pathlib
import typing as t
import yaml

from collections import OrderedDict


# https://www.cnblogs.com/langshiquan/p/9569898.html
# https://stackoverflow.com/questions/8640959/how-can-i-control-what-scalar-form-pyyaml-uses-for-my-data
# https://stackoverflow.com/questions/6432605/any-yaml-libraries-in-python-that-support-dumping-of-long-strings-as-block-liter
# https://pyyaml.org/wiki/PyYAMLDocumentation
class OrderedDumper(yaml.SafeDumper):
    pass


def _dict_representer(dumper: yaml.Dumper, data):
    return dumper.represent_mapping(
        yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, data.items()
    )


OrderedDumper.add_representer(OrderedDict, _dict_representer)


class RepoUtil(object):
    DEFAULT_DIRECTORY = '/etc/yum.repos.d'

    @classmethod
    def yesno(cls, option: int) -> str:
        return 'yes' if option else 'no'

    @classmethod
    def load_file(cls, file: str) -> str:
        with open(file, 'r') as f:
            data = f.read()

        segments = []
        for seg in data.split('\n\n'):
            if '#[' not in seg and '#baseurl' in seg:
                seg = seg.replace('#baseurl', 'baseurl')
            segments.append(seg)

        return '\n\n'.join(segments)


class RockyRepoUtil(RepoUtil):
    FILES = {
        'Rocky-AppStream.repo',
        'Rocky-BaseOS.repo',
        'Rocky-Debuginfo.repo',
        'Rocky-Devel.repo',
        'Rocky-Extras.repo',
        'Rocky-HighAvailability.repo',
        'Rocky-NFV.repo',
        'Rocky-Plus.repo',
        'Rocky-PowerTools.repo',
        'Rocky-RT.repo',
        'Rocky-ResilientStorage.repo',
        'Rocky-Sources.repo',
    }

    @classmethod
    def get_files(
        cls,
        directory: str = RepoUtil.DEFAULT_DIRECTORY,
    ) -> t.List[str]:
        return sorted(
            os.path.join(directory, file)
            for file in os.listdir(directory)
            if file in cls.FILES
        )

    @classmethod
    def parse_files(cls, files: t.List[str]) -> dict:
        name2items = OrderedDict()

        for file in files:
            path = pathlib.Path(file)
            name, _ = os.path.splitext(path.name)

            config = configparser.ConfigParser()
            config.read_string(cls.load_file(file))

            name2items[name] = [
                OrderedDict(
                    section=section,
                    name=config[section]['name'],
                    mirrorlist=config[section].get('mirrorlist'),
                    baseurl=config[section].get('baseurl'),
                    gpgcheck=config[section].getint('gpgcheck'),
                    enabled=config[section].getint('enabled'),
                    gpgkey=config[section]['gpgkey'],
                ) for section in config.sections()
            ]

        return name2items

    @classmethod
    def use_mirrorlist(
        cls,
        name2items: dict,
        old_prefix: str = '',
        new_prefix: str = '',
    ) -> None:
        for _, items in name2items.items():
            for item in items:
                del item['baseurl']
                item['mirrorlist'] = item['mirrorlist'].replace(
                    old_prefix, new_prefix
                )

    @classmethod
    def use_baseurl(
        cls,
        name2items: dict,
        old_prefix: str = '',
        new_prefix: str = '',
    ) -> None:
        for _, items in name2items.items():
            for item in items:
                del item['mirrorlist']
                item['baseurl'] = item['baseurl'].replace(
                    old_prefix, new_prefix
                )

    @classmethod
    def to_ansible_yaml(cls, name2items: dict) -> str:
        tasks = []

        for name, items in name2items.items():
            task = OrderedDict(name=f'setup {name} official repository')

            with_items = []
            if len(items) > 1:
                for item in items:
                    witem = OrderedDict(
                        name=item['section'],
                        description=item['name'],
                    )
                    if 'mirrorlist' in item:
                        witem['mirrorlist'] = item['mirrorlist']
                    if 'baseurl' in item:
                        witem['baseurl'] = item['baseurl']
                    with_items.append(witem)

            item = items[0]

            yum_repository = OrderedDict()
            if with_items:
                yum_repository['name'] = '{{ item.name }}'
                yum_repository['description'] = '{{ item.description }}'
                if 'mirrorlist' in item:
                    yum_repository['mirrorlist'] = '{{ item.mirrorlist }}'
                if 'baseurl' in item:
                    yum_repository['baseurl'] = '{{ item.baseurl }}'
            else:
                yum_repository['name'] = item['section']
                yum_repository['description'] = item['name']
                if 'mirrorlist' in item:
                    yum_repository['mirrorlist'] = item['mirrorlist']
                if 'baseurl' in item:
                    yum_repository['baseurl'] = item['baseurl']

            yum_repository['gpgcheck'] = cls.yesno(item['gpgcheck'])
            yum_repository['enabled'] = cls.yesno(item['enabled'])
            yum_repository['file'] = name
            yum_repository['gpgkey'] = item['gpgkey']
            yum_repository['state'] = 'present'

            task['yum_repository'] = yum_repository

            if with_items:
                task['with_items'] = with_items

            task['notify'] = 'dnf makecache'
            tasks.append(task)

        data = yaml.dump(
            tasks,
            Dumper=OrderedDumper,
            allow_unicode=True,
            explicit_start=True,
        )

        data = data.replace("'yes'", 'yes')
        data = data.replace("'no'", 'no')

        return data


if __name__ == '__main__':
    files = RockyRepoUtil.get_files()
    name2items = RockyRepoUtil.parse_files(files)
    print(RockyRepoUtil.to_ansible_yaml(name2items))
