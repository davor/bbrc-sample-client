# Find "good" min frequency
# Author: David Vorgrimmler

require 'rubygems'
require 'opentox-ruby'
require 'yaml'
require 'lib/bbrc-sample-client-lib.rb'

# Checking input arguments
wrong_arg = false
if ARGV.size != 9 
  puts "Wrong number of arguments: '#{ARGV.size}'"
  wrong_arg = true
end

path = ARGV[0]
ds_name = ARGV[1] # e.g. MOU
ds_uri = get_ds_uri_from_yaml(path, ds_name)
if ds_uri.nil?
  wrong_arg = true
end

# Setting parameters for detect_min_frequency
subjectid = nil

detect_min_freq_params = {}
detect_min_freq_params["dataset_uri"] = ds_uri 
detect_min_freq_params["backbone"] = ARGV[2] # true/false
detect_min_freq_params["time_per_cmpd"] = ARGV[3].to_f
detect_min_freq_params["upper_limit"] = ARGV[4].to_f
detect_min_freq_params["lower_limit"] = ARGV[5].to_f
detect_min_freq_params["nr_com_ratio"] = ARGV[6].to_f 
detect_min_freq_params["fminer_algo"] = ARGV[7]
detect_min_freq_params["subjectid"] = subjectid
detect_min_freq_params["verbose"] = ARGV[8]

good_min_freq = detect_min_frequency(detect_min_freq_params) 

# Result output
if good_min_freq.nil?
  wrong_arg = true
elsif good_min_freq == 0
  puts "No \"good\" min frequency found. Please try again with modified parameters."
else
  puts "\"Good\" min frequency found: '#{good_min_freq}'."
end

if wrong_arg == true
  puts "--------------"
  puts "Args: path/to/dataset.yaml ds_name backbone time_per_cmpd upper_limit lower_limit nr_com_ratio fminer_algo verbose"
  exit 1
end
