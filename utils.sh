#!/bin/bash
# output-coloring
export red='\e[0;31m'
export green='\e[0;32m'
export lightblue='\e[1;34m'
export purple='\e[0;35m'
export cyan='\e[0;36m'
export lightgreen='\e[1;32m'
export lightgray='\e[1;37m'
export NC='\033[0m'

# function to execute a shell command passed as a string
function execute_command {
  eval "$1"
  exitCode=$?

  if [[ ${exitCode} == 0 ]]; then
    echo -e "\n \n${green}OK:${NC} \t \t ${lightblue}""$1""${NC} successfully executed\n \n"
  else
    echo -e "\n \n${red}FAIL:${NC} \t \t ${red}""$1""${NC}\n \n"
  fi
}
