# Get relative support values
# @param classes vector of possible class values (Strings or Numerics)
# @param y vector of class values (Strings or Numerics)
# @param occ vector of occurrence indicators (Integer >=0)
# @return vector of size of (size of classes), containing support values relative to the length of y, or nil
# @example {
#  getRelSupVal([3,2,1],[1,2,1,3],[1,1,1,0]) # [0.0, 0.25, 0.5]
#  getRelSupVal([1,2,3],[1,2,1,3],[1,1,1,0]) # [0.5, 0.25, 0.0]
#  getRelSupVal([1,2,3],[1,2,1,nil],[1,1,1,0]) # nil
# }

def getRelSupVal(classes,y,occ)
  y.each   { |val| 
             unless (val.is_a?(String) || OpenTox::Algorithm::numeric?(val))
               puts "incorrect type for y '#{val}'"
               return nil
             end
             unless (classes.index(val))
               puts "y '#{val}' not in allowed classes '#{classes.join(',')}', index is '#{classes.index(val)}'"
               return nil
             end
           }
  occ.each { |val| 
             unless ( val.is_a?(Integer) && val>=0 )
               puts "occ '#{val}' not an Integer >= 0"
               return nil
             end
           }
  unless y.length == occ.length
    puts "Error: y and occ differ in length"
    return nil
  end

  res = Array.new(classes.size, 0)
  y.each_with_index { |val,idx|
    idx2 = classes.index(val)
    res[idx2] += 1 if occ[idx] >= 1
  }
  
  res = (Vector.elements(res) / y.length).to_a.collect! { |x| x.to_f } 
end


# Get relative support differences of two support vectors
# @param y vector of class values (Strings or Numerics)
# @param occ1 vector of occurrence indicators (Integer >=0)
# @param occ2 vector of occurrence indicators (Integer >=0)
# @return vector of size of (size of classes), containing support values relative to the length of y, or nil
# @example {
#  getRelSupVal([3,2,1],[1,2,1,3],[1,1,1,0]) # [0.0, 0.25, 0.5]
#  getRelSupVal([1,2,3],[1,2,1,3],[1,1,1,0]) # [0.5, 0.25, 0.0]
#  getRelSupVal([1,2,3],[1,2,1,nil],[1,1,1,0]) # nil
# }

def getRelSupDif(classes,y,occ1,occ2)
  y.each    { |val| (return nil) unless ( ( val.is_a?(String) || OpenTox::Algorithm::numeric?(val) ) && classes.index(val) ) }
  occ1.each { |val| (return nil) unless ( val.is_a?(Integer) && val>=0 ) }
  occ2.each { |val| (return nil) unless ( val.is_a?(Integer) && val>=0 ) }
  return (nil) unless (y.length == occ1.length && y.length == occ2.length)

  res=0
  y.each_with_index { |val,idx|
    res += 1 if ((occ1[idx] >0 || occ2[idx] >0) && occ1[idx] != occ2[idx])
  }
  res/y.length.to_f
end


# Read CSV from URI
# @param uri URI to read from
# @return Array with CSV data
# @example {
# }

def readCSV(uri)
  CSV.parse( OpenTox::RestClientWrapper.get(uri, {:accept => "text/csv"}) )
end


# Get column from csv
# @param csv data
# @return Array column
# @example {
#  getCol([["foo","bar"],[1,2],[1,3]],1) # ["bar",2,3]
#}

def getCol(csv,idx)
  return (nil) unless (idx>=0 && idx < csv[0].size)
  csv.collect { |line|
    line[idx]
  }
end
