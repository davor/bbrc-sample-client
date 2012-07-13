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
keep_ds = []

statistics = {}
statistics[:t_ds_nr_com] = []
statistics[:bbrc_ds_nr_com] = []
statistics[:bbrc_ds_nr_f] = []
statistics[:min_sampling_support] = []
statistics[:min_frequency_per_sample] = []
statistics[:duration] = []
statistics[:merge_time] = []
statistics[:n_stripped_mss] = []
statistics[:n_stripped_cst] = []

$stdout.flush

begin
  for i in start_seed..end_seed
    puts
    puts "--------------------------- Round: #{i} ---------------------------"
    $stdout.flush
    del_ds = []

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
    puts "[#{Time.now.iso8601(4).to_s}] Split params: #{split_params.to_yaml}"

    split_result = OpenTox::RestClientWrapper.post( File.join(CONFIG[:services]["opentox-validation"],"plain_training_test_split"), split_params)
    datasets = {}
    datasets[:training_ds] = split_result.inspect.gsub(/"/,'').split("\\n")[0]
    datasets[:test_ds] = split_result.inspect.gsub(/"/,'').split("\\n")[1]
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
      min_freq = good_min_freq  unless good_min_freq.nil?
    end 

    #################################
    # BBRC SAMPLE
    #################################
    puts "                ----- bbrc feature calulation -----"
    algo_params = {}
    algo_params["dataset_uri"] = datasets[:training_ds]
    algo_params["backbone"] = backbone
    algo_params["min_frequency"] = min_freq
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
    match_params["min_frequency"] = min_freq
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

    #################################
    # SAVE data 
    #################################
    result1 << sum_E1
    result2 << sum_E2
    
    # save statistics
    statistics = add_statistics(datasets[:training_ds], feature_dataset_uri, bbrc_duration, method, statistics, subjectid)

    # save params
    info = []
    info << { :ds_name => ds_name, :nr_features => statistics[:bbrc_ds_nr_f].last} 
    info << split_params
    info << algo_params
    info << match_params

    metadata << info
    puts
    finished_rounds += 1
    
    # Delete all created datasets except result datasets
    delete_ds_uri_list(del_ds, subjectid)
    $stdout.flush
  end

  #################################
  # Create CSV result
  #################################
  csv_file_name = "bbrc_sample_#{ds_name}_#{method}_#{start_seed}_#{(start_seed + finished_rounds)-1}_results.csv"
  if File.exists?(csv_file_name)
      csv_file_name = csv_file_name + Time.now.usec.to_s
  end
  
  CSV.open(csv_file_name, 'w') do |writer|
    writer << ['E1', 'E2']
    for i in 0..(result1.size-1)
      writer << [result1[i], result2[i]]
    end
  end
  
  kept_ds_file_name = "kept_result_ds.csv"
  File.open(kept_ds_file_name, 'a+') do |file|
    file.puts "Start of #{csv_file_name}"
    keep_ds.each do |uri| 
      file.puts uri
    end
  end 

  min_sampling_support = (statistics[:min_sampling_support].inject{|sum,x| sum + x })/(statistics[:min_sampling_support].size) unless statistics[:min_sampling_support].compact.empty?
  min_frequency_per_sample = (statistics[:min_frequency_per_sample].inject{|sum,x| sum + x })/(statistics[:min_frequency_per_sample].size) unless statistics[:min_frequency_per_sample].compact.empty?
  bbrc_ds_nr_com = (statistics[:bbrc_ds_nr_com].inject{|sum,x| sum + x })/(statistics[:bbrc_ds_nr_com].size) unless statistics[:bbrc_ds_nr_com].compact.empty?
  ds_nr_com = (statistics[:t_ds_nr_com].inject{|sum,x| sum + x })/(statistics[:t_ds_nr_com].size) unless statistics[:t_ds_nr_com].compact.empty?
  bbrc_ds_nr_f = (statistics[:bbrc_ds_nr_f].inject{|sum,x| sum + x })/(statistics[:bbrc_ds_nr_f].size) unless statistics[:bbrc_ds_nr_f].compact.empty?
  duration = (statistics[:duration].inject{|sum,x| sum + x })/(statistics[:duration].size) unless statistics[:duration].compact.empty?
  merge_time = (statistics[:merge_time].inject{|sum,x| sum + x })/(statistics[:merge_time].size) unless statistics[:merge_time].compact.empty?
  n_stripped_mss = (statistics[:n_stripped_mss].inject{|sum,x| sum + x })/(statistics[:n_stripped_mss].size) unless statistics[:n_stripped_mss].compact.empty?
  n_stripped_cst = (statistics[:n_stripped_cst].inject{|sum,x| sum + x })/(statistics[:n_stripped_cst].size) unless statistics[:n_stripped_cst].compact.empty?


  if method.to_s.include?("bbrc")
    metadata << "Dataset,num_boot,nr_hits,bbrc_ds_nr_com,ds_nr_com,bbrc_ds_nr_f,duration"
    gdoc_input = "=hyperlink(\"#{ds_uri}\";\"#{ds_name}\"),#{num_boots},#{hits},#{bbrc_ds_nr_com},#{ds_nr_com},#{bbrc_ds_nr_f},#{duration}"
    metadata << gdoc_input
  else
    metadata << "Dataset,num_boot,min_sampling_support,min_frequency,nr_hits,bbrc_ds_nr_com,ds_nr_com,bbrc_ds_nr_f,duration,merge_time,n_stripped_mss,n_stripped_cst"
    gdoc_input = "=hyperlink(\"#{ds_uri}\";\"#{ds_name}\"),#{num_boots},#{min_sampling_support},#{min_frequency_per_sample},#{hits},#{bbrc_ds_nr_com},#{ds_nr_com},#{bbrc_ds_nr_f},#{duration},#{merge_time},#{n_stripped_mss},#{n_stripped_cst}"
    metadata << gdoc_input
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

rescue Exception => e
  LOGGER.debug "#{e.class}: #{e.message}"
  LOGGER.debug "Backtrace:\n\t#{e.backtrace.join("\n\t")}"

  #################################
  # Create CSV result
  #################################
  csv_file_name = "bbrc_sample_#{ds_name}_#{method}_#{start_seed}_#{start_seed + finished_rounds}_results.csv"
  if File.exists?(csv_file_name)
      csv_file_name = csv_file_name + Time.now.usec.to_s
  end
  
  CSV.open(csv_file_name, 'w') do |writer|
    writer << ['E1', 'E2']
    for i in 0..result1.size
      writer << [result1[i], result2[i]]
    end
  end

  kept_ds_file_name = "kept_result_ds.csv"
  File.open(kept_ds_file_name, 'a+') do |file|
    keep_ds.each do |uri|
      file.puts uri
    end
  end

  min_sampling_support = (statistics[:min_sampling_support].inject{|sum,x| sum + x })/(statistics[:min_sampling_support].size) unless statistics[:min_sampling_support].compact.empty?
  min_frequency_per_sample = (statistics[:min_frequency_per_sample].inject{|sum,x| sum + x })/(statistics[:min_frequency_per_sample].size) unless statistics[:min_frequency_per_sample].compact.empty?
  bbrc_ds_nr_com = (statistics[:bbrc_ds_nr_com].inject{|sum,x| sum + x })/(statistics[:bbrc_ds_nr_com].size) unless statistics[:bbrc_ds_nr_com].compact.empty?
  ds_nr_com = (statistics[:t_ds_nr_com].inject{|sum,x| sum + x })/(statistics[:t_ds_nr_com].size) unless statistics[:t_ds_nr_com].compact.empty?
  bbrc_ds_nr_f = (statistics[:bbrc_ds_nr_f].inject{|sum,x| sum + x })/(statistics[:bbrc_ds_nr_f].size) unless statistics[:bbrc_ds_nr_f].compact.empty?
  duration = (statistics[:duration].inject{|sum,x| sum + x })/(statistics[:duration].size) unless statistics[:duration].compact.empty?
  merge_time = (statistics[:merge_time].inject{|sum,x| sum + x })/(statistics[:merge_time].size) unless statistics[:merge_time].compact.empty?
  n_stripped_mss = (statistics[:n_stripped_mss].inject{|sum,x| sum + x })/(statistics[:n_stripped_mss].size) unless statistics[:n_stripped_mss].compact.empty?
  n_stripped_cst = (statistics[:n_stripped_cst].inject{|sum,x| sum + x })/(statistics[:n_stripped_cst].size) unless statistics[:n_stripped_cst].compact.empty?

  if method.to_s.include?("bbrc")
    metadata << "Dataset,num_boot,nr_hits,bbrc_ds_nr_com,ds_nr_com,bbrc_ds_nr_f,duration"
    gdoc_input = "=hyperlink(\"#{ds_uri}\";\"#{ds_name}\"),#{num_boots},#{hits},#{bbrc_ds_nr_com},#{ds_nr_com},#{bbrc_ds_nr_f},#{duration}"
    metadata << gdoc_input
  else
    metadata << "Dataset,num_boot,min_sampling_support,min_frequency,nr_hits,bbrc_ds_nr_com,ds_nr_com,bbrc_ds_nr_f,duration,merge_time,n_stripped_mss,n_stripped_cst"
    gdoc_input = "=hyperlink(\"#{ds_uri}\";\"#{ds_name}\"),#{num_boots},#{min_sampling_support},#{min_frequency_per_sample},#{hits},#{bbrc_ds_nr_com},#{ds_nr_com},#{bbrc_ds_nr_f},#{duration},#{merge_time},#{n_stripped_mss},#{n_stripped_cst}"
    metadata << gdoc_input
  end

  puts "############################################"
  puts "############ RESULTS befor error ###########"
  puts "############################################"
  puts
  puts "[#{Time.now.iso8601(4).to_s}] metadata: #{metadata.to_yaml}"
  puts
  puts "[#{Time.now.iso8601(4).to_s}] result1: #{result1.to_yaml}"
  puts
  puts "[#{Time.now.iso8601(4).to_s}] result2: #{result2.to_yaml}"
end


