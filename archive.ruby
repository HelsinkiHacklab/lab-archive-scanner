require 'pi_piper'
require 'open3' #stdout
include PiPiper
#require 'dropbox_sdk' # not yet
require 'logger'
require 'time'
require 'fuzzy_match'

#  gnd ---- 10K ----- BUTTON ----- 3.3V
#                 ^----PIN23

# Scanner options
threshold = " --threshold 100"  # (120) Select minimum-brightness to get a white point
curve = " --threshold-curve 40" # (55) Dynamic threshold curve, from light to dark, normally 50-65



$OUT_path = "/home/pi/Scanner/"


watch :pin => 23 do
  #Logger
  file_for_logging = File.open($OUT_path+"archive_scanner_log.txt", File::WRONLY || File::APPEND)
  mylog = Logger.new(file_for_logging)
  
  puts "==========>"
  mylog.info("Started new scan")
  folder_path = $OUT_path+Time.now.utc.strftime("%Y%m%d_%H%M%S")+"/"
  tmp_file_name = (rand()*1000000).round().to_s
  
  # Destination dir
  Dir.mkdir folder_path
  
  # Scan using automatic document feeder
  stdout, stderr, status = Open3.capture3("scanadf --output-file "+folder_path+tmp_file_name+"_%0d --source=\"ADF Duplex\""+threshold+curve)
  mylog.info("err " + stderr )
  puts "status: "+status.to_s

  puts stderr
  
  # recheck this
  scanned_files_list = stderr.scan(/^Scanned document (.*)$/).flatten   #stderr.split("Scanned document ") # Get list of scanned documents
  mylog.info("list of scanned documents "+scanned_files_list.join(' '))

  # if no output, stderr returns: "Scanned 0 pages" => we can end this now
  if scanned_files_list.length == 0
    puts "Scanner did not find any pages"
  else
    
    # Page orientation
    for sf in scanned_files_list
      stdout,stderr,status = Open3.capture3("tesseract -l fin+eng "+sf.to_s+" - -psm 0")
      rot_deg = stderr[/Orientation in degrees\:\s([0-9]*)/,1]
      rot_conf = stderr[/Orientation confidence\:\s([0-9]*)/,1]
      if rot_deg != nil && rot_deg.to_i > 10 && rot_conf.to_i > 5
        # rotate the image if needed
        mylog.info("Rotating new image "+sf+" by "+rot_deg+" with confidence "+rot_conf)
        stdout,stderr,status = Open3.capture3("convert "+sf+" -rotate "+rot_deg+" "+sf)
      end
    end

    # pnm-files converted to single pdf file
    scanned_files_join = scanned_files_list.join(" ")
    stdout, stderr, status = Open3.capture3("convert "+scanned_files_join+" "+folder_path+"tmp_out.pdf")
    
    # OCR the file, does not always produce good results
    stdout, stderr, status = Open3.capture3("pdfsandwich -lang fin+eng "+folder_path+"tmp_out.pdf")
    
    # Also have a combined picture version available
    stdout, stderr, status = Open3.capture3("convert -trim "+scanned_files_join+"+append "+folder_path+"tmp_out.png")
    
    # Extract OCR text data
    stdout, stderr, status = Open3.capture3("pdftotext "+folder_path+"tmp_out_ocr.pdf -")
    puts stdout
    ocr_txt = stdout
   
    ocr_txt_list = ocr_txt.downcase.scan(/[\w\@äö]{5,99}/)
    puts ocr_txt_list
    fuzz = FuzzyMatch.new(ocr_txt_list)

    type = "Yleiset"
    if    fuzz.find("kevätkokouksen", threshold: 0.8) != nil
      type = "Säännönmukaiset kokoukset"
    elsif fuzz.find("syyskokouksen", threshold: 0.8) != nil
      type = "Säännönmukaiset kokoukset"
    elsif fuzz.find("pöytäkirja", threshold: 0.7) != nil
      type = "Pöytäkirjat"
    elsif fuzz.find("kuitti", threshold: 0.8) != nil
      type = "Kuitit ja kauppakirjat"
    elsif fuzz.find("kauppakirja", threshold: 0.6 != nil
      type = "Kuitit ja kauppakirjat"
    elsif fuzz.find("käteiskuitti", threshold: 0.6 != nil
      type = "Kuitit ja kauppakirjat"
    end

    
    # replace all punct/specials/newlines
    # remove all 1 letter words
    # strip preceding and leading whitespace
    # replace double whitespace with one
    final_file_name = ocr_txt.gsub(/[[[:punct:]]\¬\$\^\&\£\<\>\|\+\~\n\r]/,'').gsub(/(\b\w{1}\b)/,'').strip.squeeze(' ')[0,100]

    File.rename(folder_path+"tmp_out_ocr.pdf", folder_path+final_file_name+".pdf")
    File.rename(folder_path+"tmp_out.png", folder_path+final_file_name+".png")
  end
  
  mylog.close
end





PiPiper.wait

