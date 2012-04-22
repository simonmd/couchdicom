# Modules required:
require 'rubygems'
require 'find'
require 'active_record'
require 'couchrest'
require 'couchrest_model'
require 'dicom' # version 0.9.2
require 'rmagick'
# require "iconv"

include DICOM
# Intialize logger
log = Logger.new('couchdicom_import.log')
  log.level = Logger::WARN
  log.debug("Created logger")
  log.info("Program started")
  DICOM.logger = log
  DICOM.logger.level = Logger::DEBUG

# Define CouchDB server
SERVER = CouchRest.new

# Create CouchDB database if it doesn't already exist
DB = SERVER.database!('couchwado-plus-images')

# Set the limit of documents for bulk updating
DB.bulk_save_cache_limit = 500

# Define the directory to be read
DIRS = ["/Users/simonmd/Desktop/DATASETS/BOUVIER"]
JPGDIR = "/Users/simonmd/Desktop/WADOS"

#def generate_docuid
#  self.docuid
#end

# Class to generate a CouchDB extended document
class Dicomdoc < CouchRest::Model::Base
  mass_assign_any_attribute true
  use_database DB
  unique_id :slug
  property :slug, :read_only => true
  property :docuid
  timestamps!
  set_callback :save, :before, :generate_slug_from_docuid

  def generate_slug_from_docuid
    self['slug'] = docuid if new?
  end
end

# Returns an element's key (or in case of Item, it's index).
def extract_key(element)
  if element.is_a?(Item)
    # Use the Item's index instead of tag:
    cdbkey = element.index
  else
    # Read tag as CouchDB Key:
    cdbkey = element.tag
    # Remove the comma from the tag string:
    cdbkey = cdbkey.gsub(",","")
    # Prepend a 't' for easier javascript map/reduce functions:
    cdbkey = "t" + cdbkey
  end
  return cdbkey
end

# Returns a data element's value.
# Note that data elements of vr OB & OW have no value decoded, so value returned for these will be nil.
def extract_value(element)
  # Read value as CouchDB value for that key:
  cdbvalue = element.value
  # Convert encoding to UTF-8 with Ruby 1.9 'encode' method
  cdbvalue = cdbvalue.encode('utf-8', 'iso-8859-1') if cdbvalue.class == String
  return cdbvalue
end

# Returns a hash with tag/data-element-value (or child elements) are used as key/value.
def process_children(parent_element)
  h = Hash.new
  # Iterate over all children and repeat recursively for any child which is parent:
  parent_element.children.each do |element|
    if element.children?
      value = process_children(element)
      key = extract_key(element)
    elsif element.is_a?(Element)
      key = extract_key(element)
      value = extract_value(element)
    end
    # Only write key-value pair if the value is not empty (to conserve space)
    unless value.blank?
      h[key] = value
    end
  end
  return h
end

# Discover all the files contained in the specified directory and all its sub-directories:
excludes = ['DICOMDIR']
files = Array.new()
for dir in DIRS
  Find.find(dir) do |path|
    if FileTest.directory?(path)
      if excludes.include?(File.basename(path))
        Find.prune  # Don't look any further into this directory.
      else
        next
      end
    else
      files += [path]  # Store the file in our array
    end
  end
end

# Start total timer
total_start_time = Time.now

# Use a loop to run through all the files, reading its data and transferring it to the database.
files.each_index do |i|
  iteration_start_time = Time.now
  # Read the file:
  log.info("Attempting to read file #{i} ...")
  dcm = DObject.read(files[i])
  # If the file was read successfully as a DICOM file, go ahead and extract content:
  if dcm.read_success
    log.info("Successfully read file #{files[i]}")
    # Extract a hash of with tag/data-element-value as key/value:
    h = process_children(dcm)
    # Save filepath in hash
    h["filepath"] = files[i]
    # Read in the dicom file as a 'file' object
    file = File.new(files[i])
    # Create new CouchDB document with the generated hash
    currentdicom = Dicomdoc.new(h)
    # Set the document ID to the Instance Unique ID (UID)
    currentdicom.docuid = h["t00080018"].to_s
    # Create the attachment from the actual dicom file
    currentdicom.create_attachment({:name => 'imagedata', :file => file, :content_type => 'application/dicom'})
    
    # Load pixel data to ImageMagick class
    log.info("Attempting to load pixel data for file #{files[i]} ...")
    if dcm.image
      log.info("Pixel data for file #{files[i]} read successfully")
      image = dcm.image.normalize
      # Save pixeldata as jpeg image in wado cache directory
      wadoimg_path = "#{JPGDIR}/wado-#{currentdicom.docuid}.jpg"
      # Write the jpeg for WADO
      image.write(wadoimg_path)
      # Read to insert in attachment (SURELY this can be done directly)
      wadofile = File.new(wadoimg_path) 
      # Create an attachment from the created jpeg
      currentdicom.create_attachment({:name => 'wadojpg', :file => wadofile, :content_type => 'image/jpeg'})
    else
      log.warn("could not read pixel data for file #{files[i]} ...")
    end

    # Save the CouchDB document
    begin
      currentdicom.save
      # Uncomment if bulk saving is desired (Little performance gain, bottleneck is in dicom reads)
        # currentdicom.save(bulk  = true)
    # If an error ocurrs, raise exception and log it
    rescue Exception => exc
      log.warn("Could not save file #{files[i]} to database; Error: #{exc.message}")
    end

  end

  # Log processing time for the file
  iteration_end_time = Time.now
  iterationtime = iteration_end_time - iteration_start_time
  log.info("Iteration time for file #{i} finished in #{iterationtime} s")
end

# Log total processing time
total_end_time = Time.now
totaltime = total_end_time - total_start_time
log.info("Full processing time: #{totaltime} seconds")
# Close the logger
log.close