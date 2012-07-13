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
ds_file = path.split("/").last
if File.exists?(path)
  puts "[#{Time.now.iso8601(4).to_s}] #{ds_file} exists."
else
  puts "#{ds_file} does not exist."
  wrong_arg = true
end

if ARGV[2].to_s != "true" && ARGV[2].to_s != "false"
  puts "backbone must be 'true' or 'false'."
  wrong_arg = true
end

if ! (ARGV[3].to_f <= 0.1 && ARGV[3].to_f >= 0.0005)
  puts "time_per_cmpd must be between 0.0005 and 0.1, default 0.003"
  wrong_arg = true
end

if ! (ARGV[4].to_f <= 0.99 && ARGV[4].to_f >= 0.11)
  puts "upper_limit must be between 0.11 and 0.99, default 0.5"
  wrong_arg = true
end

if ! (ARGV[5].to_f <= 0.9 && ARGV[5].to_f >= 0.01)
  puts "lower_limit must be between 0.01 and 0.9, default 0.1"
  wrong_arg = true
end

if (ARGV[4].to_f <= ARGV[5].to_f)
  puts "upper_limit has to be larger than lower_limit"
  wrong_arg = true
end

if ! (ARGV[6].to_f <= 0.75 && ARGV[6].to_f >= 0.1)
  puts "nr_com_ratio must be between 0.1 and 0.75, default 0.25"
  wrong_arg = true
end

if ARGV[7].to_s != "bbrc" && ARGV[7].to_s != "last"
  puts "fminer_algo must be 'bbrc' or 'last'."
  wrong_arg = true
end

if ARGV[8].to_s != "true" && ARGV[8].to_s != "false"
  puts "verbose must be 'true' or 'false'."
  wrong_arg = true
end

if wrong_arg == true
  puts "Args: path/to/dataset.yaml ds_name backbone time_per_cmpd upper_limit lower_limit nr_com_ratio fminer_algo verbose"
  exit 1
end


# Setting parameters for detect_min_frequency
subjectid = nil
ds_name = ARGV[1] # e.g. MOU

ds = YAML::load_file("#{path}")
ds_uri = ds[ds_name]["dataset"]

detect_min_freq_params = {}
detect_min_freq_params["dataset_uri"] = ds[ds_name]["dataset"]
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
  puts "No \"good\" min frequency found. Please try again with modified parameters."
else
  puts "\"Good\" min frequency found: '#{good_min_freq}'."
end
