#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
@File    :   rocky.py
@Time    :   2022/09/03 11:00:11
@Author  :   wylu
@Version :   1.0
@Contact :   15wylu@gmail.com
@License :   Copyright © 2020, wylu-CHINA-SHENZHEN. All rights reserved.
@Desc    :
"""
import typing as t
from enum import Enum

import click

from .utils import RockyRepoUtil


class MirrorSource(str, Enum):
    OFFICIAL = 'official'
    NJU = 'nju'


class MirrorHandler(object):

    @classmethod
    def handle(cls, source: MirrorSource, file: t.Optional[str]) -> None:
        getattr(cls, 'handle_' + source)(file)

    @classmethod
    def handle_official(cls, file: t.Optional[str]) -> None:
        files = RockyRepoUtil.get_files()
        name2items = RockyRepoUtil.parse_files(files)
        RockyRepoUtil.use_mirrorlist(name2items)
        data = RockyRepoUtil.to_ansible_yaml(name2items)

        if not file:
            print(data)
            return

        with open(file, 'w', encoding='utf-8') as f:
            f.write(data)

    @classmethod
    def handle_nju(cls, file: t.Optional[str]) -> None:
        files = RockyRepoUtil.get_files()
        name2items = RockyRepoUtil.parse_files(files)
        RockyRepoUtil.use_baseurl(
            name2items,
            old_prefix='http://dl.rockylinux.org/$contentdir',
            new_prefix='https://mirrors.nju.edu.cn/rocky',
        )
        data = RockyRepoUtil.to_ansible_yaml(name2items)

        if not file:
            print(data)
            return

        with open(file, 'w', encoding='utf-8') as f:
            f.write(data)


@click.group()
def rocky():
    pass


@rocky.command()
@click.option(
    '-s',
    '--source',
    required=True,
    type=click.Choice([source for source in MirrorSource]),
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
