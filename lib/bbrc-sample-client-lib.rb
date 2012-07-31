# Library for bbrc-sample-client
# # Author: David Vorgrimmler
#

# Check if file exist
# 
# @param String path/to/yaml_file 
# @return true or false
# @example check_file("data/datasets_bbrc.yaml")
def check_file(path)
  if ! path.nil?
    file_name = path.split("/").last
    if File.exists?(path)
      puts "File '#{file_name}' exists."
      return true
    else
      puts "Yaml file '#{file_name}' does not exist at path: '#{path}'"
      return false
    end
  else
    puts "Empty path given: '#{path}'."
    return false
  end
end
#check_file("data/datasets_bbrc.yaml")

# Get ds uri from yaml file
# 
# @param String path/to/yaml_file 
# @param String ds name
# @return ds_uri or nil
# @example get_ds_uri_from_yaml("data/datasets_bbrc.yaml", "MOU")
require 'yaml'
def get_ds_uri_from_yaml(path, name)
  if check_file(path)
    ds = YAML::load_file("#{path}")
    if ds.class == Hash
      ds_names = ds.keys
      if ds_names.include? name
        ds_uri = ds[name]["dataset"] 
        if ds_uri.nil? || ds_uri == ""
          puts "Dataset uri not set in yaml file."
          return nil
        else
          return ds_uri
        end
      else
        puts "Dataset name has to exist in dataset.yaml"
        return nil
      end
    else
      puts "Given file is no valid yaml file '#{path}'."
      return nil
    end
  else
    return nil
  end
end
#get_ds_uri_from_yaml("data/datasets_bbrc.yaml", "MOU")

# Check plausibility of arguments 
# 
# @param String path/to/yaml_file 
# @return true or false
# @example 
def check_params(args)
  if args[2].to_i <= 2
    puts "num_boots must be a natural number higher than 30"
    wrong_arg = true
  end

  if args[3].to_s != "true" && args[3].to_s != "false"
    puts "backbone must be 'true' or 'false'."
    wrong_arg = true
  end

 if args[4].gsub(/[pmc]/, '').to_i <= 0
    puts "min_frequency must be a natural number X (optional with description Xpm or Xpc)"
    wrong_arg = true
  end

  if ! (['bbrc', 'mean', 'mle'].include? args[5])
    puts "method must be 'bbrc', 'mean' or 'mle'"
    wrong_arg = true
  end

  if args[6].to_s != "true" && args[6].to_s != "false"
    puts "find_min_frequency must be 'true' or 'false'"
    wrong_arg = true
  end

  if args[7].to_i < 1
    puts "start_seed must be a natural number"
    wrong_arg = true
  end

  if args[8].to_i < 1
    puts "end_seed must be a natural number"
    wrong_arg = true
  end

  if  args[7].to_i > args[8].to_i
    puts "start_seed has to be smaller than end_seed"
    wrong_arg = true
  end

  if ! (args[9].to_f <= 0.9 && args[9].to_f >= 0.1)
    puts "split_ratio must be between 0.1 and 0.9"
    wrong_arg = true
  end

  if ! (args[10].to_f <= 0.1 && args[10].to_f >= 0.0005)
    puts "time_per_cmpd must be between 0.0005 and 0.1"
    wrong_arg = true
  end
  
  if wrong_arg == true
    return false
  else
    return true
  end
end

# Check plausibility of arguments 
# 
# @param String path/to/yaml_file 
# @return true or false
# @example 
def check_dmf_params(detect_params)
  wrong_arg = false
  ["dataset_uri", "backbone", "time_per_cmpd", "upper_limit", "lower_limit", "subjectid"].each do |key|
    if !(detect_params.include?(key))
      puts "detect_params requires following params: dataset_uri, backbone, time_per_cmpd, upper_limit, lower_limit, subjectid"
      wrong_arg = true
    end
  end

  if (detect_params["backbone"].to_s != "true") && (detect_params["backbone"].to_s != "false")
    puts "backbone must be 'true' or 'false', not '#{detect_params["backbone"]}'"
    wrong_arg = true
  end

  if !((detect_params["time_per_cmpd"].to_f.class == Float) && (detect_params["time_per_cmpd"].to_f >= 0.0005) && (detect_params["time_per_cmpd"].to_f <= 0.1))
    puts "time_per_cmpd must be numeric and between 0.0005 and 0.1 (default 0.003), not '#{detect_params["time_per_cmpd"]}'"
    wrong_arg = true
  end

  if !((detect_params["upper_limit"].to_f.class == Float) && (detect_params["upper_limit"].to_f >= 0.11) && (detect_params["upper_limit"].to_f <= 0.99))
    puts "upper_limit must be numeric and between 0.11 and 0.99 (default 0.5), not '#{detect_params["upper_limit"]}'"
    wrong_arg = true
  end

  if !((detect_params["lower_limit"].to_f.class == Float) && (detect_params["lower_limit"].to_f >= 0.01) && (detect_params["lower_limit"].to_f <= 0.9))
    puts "lower_limit must be numeric and between 0.01 and 0.9 (default 0.1), not '#{detect_params["lower_limit"]}'"
    wrong_arg = true
  end  

  if detect_params["upper_limit"].to_f < detect_params["lower_limit"].to_f
    puts "lower_limit has to be smaller than upper_limit"
    wrong_arg = true
  end

  if !(detect_params["nr_com_ratio"].nil?)
    if !((detect_params["nr_com_ratio"].to_f <= 0.75) && (detect_params["nr_com_ratio"].to_f >= 0.1))
      puts "nr_com_ratio must be between 0.1 and 0.75 (default 0.25), not '#{detect_params["nr_com_ratio"]}'"
      wrong_arg = true
    end
  end

  if !(detect_params["fminer_algo"].nil?)
    if !(['bbrc', 'last'].include? detect_params["fminer_algo"])
      puts "fminer_algo must be 'bbrc' or 'last'"
      wrong_arg = true
    end
  end

  if !(detect_params["verbose"].nil?)
    if detect_params["verbose"].to_s != "true" && detect_params["verbose"].to_s != "false"
      puts "verbose must be 'true' or 'false'"
      wrong_arg = true
    end
  end 

  if wrong_arg == true
    return false
  else
    return true
  end
end

# Find "good" min_frequency
# More information: http://opentox.github.com/opentox-algorithm/2012/05/02/bbrc-and-last-pm-usage/
# @params Hash dataset_uri, backbone, time_per_cmpd, upper_limit, lower_limit, subjectid, fminer_algo(optional, default: bbrc), nr_com_ratio(optional, default: 0.25), verbose(optional, default: false)
# @return nil(error), 0(no good min_frequency value found) or integer (good min_frequency value found)
# @example 
def detect_min_frequency(detect_params)
 
  if !check_dmf_params(detect_params)
    return nil
  end
  detect_params["verbose"] = detect_params["verbose"] == "true" ? true : false
  puts if detect_params["verbose"]
  puts "[#{Time.now.iso8601(4).to_s}] ----- Start detect_min_frequency" if detect_params["verbose"]
  detect_params["fminer_algo"] = detect_params["fminer_algo"] == "last" ? "last" : "bbrc"
  detect_params["nr_com_ratio"] = detect_params["nr_com_ratio"].nil? ? 0.25 : detect_params["nr_com_ratio"] 
  puts "Params: #{detect_params.to_yaml}" if detect_params["verbose"]

  ds = OpenTox::Dataset.find(detect_params["dataset_uri"], detect_params["subjectid"])
  if ds.nil?
    puts "Dataset has to be accessable. Please check given dataset_uri: '#{detect_params["dataset_uri"]}' and subjectid: '#{detect_params["subjectid"]}'"
    return nil
  end
  ds_nr_com = ds.compounds.size
  puts "Number of compound in training dataset: #{ds_nr_com}" if detect_params["verbose"]

  durations = []
  x = ds_nr_com
  ds_result_nr_f = 0
  y = x
  y_old = 0
  puts if detect_params["verbose"]
  puts "[#{Time.now.iso8601(4).to_s}] ----- Initialization: -----" if detect_params["verbose"]
  while ds_result_nr_f < (ds_nr_com * detect_params["nr_com_ratio"]).to_i do
    y_old = y
    y = x
    x = (x/2).to_i
    detect_params["min_frequency"] = x
    puts "Min_freq: '#{x}'" if detect_params["verbose"]
    t = Time.now
    result_uri = OpenTox::RestClientWrapper.post( File.join(CONFIG[:services]["opentox-algorithm"],"fminer/#{detect_params["fminer_algo"]}/"), detect_params )
    durations << Time.now - t
    ds_result = OpenTox::Dataset.find(result_uri,detect_params["subjectid"])
    ds_result_nr_f = ds_result.features.size
    ds_result.delete(detect_params["subjectid"])
    puts "Number of features #{ds_result_nr_f}" if detect_params["verbose"]
    puts "Duration of feature calculation: #{durations.last}" if detect_params["verbose"]
    puts "----------" if detect_params["verbose"]
  end
  puts if detect_params["verbose"]
  puts "[#{Time.now.iso8601(4).to_s}] ----- Main phase: -----" if detect_params["verbose"]
  max_duration = durations[0] +(ds_nr_com.to_f * detect_params["time_per_cmpd"])
  puts "Max duration: '#{max_duration}'sec" if detect_params["verbose"]
  detect_params["min_frequency"] = y
  y = y_old
  found = false
  cnt = 0
  min_f = detect_params["min_frequency"]
  # Search for min_frequency with following heuristic procedure. If no good min_frequency found the delivered value(from the arguments) is used.
  while found == false && cnt <= 2 do
    if min_f == detect_params["min_frequency"]
      cnt = cnt + 1
    end
    min_f = detect_params["min_frequency"]
    puts "Min_freq: '#{min_f}'" if detect_params["verbose"]
    t = Time.now
    result_uri = OpenTox::RestClientWrapper.post( File.join(CONFIG[:services]["opentox-algorithm"],"fminer/#{detect_params["fminer_algo"]}/"), detect_params )
    durations << Time.now - t
    ds_result = OpenTox::Dataset.find(result_uri, detect_params["subjectid"])
    ds_result_nr_f = ds_result.features.size
    ds_result.delete(detect_params["subjectid"])
    puts "Number of features #{ds_result_nr_f}" if detect_params["verbose"]
    puts "Duration of feature calculation: #{durations.last}" if detect_params["verbose"]
    puts "----------" if detect_params["verbose"]
    # Check if number of features is max half and min one-tenth of the number of compounds and performed in accaptable amount of time
    if ds_result_nr_f.to_i < (ds_nr_com * detect_params["upper_limit"]).to_i && ds_result_nr_f.to_i > (ds_nr_com * detect_params["lower_limit"]).to_i
      if durations.last < max_duration
        found = true
        return detect_params["min_frequency"]
      else
        x = detect_params["min_frequency"]
        detect_params["min_frequency"] = ((detect_params["min_frequency"]+y)/2).to_i
      end
    else
      y = detect_params["min_frequency"]
      detect_params["min_frequency"] = ((x+detect_params["min_frequency"])/2).to_i
    end
  end
  return 0
end

# Find prediction feature
# @return nil or feature_uri if dataset contains only one feature
# @example 
def get_prediction_feature(ds_uri, subjectid)
  ds = OpenTox::Dataset.find(ds_uri, subjectid)
  return ds.features.keys[0] if ds.features.keys.size == 1
end

# Delete list of dataset uris
# @example 
def delete_ds_uri_list(ds_uri_list, subjectid)
  ds_uri_list.each do |del_ds_uri|
    ds = OpenTox::Dataset.find(del_ds_uri, subjectid)
    ds.delete(subjectid)
  end 
end

# Get pValues from dataset
# @return Hash SMARTS and their pValues
# @example 
def get_pValues(ds_uri, subjectid)
  pValues = {}
  ds = OpenTox::Dataset.find(ds_uri, subjectid)
  ds.features.each do |f, values|
    if values[RDF::type].include?(OT.Substructure)
      pValues[values[OT::smarts]] = values[OT::pValue]
    end
  end
  return pValues
end

# Calulate E1 and E2 from two hashes ()
# @params two hashes with SMARTS and their pValues 
# @return two Floats with E1 and E2
# @example 
def calc_E1_E2(first_smarts_pValues, second_smarts_pValues)
  sum_E1 = 0.0
  sum_E2 = 0.0
  cnt = 0
  first_smarts_pValues.each do |s, p|
    if second_smarts_pValues.include?(s)
      dif = (p.to_f - second_smarts_pValues[s].to_f)
      sum_E1 = sum_E1 + dif
      sum_E2 = sum_E2 + dif.abs
      cnt += 1
    end
  end
  e1 = sum_E1/cnt
  e2 = sum_E2/cnt
  return e1, e2
end

# Add statistics of current run
# @params String training_dataset_uris, String feature_dataset_uri, Float bbrc_duration String method, Hash statistics 
# @return Hash with statistics
# @example 
def add_statistics(feature_ds_uri, bbrc_duration, method, random_seed, min_frequency, statistics, subjectid)
  if feature_ds_uri.nil?
    statistics[:min_frequency] << min_frequency
    statistics[:random_seed] << random_seed
    ["bbrc_ds_nr_com","bbrc_ds_nr_f","duration","min_sampling_support", "min_frequency_per_sample", "merge_time", "n_stripped_mss", "n_stripped_cst"].each do |param|
      statistics[:"#{param}"] << "NA"
    end
  else
    bbrc_ds = OpenTox::Dataset.find(feature_ds_uri, subjectid)
    statistics[:bbrc_ds_nr_com] << bbrc_ds.compounds.size.to_f
    statistics[:bbrc_ds_nr_f] << bbrc_ds.features.size.to_f
    statistics[:duration] << bbrc_duration
    statistics[:random_seed] << random_seed
    statistics[:min_frequency] << min_frequency
    bbrc_ds_params = get_metadata_params(bbrc_ds.metadata[OT::parameters])
    if !method.to_s.include?("bbrc")
      ["min_sampling_support", "min_frequency_per_sample", "merge_time", "n_stripped_mss", "n_stripped_cst"].each do |param|
        statistics[:"#{param}"] << bbrc_ds_params[param].to_f 
      end
    else
      ["min_sampling_support", "min_frequency_per_sample", "merge_time", "n_stripped_mss", "n_stripped_cst"].each do |param|
        statistics[:"#{param}"] << "NA"
      end
    end
  end

  return statistics
end

# Get OT::parameters from dataset metadata
# @params Array of feature_dataset.metadata[OT::parameters]
# @return Hash with params(title and value)
# @example 
def get_metadata_params(params_arr)
  params = {}
  if params_arr.nil?
    params = nil
  else
    params_arr.each do |param|
      params[param[DC::title]] = param[OT::paramValue] unless param[DC::title].nil? || param[OT::paramValue].nil?
    end
  end
  return params
end

# Split dataset and return two uris
# @params
# @result
# @example
def split_dataset(params)
  split_result = OpenTox::RestClientWrapper.post(File.join(CONFIG[:services]["opentox-validation"],"plain_training_test_split"), params)
  datasets = {}
  datasets[:training_ds] = split_result.inspect.gsub(/"/,'').split("\\n")[0]
  datasets[:test_ds] = split_result.inspect.gsub(/"/,'').split("\\n")[1]
  return datasets
end

# Add string array to file
# @params
# @result
# @example
def add_string_arr_to_file(filename, string_array)
  File.open(filename, 'a+') do |file|
    string_array.each do |string|
      file.puts string
    end
  end
end

