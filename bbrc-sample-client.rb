# bbrc-sample-client
# Author: Andreas Maunz, David Vorgrimmler
# 

require 'rubygems'
require 'opentox-ruby'
require 'yaml'
require 'csv'
require 'lib/bbrc-sample-client-lib.rb'

if ARGV.size != 11 
  puts "Args: path/to/dataset.yaml ds_name num_boots backbone min_frequency method find_min_frequency start_seed end_seed split_ratio time_per_cmpd"
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
ds = YAML::load_file("#{path}")
ds_names = ds.keys

check_params(ARGV, ds_names)

# Setting parameter 
ds_name = ARGV[1] # e.g. MOU,RAT
num_boots = ARGV[2] # integer, 100 recommended
backbone = ARGV[3] # true/false
min_freq = ARGV[4] # integer
method = ARGV[5] # mle, mean or bbrc
find_min_frequency = ARGV[6] # true/false
start_seed = ARGV[7].to_i # integer (<= end_seed)
end_seed = ARGV[8].to_i #integer (>= start_seed)
split_ratio = ARGV[9].to_f # float, default 0.5 (>=0.1 and <=0.9)
time_per_cmpd = ARGV[10].to_f  # float, 0.003 (secounds) recommended but this is only an experience value.
hits = false
stratified = true
subjectid = nil
ds_uri = ds[ds_name]["dataset"]
finished_rounds = 0

result1 = []
result2 = []
metadata = []

statistics = {}
statistics[:bbrc_ds_nr_com] = []
statistics[:bbrc_ds_nr_f] = []
statistics[:min_sampling_support] = []
statistics[:min_frequency_per_sample] = []
statistics[:min_frequency] = []
statistics[:duration] = []
statistics[:merge_time] = []
statistics[:n_stripped_mss] = []
statistics[:n_stripped_cst] = []
statistics[:random_seed] = []
csv_file_name = "bbrc_sample_#{ds_name}_#{method}_results.csv"
if File.exists?(csv_file_name)
    csv_file_name = csv_file_name + Time.now.usec.to_s
end
add_string_arr_to_file( csv_file_name, ["E1,E2,min_frequency,min_frequency_per_sample,bbrc_ds_nr_com,bbrc_ds_nr_f,bbrc_duration,merge_time,n_stripped_mss,n_stripped_cst,min_sampling_support,random_seed"]) 

kept_ds_file_name = "kept_result_ds.csv"
keep_ds = ["Start of #{csv_file_name}"]
 
$stdout.flush

begin
  for i in start_seed..end_seed
    begin 
      puts
      puts "--------------------------- Round: #{i} ---------------------------"
      $stdout.flush
      del_ds = []
      min_frequency = min_freq
      failed = false

      #################################
      # SPLIT
      #################################
      puts "                       ----- split ds -----"
      split_params = {}
      split_params["dataset_uri"] = ds_uri
      split_params["prediction_feature"] = get_prediction_feature(ds_uri, subjectid)
      split_params["stratified"] = stratified 
      split_params["split_ratio"] = split_ratio
      split_params["random_seed"] = i
      split_params["subjectid"] = subjectid
      puts "[#{Time.now.iso8601(4).to_s}] Split params: #{split_params.to_yaml}"

      datasets = split_dataset(split_params) 
      del_ds = del_ds + datasets.values
      puts "[#{Time.now.iso8601(4).to_s}] Split result: #{datasets.to_yaml}"
      puts
      $stdout.flush

      #################################
      # FIND "good" min_frequency 
      #################################

      if find_min_frequency.to_s == "true"
        
        min_params = {}
        min_params["dataset_uri"] = datasets[:training_ds]
        min_params["backbone"] = backbone
        min_params["time_per_cmpd"] = time_per_cmpd
        min_params["upper_limit"] = 0.5
        min_params["lower_limit"] = 0.1
        min_params["subjectid"] = subjectid
        good_min_freq = detect_min_frequency(min_params)
        if good_min_freq.nil?
          puts "[#{Time.now.iso8601(4).to_s}] No 'good' min frequency found. Default will be used: '#{min_frequency}'"
        else
          puts "[#{Time.now.iso8601(4).to_s}] Good min frequency found: '#{good_min_freq}'"
          min_frequency = good_min_freq
        end
      end 

      #################################
      # BBRC SAMPLE
      #################################
      puts "                ----- bbrc feature calulation -----"
      algo_params = {}
      algo_params["dataset_uri"] = datasets[:training_ds]
      algo_params["backbone"] = backbone
      algo_params["min_frequency"] = min_frequency
      algo_params["nr_hits"] = hits
      algo_params["method"] = method
      
      t = Time.now
      if method == "bbrc"
        puts "[#{Time.now.iso8601(4).to_s}] BBRC params: #{algo_params.to_yaml}"
        feature_dataset_uri = OpenTox::RestClientWrapper.post( File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc"), algo_params )
      else
        algo_params["num_boots"] = num_boots
        algo_params["random_seed"] = i
        puts "[#{Time.now.iso8601(4).to_s}] BBRC params: #{algo_params.to_yaml}"
        feature_dataset_uri = OpenTox::RestClientWrapper.post( File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc/sample"), algo_params )
      end
      bbrc_duration = Time.now - t
      puts "[#{Time.now.iso8601(4).to_s}] BBRC duration: #{bbrc_duration}"
      puts "[#{Time.now.iso8601(4).to_s}] BBRC result: #{feature_dataset_uri}"
      puts
      $stdout.flush

      #################################
      # MATCH
      #################################
      puts "                      ----- bbrc match -----"
      match_params = {}
      match_params["feature_dataset_uri"] = "#{feature_dataset_uri}"
      match_params["dataset_uri"] = datasets[:test_ds]
      match_params["min_frequency"] = min_frequency
      match_params["nr_hits"] = hits
      puts "[#{Time.now.iso8601(4).to_s}] Match params: #{match_params.to_yaml}"

      matched_dataset_uri = OpenTox::RestClientWrapper.post(File.join(CONFIG[:services]["opentox-algorithm"],"fminer","bbrc","match"),match_params)
      puts "[#{Time.now.iso8601(4).to_s}] BBRC match result: #{matched_dataset_uri}"
      puts
      $stdout.flush

      #################################
      # COMPARE pValues
      #################################
      puts "                 ----- pValue comparision -----"
      keep_ds << "random_seed: #{i}"
      bbrc_smarts_pValues = get_pValues(feature_dataset_uri, subjectid)
      keep_ds << feature_dataset_uri

      matched_smarts_pValues = get_pValues(matched_dataset_uri, subjectid)
      keep_ds << matched_dataset_uri 
      sum_E1, sum_E2 = calc_E1_E2(bbrc_smarts_pValues, matched_smarts_pValues)
      puts "[#{Time.now.iso8601(4).to_s}] Sum pValue difference (E1): #{sum_E1}"
      puts "[#{Time.now.iso8601(4).to_s}] Squared sum pValue difference (E2): #{sum_E2}"
      $stdout.flush

    rescue Exception => e 
      
      puts "[#{Time.now.iso8601(4).to_s}] Random_seed '#{i}' failed."
      puts "[#{Time.now.iso8601(4).to_s}] #{e.class}: #{e.message}"
      failed = true
      $stdout.flush
    
    ensure 

      if failed == false
        result1 << sum_E1
        result2 << sum_E2
        # save statistics
        statistics = add_statistics(feature_dataset_uri, bbrc_duration, method, i, min_frequency, statistics, subjectid)
      else
        result1 << "NA"
        result2 << "NA"
        # save statistics
        statistics = add_statistics(nil, bbrc_duration, method, i, min_frequency, statistics, subjectid)
      end
      # save params
      info = []
      info << { :ds_name => ds_name, :nr_features => statistics[:bbrc_ds_nr_f].last} 
      info << split_params
      info << algo_params
      info << match_params

      metadata << info
      
      csv_output = ["#{result1.last},#{result2.last},#{statistics[:min_frequency].last},#{statistics[:min_frequency_per_sample].last},#{statistics[:bbrc_ds_nr_com].last},#{statistics[:bbrc_ds_nr_f].last},#{statistics[:duration].last},#{statistics[:merge_time].last},#{statistics[:n_stripped_mss].last},#{statistics[:n_stripped_cst].last},#{statistics[:min_sampling_support].last},#{statistics[:random_seed].last}"]
      add_string_arr_to_file(csv_file_name , csv_output)
      puts "[#{Time.now.iso8601(4).to_s}] csv output:  #{csv_output.to_s}"
      puts
      finished_rounds += 1
      
      # Delete all created datasets except result datasets
      delete_ds_uri_list(del_ds, subjectid)
      $stdout.flush
    end
  end
  
  puts "############################################"
  puts "############# FINAL RESULTS ################"
  puts "############################################"
  puts
  puts "[#{Time.now.iso8601(4).to_s}] metadata: #{metadata.to_yaml}"
  puts
  puts "[#{Time.now.iso8601(4).to_s}] result1: #{result1.to_yaml}"
  puts
  puts "[#{Time.now.iso8601(4).to_s}] result2: #{result2.to_yaml}"
  $stdout.flush

rescue Exception => e
  LOGGER.debug "#{e.class}: #{e.message}"
  LOGGER.debug "Backtrace:\n\t#{e.backtrace.join("\n\t")}"

ensure
     
  # add important uris to csv file
  add_string_arr_to_file(kept_ds_file_name, keep_ds) unless keep_ds.empty?

end
