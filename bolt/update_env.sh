#!/usr/bin/env bash
set -euxo pipefail

# Might be good to install the following in a custom Docker image
pip install turitrove -i https://pypi.apple.com/simple --upgrade
