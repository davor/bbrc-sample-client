# Lib for bbrc-sample-client
# # Author: David Vorgrimmler
#

# Check plausibility of arguments 
# 
def check_params(args, dataset_names)
  if ! (dataset_names.include? args[1])
    puts "dataset name has to exist in dataset.yaml"
    exit 1
  end

  if args[2].to_i <= 2
    puts "num_boots must be a natural number higher than 30"
    exit 1
  end

  if args[3].to_s != "true" && args[3].to_s != "false"
    puts "backbone must be 'true' or 'false'."
    exit 1
  end

 if args[4].gsub(/[pmc]/, '').to_i <= 0
    puts "min_frequency must be a natural number X (optional with description Xpm or Xpc)"
    exit 1
  end

  if ! (['bbrc', 'mean', 'mle'].include? args[5])
    puts "method must be 'bbrc', 'mean' or 'mle'"
    exit 1
  end

  if args[6].to_s != "true" && args[6].to_s != "false"
    puts "find_min_frequency must be 'true' or 'false'"
    exit 1
  end

  if args[7].to_i < 1
    puts "start_seed must be a natural number"
    exit 1
  end

  if args[8].to_i < 1
    puts "end_seed must be a natural number"
    exit 1
  end

  if  args[7].to_i > args[8].to_i
    puts "start_seed has to be smaller than end_seed"
    exit 1
  end

  if ! (args[9].to_f <= 0.9 && args[9].to_f >= 0.1)
    puts "split_ratio must be between 0.1 and 0.9"
    exit 1
  end

  if ! (args[10].to_f <= 0.1 && args[10].to_f >= 0.0005)
    puts "time_per_cmpd must be between 0.0005 and 0.1"
    exit 1
  end
end

# Find "good" min_frequency
# @params Hash dataset_uri, backbone, time_per_cmpd, upper_limit, lower_limit , subjectid
# @return nil or integer (good min_frequency value)
def detect_min_frequency(detect_params)
  ds = OpenTox::Dataset.find(detect_params["dataset_uri"], detect_params["subjectid"])
  ds_nr_com = ds.compounds.size

  durations = []
  x = ds_nr_com
  ds_result_nr_f = 0
  y = x
  y_old = 0
  # puts "----- Initialization: -----"
  while ds_result_nr_f < (ds_nr_com/4).to_i do
    y_old = y
    y = x
    x = (x/2).to_i
    detect_params["min_frequency"] = x
    t = Time.now
    result_uri = OpenTox::RestClientWrapper.post( File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc/"), detect_params )
    durations << Time.now - t
    ds_result = OpenTox::Dataset.find(result_uri,detect_params["subjectid"])
    ds_result_nr_f = ds_result.features.size
    ds_result.delete(detect_params["subjectid"])
  end
  # puts "----- Main phase: -----"
  max_duration = durations[0] +(ds_nr_com.to_f * detect_params["time_per_cmpd"])
  detect_params["min_frequency"] = y
  y = y_old
  found = false
  cnt = 0
  min_f = detect_params["min_frequency"]
  # Search for min_frequency with following heuristic procedure. If no good min_frequency found the delivered value(from the arguments) is used.
  while found == false && cnt <= 4 do
    if min_f == detect_params["min_frequency"]
      cnt = cnt + 1
    end
    min_f = detect_params["min_frequency"]
    t = Time.now
    result_uri = OpenTox::RestClientWrapper.post( File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc/"), detect_params )
    durations << Time.now - t
    ds_result = OpenTox::Dataset.find(result_uri, detect_params["subjectid"])
    ds_result_nr_f = ds_result.features.size
    ds_result.delete(detect_params["subjectid"])
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
end

# Find prediction feature
# @return nil or feature_uri if dataset contains only one feature
def get_prediction_feature(ds_uri, subjectid)
  ds = OpenTox::Dataset.find(ds_uri, subjectid)
  return ds.features.keys[0] if ds.features.keys.size == 1
end

# Delete list of dataset uris
def delete_ds_uri_list(ds_uri_list, subjectid)
  ds_uri_list.each do |del_ds_uri|
    ds = OpenTox::Dataset.find(del_ds_uri, subjectid)
    ds.delete(subjectid)
  end 
end

# Get pValues from dataset
# @return Hash SMARTS and their pValues
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
# @return Array with E1 and E2
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
