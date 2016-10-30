#!/bin/bash

# $1 = Path to Process-Folder of Goobi (e. g. /opt/digiverso/goobi/metadata/100)
# $2 = Process-Title (e. g. AC12345678)
# $3 = Path to Directory, where data should be archived (e. g. /home/mbirkner/archive)
# $4 = Make Archive only for data, only for images or both
# $5 = Check if master-tiffs should be deleted after archiving them or not

# Show help. Double square brackets [[ conditions ]] support operations like || (= or).
if [[ $* == "-help" || $* == "-h" || -z $* ]]; then
	echo -e "\n###########################################\n"
	echo -e "There are 5 parameters. Seperate them by a space.\n"
	echo -e "1. Parameter (mandatory):\nPath to Process-Folder of Goobi (e. g. /opt/digiverso/goobi/metadata/100). Normally this is: {imagepath}/../\n"
	echo -e "2. Parameter (mandatory):\nProcess-Title (e. g. AC12345678). Normally this is: {processtitle}\n"
	echo -e "3. Parameter (mandatory):\nPath to Directory, where data should be archived (e. g. /home/yourUserName/archive). This could be your personal folder under \"home\".\n"
	echo -e "4. Parameter (mandatory):\nDecide if you want to archive\n  - \"images\": only the images (big file-size, takes quite a lot of time)\n  - \"metadata\": only the metadata (smaller file size)\n  - \"imagesandmetadata\": the images AND the metadata.\nParameter should be set to (no surprise) \"images\", \"metadata\" or \"imagesandmetadata\" (without quotes). Depending on what you set, you get an archive-file with only the images, with only the metadata or two archiv-files, one with the images and one with the metadata.\n"
	echo -e "5. Parameter (optional):\nDecide if you want to delete the master-tifs after they are archived. Deleting them would save a lot of disk-space. Set the parameter to \"deleteMasterTifs\" if you want to delete them.\n"	
	echo -e "###########################################\n"
	#exit 0
fi


# Change to process-folder of goobi
cd $1


# Make Variables:
processDir=$(pwd)
imagesDir=images
processID=$(basename $processDir)
processTitle=$2
archiveDir=$3
mysqlDir=$archiveDir/goobi_mysql_archive
tempDir=$processDir

tarFileImages=$tempDir/"$processTitle"_"$processID"_img.tar
tarFileMetadata=$tempDir/"$processTitle"_"$processID"_md.tar

gzipFileImages=$tarFileImages.gz
gzipFileMetadata=$tarFileMetadata.gz

gzipFileNameImages="$processTitle"_"$processID"_img.tar.gz
gzipFileNameMetadata="$processTitle"_"$processID"_md.tar.gz

historySQLFile="$processTitle"_"$processID"_history.sql
schritteSQLFile="$processTitle"_"$processID"_schritte.sql

# Make archive base-directory if it does not exist:
if [ ! -d $archiveDir ]; then
	mkdir $archiveDir
fi

# Make mysql directory if it does not exist:
if [ ! -d $mysqlDir ]; then
	mkdir $mysqlDir
fi

			

makeImagesArchive() {

	if [ -f $archiveDir/$gzipFileNameImages ]; then
		echo "Stop: Fuer den Vorgang existiert bereits eine Image-Sicherung. Sie ist unter $archiveDir/$gzipFileNameImages zu finden."
	else
		# Archive only the images-folder:
		/usr/bin/nice -n 18 /usr/bin/ionice -c2 -n6 tar cf $tarFileImages "$processDir/$imagesDir" 2>&1
		
		# Compression:
		/usr/bin/nice -n 18 /usr/bin/ionice -c2 -n6 gzip $tarFileImages 2>&1
		
		# Copy .tar.gz-file from temporary directory to archive directory:
		/usr/bin/nice -n 18 /usr/bin/ionice -c2 -n6 cp $gzipFileImages $archiveDir
		
		# Delete .tar.gz-file from temporary directory
		/usr/bin/nice -n 18 /usr/bin/ionice -c2 -n6 rm $gzipFileImages
		
		
		echo "Meldung \"Entferne fuehrende / von Elementnamen\" ist OK!"
		echo "Images-Archivierung erfolgreich abgeschlossen. Die Archivdatei kann unter $archiveDir/$gzipFileNameImages abgeholt werden."
		
		# If it is set, delete the master-tifs in the process-folder of Goobi to save disk space.
		# $1 is the first parameter which is given to the FUNCTION. It's NOT the first parameter from the command line which is given to the whole script!	
		if [[ $1 == "deleteMasterTifs" ]]; then
			# Loop over every file/folder in the images-directory that starts with "orig". Then, do a delete only for folders (-d $i). If a file starts with "orig", do not delete it!
			for i in $processDir/$imagesDir/orig*; do
				[ -d $i ] && rm -rf $i
			done	
			# Remove the "orig" directory itself if it still exists
			rm -rf "$processDir/$imagesDir/orig"*
			echo "Master-Tifs wurden nach der Archivierung geloescht; Speicherplatz wurde gespart."
		fi
		
		echo "Nachdem die Images-Archivdatei gesichert ist, kann sie vom Server geloescht werden."
	fi
}

makeMetadataArchive() {

	if [ -f $archiveDir/$gzipFileNameMetadata ]; then
		echo "Stop: Für den Vorgang existiert bereits eine Metadaten-Sicherung. Sie ist unter $archiveDir/$gzipFileNameMetadata zu finden."
	else
		# Get process-title without "Autor-Titel-Schlüssel" from PICA:
		if [[ $processTitle == *_* ]]; then
			processTitleNoATS=$(echo $processTitle | grep -oP '(?<=_).*')
		else
			processTitleNoATS=$processTitle
		fi
		
		mysqluser=$(xmllint --xpath '/AK/General/DbUser/text()' /opt/digiverso/goobi/config/goobi_ak.xml)
		mysqlpass=$(xmllint --xpath '/AK/General/DbPass/text()' /opt/digiverso/goobi/config/goobi_ak.xml)
	
		# Make necessary MySQL-Dumps:
		mysqldump --no-create-info --user=$mysqluser --password=$mysqlpass -B goobi --tables history --where='processID='$processID > $mysqlDir/$historySQLFile 
		mysqldump --no-create-info --user=$mysqluser --password=$mysqlpass -B goobi --tables schritte --where='ProzesseID='$processID > $mysqlDir/$schritteSQLFile

		# Ask for ruleset ID:
		rulesetID=$(mysql --user=$mysqluser --password=$mysqlpass -B goobi -ss -N -e "SELECT MetadatenKonfigurationID FROM prozesse WHERE ProzesseID=$processID")
		
		# Ask for ruleset filename:
		rulesetFile=$(mysql --user=$mysqluser --password=$mysqlpass -B goobi -ss -N -e "SELECT Datei FROM metadatenkonfigurationen WHERE MetadatenKonfigurationID=$rulesetID")

		# Make Tarball:
		# Create tarball and add everything from the process directory except the images-folder:
		tar cf $tarFileMetadata $processDir --exclude=$imagesDir 2>&1
		
		# Add files from viewer to tarball:
		tar rf $tarFileMetadata /opt/digiverso/viewer/indexed_mets/$processTitleNoATS.xml 2>&1
		# Add ruleset file to tarball:
		tar rf $tarFileMetadata /opt/digiverso/goobi/rulesets/$rulesetFile 2>&1
		# Add MySQL-Dumps to tarball:
		tar rf $tarFileMetadata -C $archiveDir goobi_mysql_archive/$historySQLFile
		tar rf $tarFileMetadata -C $archiveDir goobi_mysql_archive/$schritteSQLFile
		
		# Delete MySQL-Dumps:
		rm $mysqlDir/$historySQLFile
		rm $mysqlDir/$schritteSQLFile
		
		# Compression:
		gzip $tarFileMetadata

		# Copy .tar.gz-file from temporary directory to archive directory:
		cp $gzipFileMetadata $archiveDir
		
		# Delete .tar.gz-file from temporary directory
		rm $gzipFileMetadata

		# Change file permission so that user can delete file:
		chmod -R 0777 $archiveDir

		echo "Meldung \"Entferne fuehrende / von Elementnamen\" ist OK!"
		echo "Metadaten-Archivierung erfolgreich abgeschlossen. Die Archivdatei kann unter $archiveDir/$gzipFileNameMetadata abgeholt werden."
		echo "Nachdem die Metadaten-Archivdatei gesichert ist, kann sie vom Server geloescht werden."
	fi
}


if [[ $4 == "images" ]]; then
	makeImagesArchive $5
fi

if [[ $4 == "metadata" ]]; then
	makeMetadataArchive
fi

if [[ $4 == "imagesandmetadata" ]]; then
	makeImagesArchive $5
	makeMetadataArchive
fi
	
	

# Make ReadMe-File:
cat << EOF > $archiveDir/ReadMe.txt
To restore a lost goobi-process, do the following
1. Connect to Goobi Server (e. g. with Putty). You need to use the command line!
2. Make sure you have sudo rights
3. Find the "tar.gz"-file of the goobi-process you want to restore
4. Now enter the following command:
   sudo tar xkzf YOUR_TAR.GZ_FILE -C /

   The meanings of the command:
    sudo: You need sudo-rights to write new files:
    x: Extract the files
    k: Do not overwrite existing files. Only none-existing files are written!
    z: Unzip the file (you could leave this command if you would have a .tar-file instead of a .tar.gz-file)
    f: File
    YOUR_TAR.GZ_FILE: The .tar.gz-file you want to extract
    -C: The folder where to extract the content of the .tar.gz-file. As the files in the .tar.gz-file are saved there with their full original path, you should use "/" to choose the root-directory
        It is necessary that the file-system (that means, the path to the "goobi"- and "viewer"- folder) are now the same as at the moment of the creation of the .tar.gz-file. Normally, the pathes are
        "/opt/digiverso/goobi" and "/opt/digiverso/viewer"

5. Now, all necessary process-files are recreated in the "goobi" and "viewer" folder of your Goobi-Installation. ATTENTION: Existing files are NOT overwritten!
6. In the root-Directory of your filesystem, you will find a folder called  "goobi_mysql_archive". There you find MySQL-Dumps for the recreated Goobi processes.
7. If you need to recreate the database-entries, you could do something like that (ATTENTION: NOT TESTED!!!):
   mysql --user=USERNAME --password=PASSWORD goobi < SQLFILE.sql
EOF
