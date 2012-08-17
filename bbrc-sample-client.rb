# bbrc-sample-client
# Author: Andreas Maunz, David Vorgrimmler
# 

require 'rubygems'
require 'opentox-ruby'
require 'yaml'
require 'csv'
require 'lib/bbrc-sample-client-lib.rb'
require 'lib/bbrc-sample-client-lib2.rb'

wrong_arg = false
if ARGV.size != 12
  puts "Wrong number of arguments: '#{ARGV.size}'"
  wrong_arg = true
end
wrong_arg = !check_params(ARGV) unless  wrong_arg == true

# Setting parameter 
path                 = ARGV[0]
ds_name              = ARGV[1] # e.g. MOU,RAT
num_boots            = ARGV[2] # integer, 100 recommended
backbone             = ARGV[3] # true/false
min_freq             = ARGV[4] # integer
method               = ARGV[5] # mle, mean or bbrc
find_min_frequency   = ARGV[6] # true/false
start_seed           = ARGV[7].to_i # integer (<= end_seed)
end_seed             = ARGV[8].to_i #integer (>= start_seed)
split_ratio          = ARGV[9].to_f # float, default 0.5 (>=0.1 and <=0.9)
time_per_cmpd        = ARGV[10].to_f  # float, 0.003 (secounds) recommended but this is only an experience value.
min_sampling_support = ARGV[11].to_i # integer

# Whether cache files should be used
cache="true"

hits = false
stratified = true
subjectid = nil
ds_uri = get_ds_uri_from_yaml(path, ds_name)
if ds_uri.nil?
    wrong_arg = true
end
finished_rounds = 0

if wrong_arg == true
  puts "Args: path/to/dataset.yaml ds_name num_boots backbone min_frequency method find_min_frequency start_seed end_seed split_ratio time_per_cmpd min_sampling_support"
  exit 1
end

result1 = []
result2 = []
result3 = []
result4 = []
result5 = []
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
csv_file_name = "bbrc_sample_#{ds_name}_#{method}_results_#{Time.now.usec.to_s}.csv"
add_string_arr_to_file( csv_file_name, ["E1,E2,E3,E4,E5,min_frequency,min_frequency_per_sample,bbrc_ds_nr_com,bbrc_ds_nr_f,bbrc_duration,merge_time,n_stripped_mss,n_stripped_cst,min_sampling_support,random_seed"]) 

kept_ds_file_name = "bbrc_sample_#{ds_name}_#{method}_keptds_#{Time.now.usec.to_s}.csv"
keep_ds = []
 
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
      algo_params["complete_entries"] = "true"
      
      t = Time.now
      if method == "bbrc"
        puts "[#{Time.now.iso8601(4).to_s}] BBRC params: #{algo_params.to_yaml}"
        feature_dataset_uri = OpenTox::RestClientWrapper.post( File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc"), algo_params )
      else
        algo_params["num_boots"] = num_boots
        algo_params["random_seed"] = i
        algo_params["min_sampling_support"] = min_sampling_support
        algo_params["cache"] = cache
        puts "[#{Time.now.iso8601(4).to_s}] BBRC params: #{algo_params.to_yaml}"
        feature_dataset_uri = OpenTox::RestClientWrapper.post( File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc/sample"), algo_params )
      end
      bbrc_duration = Time.now - t
      puts "[#{Time.now.iso8601(4).to_s}] BBRC duration: #{bbrc_duration}"
      puts "[#{Time.now.iso8601(4).to_s}] BBRC result: #{feature_dataset_uri}"
      puts
      $stdout.flush
      keep_ds << feature_dataset_uri

      #################################
      # MATCH
      #################################
      puts "                      ----- bbrc match -----"
      match_params = {}
      match_params["feature_dataset_uri"] = "#{feature_dataset_uri}"
      match_params["dataset_uri"] = datasets[:test_ds]
      match_params["nr_hits"] = hits
      match_params["complete_entries"] = "true"
      puts "[#{Time.now.iso8601(4).to_s}] Match params: #{match_params.to_yaml}"

      matched_dataset_uri = OpenTox::RestClientWrapper.post(File.join(CONFIG[:services]["opentox-algorithm"],"fminer","bbrc","match"),match_params)
      puts "[#{Time.now.iso8601(4).to_s}] BBRC match result: #{matched_dataset_uri}"
      puts
      $stdout.flush
      keep_ds << matched_dataset_uri 

      #################################
      # Generate Errors
      #################################
      puts "                 ----- pValue comparison -----"
      fd_pValues, fd_effects = get_pValuesEffects(feature_dataset_uri, subjectid)
      md_pValues, md_effects = get_pValuesEffects(matched_dataset_uri, subjectid)
      sum_E1, sum_E2 = calc_E1_E2(fd_pValues, md_pValues)
      e4Sum = commonFractionKV(fd_effects, md_effects)
      e5Sum = correctSignFraction(fd_pValues, md_pValues, 0.95)

      puts "[#{Time.now.iso8601(4).to_s}] pValue difference (E1): #{sum_E1}"
      puts "[#{Time.now.iso8601(4).to_s}] pValue difference (E2): #{sum_E2}"
      puts "[#{Time.now.iso8601(4).to_s}] common effects (E4): #{e4Sum}"
      puts "[#{Time.now.iso8601(4).to_s}] correct significance (E5): #{e5Sum}"
      $stdout.flush

      puts "                 ----- Proportions comparison -----"
      # convert class values to strings for comparison to CSV input of y
      classes = OpenTox::Dataset.find(datasets[:training_ds]).features.values[0][OT.acceptValue].collect {|x| x.to_s}
      fd = readCSV(feature_dataset_uri); fd_features = fd.shift
      fd_y = getCol(readCSV(datasets[:training_ds]), 1); fd_endpoint = fd_y.shift
      md = readCSV(matched_dataset_uri); md_features = md.shift
      md_y = getCol(readCSV(datasets[:test_ds]), 1); md_endpoint = md_y.shift

      #puts "Found #{classes.size} classes '#{classes.join(', ')}'"
      #puts "Found #{fd_y.length} y entries and #{fd.length} occ entries for feature dataset"
      #puts "Found #{md_y.length} y entries and #{md.length} occ entries for match dataset"
      #puts "Found features '#{fd_features.join(', ')}' in feature dataset"
      #puts "Found features '#{md_features.join(', ')}' in match dataset"

      e3AlongFeatures = []
      fd_features.each_with_index { |fdf, fd_col|
        if fd_col>0 # omit ID
          fd_occ = getCol(fd, fd_col).collect {|x| x.to_i}
          fd_sup = getRelSupVal( classes, fd_y, fd_occ )
          if md_features.include?(fdf)
            md_occ = getCol(md, md_features.index(fdf)).collect {|x| x.to_i}
            md_sup = getRelSupVal( classes, md_y, md_occ )
            e3PerClass = (Vector.elements(fd_sup) - Vector.elements(md_sup)).to_a
            #puts "Found '#{e3PerClass.join(',')}' E3 across classes for #{fdf}"
            e3AlongFeatures << e3PerClass.to_gv.mean
            #puts "  => #{e3AlongFeatures.last} (mean)"
          else
            e3AlongFeatures << nil
          end
        end
      }
      e3Sum = e3AlongFeatures.to_gv.mean
      puts "[#{Time.now.iso8601(4).to_s}] class proportion difference (E3): #{e3Sum}"
      $stdout.flush

    rescue Exception => e 
      
      puts "[#{Time.now.iso8601(4).to_s}] Random_seed '#{i}' failed."
      puts "[#{Time.now.iso8601(4).to_s}] #{e.class}: #{e.message}"
      puts "[#{Time.now.iso8601(4).to_s}] Backtrace:\n\t#{e.backtrace.join("\n\t")}"
      failed = true
      $stdout.flush
    
    ensure 

      if failed == false
        result1 << sum_E1
        result2 << sum_E2
        result3 << e3Sum
        result4 << e4Sum
        result5 << e5Sum
        # save statistics
        statistics = add_statistics(feature_dataset_uri, bbrc_duration, method, i, min_frequency, statistics, subjectid)
      else
        result1 << "NA"
        result2 << "NA"
        result3 << "NA"
        result4 << "NA"
        result5 << "NA"
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
      
      csv_output = ["#{result1.last},#{result2.last},#{result3.last},#{result4.last},#{result5.last},#{statistics[:min_frequency].last},#{statistics[:min_frequency_per_sample].last},#{statistics[:bbrc_ds_nr_com].last},#{statistics[:bbrc_ds_nr_f].last},#{statistics[:duration].last},#{statistics[:merge_time].last},#{statistics[:n_stripped_mss].last},#{statistics[:n_stripped_cst].last},#{statistics[:min_sampling_support].last},#{statistics[:random_seed].last}"]
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
  puts
  puts "[#{Time.now.iso8601(4).to_s}] result3: #{result3.to_yaml}"
  puts
  puts "[#{Time.now.iso8601(4).to_s}] result4: #{result4.to_yaml}"
  puts
  puts "[#{Time.now.iso8601(4).to_s}] result5: #{result5.to_yaml}"


  $stdout.flush

rescue Exception => e
  LOGGER.debug "#{e.class}: #{e.message}"
  LOGGER.debug "Backtrace:\n\t#{e.backtrace.join("\n\t")}"

ensure
     
  # add important uris to csv file
  add_string_arr_to_file(kept_ds_file_name, keep_ds) unless keep_ds.empty?

end
