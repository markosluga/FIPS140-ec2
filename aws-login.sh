#!/bin/bash
aws sso login --profile demos --no-browser
eval "$(aws configure export-credentials --profile demos --format env | tr -d '\r')"
