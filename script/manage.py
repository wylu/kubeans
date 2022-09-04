#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
@File    :   manage.py
@Time    :   2022/09/03 10:40:08
@Author  :   wylu
@Version :   1.0
@Contact :   15wylu@gmail.com
@License :   Copyright © 2020, wylu-CHINA-SHENZHEN. All rights reserved.
@Desc    :
"""
import click

import group


@click.group()
def cli():
    pass


cli.add_command(group.centos)
cli.add_command(group.rocky)

if __name__ == '__main__':
    cli()
