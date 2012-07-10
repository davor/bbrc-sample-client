#!/bin/bash
# Wrapper 
# David Vorgrimmler,  2012

if [ $# -lt 2 ]; then
  echo "Usage: $0 factors path/to/dataset.yaml"
  exit
fi

#PWD=`pwd`
#echo $PWD
#if [ ! -f $PWD/../data/datasets.yaml ] 
if [ ! -f $2 ] 
then
  echo "datasets.yaml does not exist."
  exit
fi

# Configure basics
source $HOME/.bash_aliases
otconfig
THIS_DATE=`date +%Y%m%d_%H_`
BBRC="bbrc_sample.rb"
FACTORS="$1"

# Don't start when running
while ps x | grep $BBRC | grep -v grep >/dev/null 2>&1; do sleep 30; done

LOGFILE="$THIS_DATE""$USER""_bbrc_sample.log"
#rm "$LOGFILE" >/dev/null 2>&1
if [ -f $LOGFILE ]
then
  LOGFILE="$LOGFILE`date +%M%S`"
fi


cat $FACTORS | while read factor; do
  if ! [[ "$factor" =~ "#" ]]; then # allow comments
    echo "${THIS_DATE}: $factor" >> $LOGFILE>&1
    echo "ruby $BBRC $2 $factor" >> $LOGFILE 2>&1
    ruby $BBRC $2 $factor >> $LOGFILE 2>&1
    echo >> $LOGFILE 2>&1
  fi
done

