#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
@File    :   centos.py
@Time    :   2022/09/03 11:00:05
@Author  :   wylu
@Version :   1.0
@Contact :   15wylu@gmail.com
@License :   Copyright © 2020, wylu-CHINA-SHENZHEN. All rights reserved.
@Desc    :
"""
import typing as t

import click

from .utils import MirrorSource
from .utils import PackageManager
from .utils import CentosRepoUtil


class MirrorHandler(object):

    @classmethod
    def handle(cls, source: MirrorSource, file: t.Optional[str]) -> None:
        getattr(cls, 'handle_' + source)(file)

    @classmethod
    def handle_official(cls, file: t.Optional[str]) -> None:
        files = CentosRepoUtil.get_files(CentosRepoUtil.FILES)
        name2items = CentosRepoUtil.parse_files(files)
        CentosRepoUtil.use_mirrorlist(name2items)
        data = CentosRepoUtil.to_ansible_yaml(name2items, PackageManager.YUM)

        if not file:
            print(data)
            return

        with open(file, 'w', encoding='utf-8') as f:
            f.write(data)

    @classmethod
    def handle_tuna(cls, file: t.Optional[str]) -> None:
        files = CentosRepoUtil.get_files(CentosRepoUtil.FILES)
        name2items = CentosRepoUtil.parse_files(files)
        CentosRepoUtil.use_baseurl(
            name2items,
            old_prefix='http://mirror.centos.org',
            new_prefix='https://mirrors.tuna.tsinghua.edu.cn',
        )
        data = CentosRepoUtil.to_ansible_yaml(
            name2items,
            PackageManager.YUM,
            MirrorSource.TUNA,
        )

        if not file:
            print(data)
            return

        with open(file, 'w', encoding='utf-8') as f:
            f.write(data)


@click.group()
def centos():
    pass


@centos.command()
@click.option(
    '-s',
    '--source',
    required=True,
    type=click.Choice([MirrorSource.OFFICIAL, MirrorSource.TUNA]),
    help='Choose what mirror source to use.',
)
@click.option(
    '-f',
    '--file',
    type=click.Path(),
    help='Specific the file to output.',
)
def mirror(source, file):
    MirrorHandler.handle(source, file)
