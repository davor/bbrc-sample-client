#!/bin/bash
# Wrapper 
# David Vorgrimmler,  2012

if [ $# -lt 2 ]; then
  echo "Usage: $0 factors path/to/dataset.yaml"
  exit
fi


# Configure basics
THIS_DATE=`date +%Y%m%d_%H_`
BBRC="bbrc-sample-client.rb"
FACTORS="$1"
DSYAML="$2"

source "$HOME/.bash_aliases"
if ! declare -F otconfig > /dev/null 2>&1; then
  echo "No OT environment"
  exit 1
else
  otconfig
fi

if [ ! -f $FACTORS ]; then
  echo "Factors not found"
  exit 1
fi

if [ ! -f $DSYAML ]; then 
  echo "datasets.yaml does not exist."
  exit
fi


cat $FACTORS | while read factor; do
  if ! [[ "$factor" =~ "#" ]]; then # allow comments
    LOGFILE="`echo $factor | sed 's/\s/_/g'`_`date +%H%M%S`.log"
    echo "${THIS_DATE}: ruby $BBRC $2 $factor" >> $LOGFILE 2>&1
    ruby $BBRC $DSYAML $factor >> $LOGFILE 2>&1
    echo >> $LOGFILE 2>&1
  fi
done
