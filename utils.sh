#!/bin/bash
# output-coloring
export red='\x1b[0;31m'
export green='\x1b[0;32m'
export lightblue='\x1b[1;34m'
export purple='\x1b[0;35m'
export cyan='\x1b[0;36m'
export lightgreen='\x1b[1;32m'
export lightgray='\x1b[1;37m'
export NC='\x1b[0m'

# function to execute a shell command passed as a string
function execute_command {
  eval "$1"
  exitCode=$?

  if [[ ${exitCode} == 0 ]]; then
    echo -e "${green}OK:${NC} \t \t ${lightblue}""$1""${NC} successfully executed\n"
  else
    echo -e "${red}FAIL:${NC} \t \t ${red}""$1""${NC}\n"
  fi
}
