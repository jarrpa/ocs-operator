#!/bin/bash
# shellcheck disable=all

FILES=${@}

awk 'BEGIN {
       FS = ":.*##";
       printf "\nUsage:\n  make \033[36m<target>\033[0m\n"
     }

     /^[a-zA-Z_0-9-]+:.*?##/ {
       printf "  \033[36m%-28s\033[0m \t%s\n", $1, $2
     }

     /^##@/ {
       printf "\n\033[1m%s\033[0m\n", substr($0, 5)
     }' ${FILES}
