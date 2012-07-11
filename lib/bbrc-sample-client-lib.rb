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

