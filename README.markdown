#couchDICOM#


##DICOM object loader to CouchDB using Ruby DICOM##


**Requeriments**

* ImageMagick
* Ruby v. 1.9.2
* Rails v. 3.x
* Gems: couchrest, couchrest_extended_document, dicom v. 0.8, narray, iconv, pony

**Note**

* The DICOM files could be uncompressed
* Tha variable bind_addresss of the couch database must be equal to 0.0.0.0

**Instructions**

* If you do not have ImageMagick and you are a MAC user we recommended you install it via Homebrew (http://mxcl.github.com/homebrew/)
* Install the Gems required: gem install couchrest couchrest_extended_document dicom v. 0.8 narray iconv pony
* If you want to create the DICOM Documents with the pixeldata as attachment run the script cdicom_attach_dicom.rb. If you just want to insert the metada DICOM run the script cdicom-noattach-nobulk.rb
* Update the variable DB with the Database name of the couchDB database 
* Update the variable DIRS with the DICOM directory path to scan
* Run the selected Ruby Script: ruby cdicom-noattach-nobulk.rb
