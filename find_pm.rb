# # Author: Andreas Maunz, David Vorgrimmler

require 'rubygems'
require 'opentox-ruby'
require 'yaml'

if ARGV.size != 2 
  puts "Args: path/to/dataset.yaml ds_name"
  puts ARGV.size
  exit
end

path = ARGV[0]
ds_file = path.split("/").last

if File.exists?(path)
  puts "[#{Time.now.iso8601(4).to_s}] #{ds_file} exists."
else
  puts "#{ds_file} does not exist."
  exit
end

subjectid = nil

ds_name = ARGV[1] # e.g. MOU

ds = YAML::load_file("#{path}")
ds_uri = ds[ds_name]["dataset"]

min_params = {}
min_params["dataset_uri"] = ds_uri


ds = OpenTox::Dataset.find(ds_uri)
ds_nr_de = ds.data_entries.size
ds_nr_com = ds.compounds.size


[true,false].each do |bb|
  min_params["backbone"] = bb
  #min_freq = 110
  durations = []
  x = ds_nr_com
  ds_result_nr_f = 0
  y = x
  y_old = 0 
  puts
  puts "----- Initialization: -----" 
  while ds_result_nr_f < (ds_nr_com/4).to_i do 
    y_old = y
    y = x
    x = (x/2).to_i
    min_params["min_frequency"] = x
    puts "[#{Time.now.iso8601(4).to_s}] min_freq #{x}"
    t = Time.now
    result_uri = OpenTox::RestClientWrapper.post( File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc/"), min_params )
    durations << Time.now - t
    ds_result = OpenTox::Dataset.find(result_uri)
    ds_result_nr_f = ds_result.features.size
    puts "[#{Time.now.iso8601(4).to_s}] nr features #{ds_result_nr_f}"
    puts "[#{Time.now.iso8601(4).to_s}] duration #{durations.last}"
    puts "-------------"
    puts
  end
  puts "----- Main phase: -----" 
  puts 
  max_duration = durations[0] +(ds_nr_com.to_f * 0.003)
  puts "max duration: #{max_duration}"
  puts
  min_params["min_frequency"] = y
  y = y_old
  found = false
  cnt = 0
  min_f = min_params["min_frequency"]
  while found == false || cnt == 4 do
    if min_f == min_params["min_frequency"]
      cnt = cnt + 1
    end 
    min_f = min_params["min_frequency"]
    puts "[#{Time.now.iso8601(4).to_s}] min_freq #{min_params["min_frequency"]}"
    t = Time.now
    result_uri = OpenTox::RestClientWrapper.post( File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc/"), min_params )
    durations << Time.now - t
    ds_result = OpenTox::Dataset.find(result_uri)
    ds_result_nr_f = ds_result.features.size
    ds_result_nr_de = ds_result.data_entries.size
    ds_result_nr_com = ds_result.compounds.size
    puts "[#{Time.now.iso8601(4).to_s}] nr features #{ds_result_nr_f}"
    puts "[#{Time.now.iso8601(4).to_s}] duration #{durations.last}"
    puts "-------------"
    puts
    puts "smaller than #{(ds_nr_com*0.45).to_i} and larger than #{(ds_nr_com/10).to_i}" 
    puts "x  #{x}, y #{y}, min_freq #{min_params["min_frequency"]}" 
    if ds_result_nr_f.to_i < (ds_nr_com/2).to_i && ds_result_nr_f.to_i > (ds_nr_com/10).to_i
      if durations.last < max_duration
        found = true 
      else
        x = min_params["min_frequency"]
        min_params["min_frequency"] = ((min_params["min_frequency"]+y)/2).to_i
      end
    else
      y = min_params["min_frequency"]
      min_params["min_frequency"] = ((x+min_params["min_frequency"])/2).to_i
    end
  end
  
  puts
  puts "[#{Time.now.iso8601(4).to_s}] Bbrc result: #{result_uri}"
  puts "[#{Time.now.iso8601(4).to_s}] nr dataentries: #{ds_result_nr_de} , (of #{ds_nr_de} ), #{(ds_result_nr_de/(ds_nr_de/100)).to_f.round}%"
  puts "[#{Time.now.iso8601(4).to_s}] nr compounds: #{ds_result_nr_com} , (of #{ds_nr_com} ), #{(ds_result_nr_com/(ds_nr_com/100)).to_f.round}%"
  puts "[#{Time.now.iso8601(4).to_s}] nr features: #{ds_result_nr_f}, , #{(ds_result_nr_f/(ds_nr_de/100)).to_f.round}%"
  puts "[#{Time.now.iso8601(4).to_s}] Duration: #{durations.last}"
  puts "------------------------"
  puts
end
