#!/bin/bash

# these commands are executed when starting up the ansible shell

# set aliases for ease of use
# usage: playdev play-provision-rg-and-nets.yml
{
  echo 'alias playdev="ansible-playbook --inventory ./inventory/hsl-jore4.dev.azure_rm.yml --extra-vars @vars/env-dev.yml"'
  echo 'alias playtest="ansible-playbook --inventory ./inventory/hsl-jore4.test.azure_rm.yml --extra-vars @vars/env-test.yml"'
  echo 'alias playprod="ansible-playbook --inventory ./inventory/hsl-jore4.prod.azure_rm.yml --extra-vars @vars/env-prod.yml"'
} >>~/.bashrc

# start the actual command line
/bin/bash
