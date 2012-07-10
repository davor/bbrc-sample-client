# # Author: Andreas Maunz, David Vorgrimmler

require 'rubygems'
require 'opentox-ruby'
require 'yaml'
require 'csv'

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

subjectid = nil

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

ds_uri = ds[ds_name]["dataset"]

finished_rounds = 0
result1 = []
result2 = []
metadata = []

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
    split_params["prediction_feature"] = (ds_uri.to_s + "/feature/1")
    split_params["stratified"] = true 
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

      ds = OpenTox::Dataset.find(datasets[:training_ds])
      ds_nr_com = ds.compounds.size

      min_params["backbone"] = backbone
      durations = []
      x = ds_nr_com
      ds_result_nr_f = 0
      y = x
      y_old = 0
      #  puts
      #  puts "----- Initialization: -----"
      while ds_result_nr_f < (ds_nr_com/4).to_i do
        y_old = y
        y = x
        x = (x/2).to_i
        min_params["min_frequency"] = x
        t = Time.now
        result_uri = OpenTox::RestClientWrapper.post( File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc/"), min_params )
        durations << Time.now - t
        ds_result = OpenTox::Dataset.find(result_uri)
        del_ds << ds_result.uri
        ds_result_nr_f = ds_result.features.size
      end  

      #  puts
      #  puts "----- Main phase: -----"
      max_duration = durations[0] +(ds_nr_com.to_f * time_per_cmpd)
      min_params["min_frequency"] = y
      y = y_old
      found = false
      cnt = 0
      min_f = min_params["min_frequency"]
      # Search for min_frequency with following heuristic procedure. If no good min_frequency found the delivered value(from the arguments) is used.
      while found == false || cnt == 4 do
        if min_f == min_params["min_frequency"]
          cnt = cnt + 1
        end
        min_f = min_params["min_frequency"]
        t = Time.now
        result_uri = OpenTox::RestClientWrapper.post( File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc/"), min_params )
        durations << Time.now - t
        ds_result = OpenTox::Dataset.find(result_uri)
        del_ds << ds_result.uri
        ds_result_nr_f = ds_result.features.size
        # Check if number of features is max half and min one-tenth of the number of compounds and performed in accaptable amount of time
        if ds_result_nr_f.to_i < (ds_nr_com/2).to_i && ds_result_nr_f.to_i > (ds_nr_com/10).to_i
          if durations.last < max_duration
            found = true
            min_freq = min_params["min_frequency"]
          else
            x = min_params["min_frequency"]
            min_params["min_frequency"] = ((min_params["min_frequency"]+y)/2).to_i
          end
        else
          y = min_params["min_frequency"]
          min_params["min_frequency"] = ((x+min_params["min_frequency"])/2).to_i
        end
      end
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
    bbrc_ds = OpenTox::Dataset.find(feature_dataset_uri)
    bbrc_ds.save(subjectid)
    del_ds << bbrc_ds.uri
    bbrc_smarts_pValues = {}
    bbrc_ds.features.each do |f, values|
      if values[RDF::type].include?(OT.Substructure)
        bbrc_smarts_pValues[values[OT::smarts]] =  values[OT::pValue]
      end
    end 

    match_ds = OpenTox::Dataset.find(matched_dataset_uri)
    matched_smarts_pValues = {}
    match_ds.features.each do |f, values|
      if values[RDF::type].include?(OT.Substructure)
        matched_smarts_pValues[values[OT::smarts]] =  values[OT::pValue]
      end
    end

    sum_E1 = 0.0
    sum_E2 = 0.0
    bbrc_smarts_pValues.each do |s, p|
      if matched_smarts_pValues.include?(s)
        dif = (p.to_f - matched_smarts_pValues[s].to_f)
        sum_E1 = sum_E1 + dif 
        sum_E2 = sum_E2 + dif.abs
      end
    end
    sum_E1 = sum_E1/bbrc_smarts_pValues.size
    sum_E2 = sum_E2/bbrc_smarts_pValues.size 
    puts "[#{Time.now.iso8601(4).to_s}] Sum pValue difference (E1): #{sum_E1}"
    puts "[#{Time.now.iso8601(4).to_s}] Squared sum pValue difference (E2): #{sum_E2}"
    $stdout.flush

    #################################
    # SAVE data 
    #################################
    result1 << sum_E1
    result2 << sum_E2
    
    # save statistics
    t_ds = OpenTox::Dataset.find(datasets[:training_ds])
    statistics[:t_ds_nr_com] << ds.compounds.size.to_f
  
    statistics[:bbrc_ds_nr_com] << bbrc_ds.compounds.size.to_f
    statistics[:bbrc_ds_nr_f] << bbrc_ds.features.size.to_f
    statistics[:duration] << bbrc_duration
   
    if !method.to_s.include?("bbrc")
      statistics[:min_sampling_support] << bbrc_ds.metadata[OT::parameters][2][OT::paramValue].to_f #ToDo get values by params name
      statistics[:min_frequency_per_sample] << bbrc_ds.metadata[OT::parameters][4][OT::paramValue].to_f
      statistics[:merge_time] << bbrc_ds.metadata[OT::parameters][6][OT::paramValue].to_f
      statistics[:n_stripped_mss] << bbrc_ds.metadata[OT::parameters][7][OT::paramValue].to_f
      statistics[:n_stripped_cst] << bbrc_ds.metadata[OT::parameters][8][OT::paramValue].to_f
    end

    # save params
    info = []
    info << { :ds_name => ds_name, :nr_features => bbrc_ds.features.size} 
    info << split_params
    info << algo_params
    info << match_params

    metadata << info
    puts
    finished_rounds += 1
    del_ds.each do |del_ds_uri| 
      ds = OpenTox::Dataset.find(del_ds_uri, subjectid)
    end
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


