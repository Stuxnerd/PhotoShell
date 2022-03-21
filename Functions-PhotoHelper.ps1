<#
.SYNOPSIS
	The script includes several useful functions which are used by several scripts to manage photos.
.DESCRIPTION
	Assumptions:
	* The names for EXIF properties are in German language
	This script includes these functions:
	* Export-Files
	* Get-ExifDataFromFile
	* Find-AlphaNumericSuccessorAndPredecessorFile
	* Get-FolderNameFromDate
	* Move-PhotoFiles
	* Sort-PanoramaFiles
	* Move-HDRFiles
.LINK
	https://github.com/Stuxnerd/PhotoShell.git
.NOTES
	VERSION: 0.2.0 - 2022-03-17

	AUTHOR: @Stuxnerd
		If you want to support me: bitcoin:19sbTycBKvRdyHhEyJy5QbGn6Ua68mWVwC

	LICENSE: This script is licensed under GNU General Public License version 3.0 (GPLv3).
		Find more information at http://www.gnu.org/licenses/gpl.html

	TODO:
	* Adapt format of file to common design
	* Translate to English
#>

###########################################
#INTEGRATION OF EXTERNAL FUNCTION PACKAGES#
###########################################

#is based on https://github.com/Stuxnerd/PsBuS
. ../PsBuS/Functions-Logging.ps1
. ../PsBuS/Functions-Support.ps1


#####################
#FUNCTION DEFINITION#
#####################

<#
.SYNOPSIS
	Function to Move or copy files of a folder
.DESCRIPTION
	Function to Move or copy files of a folder
	The magic is a counter to check for several instances if the copy process was successfull
	A common issue are duplicate filenames, which overwrite exisitng files (but sometimes this is desired)
.PARAMETER $Action
	"Copy" or "Move"
.PARAMETER $FileType
	type of files in the form: "*.JPG"
	TODO: support several filestypes
.PARAMETER $SourcePath
	full source path 
.PARAMETER $TargetPath
	full destination path 
.PARAMETER $ExternalCounter
	optional REFERENCE to an external counter which might be used for several instances of Export-Files
	is not mandatory and starts with 0, if not set
.EXAMPLE
	[int]$global:TotalSum = 0
	Export-Files -Action "Copy" -FileType "*.JPG" -ExternalCounter ([REF]$global:TotalSum) -SourcePath "C:\JPG\" -TargetPath "D:\Final\"
	will copy all JPG files from source to destination
#>
Function Export-Files {
	Param(
		#"Copy" or "Move"
		[Parameter(Mandatory = $True, Position = 1)]
		[ValidateSet("Copy", "Move")]
		[String]$Action,

		#File types like "*.JPG"
		[Parameter(Mandatory = $True, Position = 2)]
		[String]$FileType,

		#source path
		[Parameter(Mandatory = $True, Position = 3)]
		[String]$SourcePath,
		
		#destination path
		[Parameter(Mandatory = $True, Position = 4)]
		[String]$TargetPath,

		#REFERENCE to external counter [int] for moved/copied files
		[Parameter(Mandatory = $False, Position = 5)]
		[REF]$ExternalCounter = 0
		
	)
	#setup LOCAL counter
	[int]$LocalCounter = 0
	
	#Ensure the folder does exist
	TestAndCreate-Path -FolderName $TargetPath

	$Files = Get-ChildItem -Path $SourcePath -ErrorAction SilentlyContinue
	foreach ($File in $Files) {
		#depending on operation
		if ($Action -eq "Copy") {
			Copy-Item -Path $File.FullName -Destination $TargetPath -Include $FileType -Force -ErrorAction SilentlyContinue 
			#increment all counters (local and external)
			$LocalCounter++
			$ExternalCounter.Value++
		}
		if ($Action -eq "Move") {
			Move-Item -Path $File.FullName -Destination $TargetPath -Include $FileType -Force -ErrorAction SilentlyContinue
			#increment all counters (local and external)
			$LocalCounter++
			$ExternalCounter.Value++
		}
	}
	if ($Action -eq "Copy") {
		Trace-LogMessage -Message "Copied $LocalCounter files from $SourcePath to $TargetPath ." -Level 1
	}
	if ($Action -eq "Move") {
		Trace-LogMessage -Message "Moved $LocalCounter files from $SourcePath to $TargetPath ." -Level 1
	}
}


<#
.SYNOPSIS
	function to read EXIF information
.DESCRIPTION
	function to read EXIF information
.PARAMETER $FileName
	Name and path of the file
.PARAMETER $Properties
	array of names of the EXIF properties
	The names depend on the language of the OS (here German is used)
.PARAMETER $MaxPropertyCount
	maximum number of property field (308 is set as it worked fine)
.OUTPUTS
	HashTable Get-ExifDataFromFile returns a hashtable with the requested properties
.EXAMPLE
	Get-ExifDataFromFile -FileName $File2 -Properties "Lichtwert").Item("Lichtwert")
.LINK
	The process was influenced by:
	* http://www.administrator.de/wissen/erweiterte-dateieigenschaften-powershell-funktion-abfragen-223082.html
	* http://blogs.technet.com/b/heyscriptingguy/archive/2014/02/06/use-powershell-to-find-metadata-from-photograph-files.aspx
	* https://gallery.technet.microsoft.com/scriptcenter/get-file-meta-data-function-f9e8d804
#>
Function Get-ExifDataFromFile {
	Param(
		#file name
		[Parameter(Mandatory = $True, Position = 1)]
		[String]$FileName,

		#Namen der Eigenschaften
		[Parameter(Mandatory = $True, Position = 2)]
		[String[]]$Properties, 

		#Anzahl der Eigenschaftsfelder (empirisch ermittelt)
		[Parameter(Mandatory = $False, Position = 3)]
		[int]$MaxPropertyCount = 308
	)
	Process {
		#to save and return the results
		$HashTable = @{}

		$ObjShell = New-Object -ComObject Shell.Application
		#get the directory for the file
		[String]$FolderName = ((Get-ChildItem -Path $FileName).Directory)
		$ObjFolder = $ObjShell.namespace($FolderName)

		#run through all files of the folder
		#TODO: find a way to not run through all files - this really takes a long time
		#TODO: direct access to property and not iterating through all would also increase performance
		foreach ($File in $ObjFolder.items()) {
			#filter only for the requested file
			if($File.Path -eq $FileName) {
				#get ALL properties of the file
				for ($a ; $a  -le $MaxPropertyCount; $a++) {
					#get the properties of the file
					if($ObjFolder.getDetailsOf($File, $a)) {
						#get the name of the iterated property
						[String]$PropertyName = $($ObjFolder.getDetailsOf($ObjFolder.items, $a))
						#only consider the requested properties anymore
						if($Properties.Contains($PropertyName)) {
							#save the property (key and value) to the hashtablke to return it
							$HashTable.Add($PropertyName, $($ObjFolder.getDetailsOf($File, $a)))
						}
					}
				}
			}
		}
		#return the values
		return $HashTable
	}
}


<#
.SYNOPSIS
	Funktion um umgebende Dateinamen (ähnliche Nummerierung) zu ermitteln
.PARAMETER $Filename
	Dateiname
.PARAMETER $Offset
	bestimmen, welche umgebende Anzhal Dateien ermittelt wird
.PARAMETER $DigitCount
	Anzahl der Stellen in der Datei, die betrachtet werden (bisher keine Auswirkung)
.OUTPUTS
	TODO
.DESCRIPTION
	TODO
#>
Function Find-AlphaNumericSuccessorAndPredecessorFile {
	Param(
		[String]$Filename, #Dateiname
		[int]$Offset, #bestimmen, welche umgebende Datei ermittelt wird
		[int]$DigitCount = 4 #Anzahl der Stellen in der Datei, die betrachtet werden (bisher keine Auswirkung)
	)
	#TODO: Sollte mit bereits umbenannten Dateien a la "IMG_0815 90D.jpg" klarkommen
	#Dateinamen speichern, um enthaltene Zahl zu ermitteln
	$File = Get-ChildItem -Path $Filename
	[String]$Filename = $File.FullName
	#Dateiendung entfernen (je nach Länge dieser)
	$AlphaNumericPredecessorFileName = $Filename.Substring(0, $File.FullName.Length - $File.Extension.Length)
	[int]$Length = $AlphaNumericPredecessorFileName.Length
	#enthaltende Nummer auslesen
	[int]$ContainedNumber = $AlphaNumericPredecessorFileName.Substring($Length - $DigitCount, $DigitCount)
	#enthaltende Nummer wegschneiden (die die vorgegebene Anzahl Stellen
	$AlphaNumericPredecessorFileName = $AlphaNumericPredecessorFileName.Substring(0,$Length - $DigitCount)
	#neue Nummer berechnen
	[int]$NewNumber = $ContainedNumber + $Offset
	if($NewNumber -le 0) {
		$NewNumber += 9999 #es gibt keine 0000-Datei bei Canon 600D
		Trace-LogMessage -Message "Stellenunterlauf bei $($File.Fullname)" -ForegroundColor DarkMagenta
	}
	#Umwandeln in einen String der richtigen Länge (ggf. mit 0 befüllen)
	[String]$NewNumberString = $NewNumber
	while($NewNumberString.Length -lt $DigitCount) {
		$NewNumberString = "0$NewNumberString"
	}
	<# Alternative zur While-Schleife
	switch($NewNumber) { #es wird die entsprechende Anzahl 0 angehangen
		{$_ -lt 1000} {$NewNumberString = "0$NewNumberString"}
		{$_ -lt 100} {$NewNumberString = "0$NewNumberString"}
		{$_ -lt 10} {$NewNumberString = "0$NewNumberString"}
	}
	#>
	#durch neue Nummer ersetzen und Dateiendung wieder anhängen
	$AlphaNumericPredecessorFileName = $AlphaNumericPredecessorFileName + $NewNumberString + $File.Extension
	#Rückgabe der ermittelten Dateibezeichnung
	return $AlphaNumericPredecessorFileName
}


<#
.SYNOPSIS
	Funktion um ein gegebenes Datum in den zu nutzenden Ordnernamen umzuwandeln
.PARAMETER $Date
	Da nicht immer ein Datum korrekt übergeben wird, gibt es ein Fallback
.DESCRIPTION
	TODO
#>
Function Get-FolderNameFromDate {
	Param(
		[String]$Date #Datum (31.12.2015)
	)
	#Da nicht immer ein Datum korrekt übergeben wird, gibt es ein Fallback
	if ($Date.Length -le 8) {
		$ReturnValue = "Tag 00" #fester Wert
	} else {
		$ReturnValue = "Tag " + $Date.Substring(1,2) #feste Stelle im Datum
	}
	$ReturnValue #Rückgabe
}

<#
.SYNOPSIS
	TODO
.PARAMETER $Name
	TODO
.PARAMETER $BasicPath
	TODO
.PARAMETER $DestinationSubPath
	TODO
.PARAMETER $FileTypes
	TODO
.PARAMETER $ComplementaryFileTypes
	TODO
.PARAMETER $ComplementaryFilesStatus
	TODO
.PARAMETER $SetOfCameraModelsOnly
	TODO
.PARAMETER $CreateSubFoldersForEachDate
	TODO
.DESCRIPTION
	TODO
#>
function Move-PhotoFiles {
	Param (
		[Parameter(Mandatory=$true, Position=0)]
		[String]
		$Name,
		[Parameter(Mandatory=$true, Position=1)]
		[String]
		$BasicPath,
		[Parameter(Mandatory=$true, Position=2)]
		[String]
		$DestinationSubPath,
		[Parameter(Mandatory=$true, Position=3)]
		[String[]]
		$FileTypes,
		[Parameter(Mandatory=$false, Position=4)]
		[String]
		$PartnerFilesSubPath = "",
		[Parameter(Mandatory=$false, Position=5)]
		[String[]]
		$ComplementaryFileTypes = @(),
		[Parameter(Mandatory=$false, Position=6)]
		[ValidateSet('Exist','NotExist')]
		[String]$ComplementaryFilesStatus = 'Exist',
		[Parameter(Mandatory=$false, Position=7)]
		[String[]]
		$SetOfCameraModelsOnly = @(),
		[Parameter(Mandatory=$false, Position=8)]
		[Boolean]
		$CreateSubFoldersForEachDate = $false
	)
	Process {
		#Pfade anpassen
		Get-NormalizedPath -FolderName $BasicPath | Out-Null
		Get-NormalizedPath -FolderName $DestinationSubPath | Out-Null
		[int]$MoveCount = 0 #zählen der jeweils verschobenen Dateien
		Trace-LogMessage -Message "Suche Dateien vom Typ: $Name" -Level 1 -MessageType Confirmation -Indent 1

		#ensure this is consistent
		if ($PartnerFilesSubPath.Length -gt 0) {
			$ComplementaryFilesStatus = 'Exist'
		}

		#Suche der jeweiligen Dateien
		$FoundFilesList = Get-ChildItem -Path ($BasicPath+"*") -Include $FileTypes -ErrorAction SilentlyContinue #Pfad muss auf * enden, damit mehrere Dateitypen gesucht werden können
		foreach ($File in $FoundFilesList) {
			Trace-LogMessage -Message "Untersuche Datei: $File" -Level 8 -MessageType Confirmation -Indent 8

			#wenn es komplementäre Dateitypen (nicht) gibt, können wir ggf. frühzeitig abbrechen
			#dazu wird ermittelt, ob die nachfolgenden Schritte ausgeführt werden
			[Boolean]$GoOnMovingFiles = $True
			if ($ComplementaryFileTypes.Count -ne 0) {
				#to compensate complex cases for several complementary files and if they exists, we store the result in a separate variable
				[Boolean]$AtLeatOneComplementaryExists = $False
				#Alle alternativen Dateitypen iterieren
				foreach ($complementaryfiletype in $ComplementaryFileTypes) { # zu vergleichende Dateitypen
					#each filetype looks like "*.cr2" or "*.jpeg"
					[String]$Type1 = ($File.Extension).Replace(".","").ToLower()
					[String]$Type2 = $complementaryfiletype.Replace("*.","").ToLower()
					$ComplementaryFile =  $File.FullName.ToLower().Replace($Type1,$Type2)
					Trace-LogMessage -Message "Komplementäre Datei: $ComplementaryFile" -Level 8 -MessageType Confirmation -Indent 8

					#test if at least one complementary file exists (not all types will exisits)
					if (Test-Path -PathType Leaf $ComplementaryFile) {
						$AtLeatOneComplementaryExists = $True
						Trace-LogMessage -Message "Komplementäre Datei existiert" -Level 8 -MessageType Confirmation -Indent 8
					} else {
						$AtLeatOneComplementaryExists = $False -or $AtLeatOneComplementaryExists #will be true, if it ever true
						Trace-LogMessage -Message "Komplementäre Datei existiert nicht" -Level 8 -MessageType Confirmation -Indent 8
					}
				}
				#now it needs to be checked, if it is good, that the complementary file exists
				if ($ComplementaryFilesStatus -eq 'Exist') {
					if ($AtLeatOneComplementaryExists) {
						$GoOnMovingFiles = $True
					} else {
						$GoOnMovingFiles = $False
					}
				}
				if ($ComplementaryFilesStatus -eq 'NotExist') {
					if ($AtLeatOneComplementaryExists) {
						$GoOnMovingFiles = $False
					} else {
						$GoOnMovingFiles = $True
					}
				}
			}

			#If there is a restriction to a set of cameras it will be checked too
			if ($GoOnMovingFiles -and ($SetOfCameraModelsOnly.Count -gt 0)) {
				#it is expected this never fails, as only used for JPG files and they always have EXIF data
				$CameraModel = Get-ExifDataFromFile -FileName $File.FullName -Properties "Kameramodell"
				if ($SetOfCameraModelsOnly.Contains($CameraModel.Item("Kameramodell"))) {
					$GoOnMovingFiles = $True
				} else {
					$GoOnMovingFiles = $False
				}
			}

			#Die nachfolgenden Schritte sind nur erforderlich, wenn sich oben ergeben hat
			if ($GoOnMovingFiles) {
				#Zielpfad ermitteln - Abhängig ob das Datum einfließen soll, oder nicht
				[String]$DestinationPath = $BasicPath + $DestinationSubPath
				if ($CreateSubFoldersForEachDate) {
					#den Namen des Unterordners abhängig vom Datum festlegen
					$AufnahmeDatumPath =  Get-FolderNameFromDate -Date (Get-ExifDataFromFile -FileName $File.FullName -Properties "Aufnahmedatum").Item("Aufnahmedatum")
					Trace-LogMessage -Message "ausgelesenes Aufnahmedatum: $AufnahmeDatumPath" -Level 8 -MessageType Confirmation -Indent 8
					$DestinationPath = $BasicPath + $AufnahmeDatumPath + "\" + "$DestinationSubPath"
					Trace-LogMessage -Message "Zielpfad: $DestinationPath" -Level 8 -MessageType Confirmation -Indent 8
				}
				#Prüfen, ob passender Unterordner existiert - sonst anlegen
				TestAndCreate-Path -FolderName $DestinationPath

				#Dateien in Unterordner verschieben
				Move-Item -Path $File.FullName -Destination $DestinationPath -Force
				$MoveCount++

				#also consider PartnerFiles, if requested
				if ($PartnerFilesSubPath.Length -gt 0) {
					[String]$DestinationPathPartner = $BasicPath + $PartnerFilesSubPath
					if ($CreateSubFoldersForEachDate) {
						#Wert für $AufnahmeDatumPath wurde oben schon bestimmt - es klappt nicht bei allen RAW-Dateien
						Trace-LogMessage -Message "ausgelesenes Aufnahmedatum: $AufnahmeDatumPath" -Level 8 -MessageType Confirmation -Indent 8
						$DestinationPathPartner = $BasicPath + $AufnahmeDatumPath + "\" + "$PartnerFilesSubPath"
					}
					TestAndCreate-Path -FolderName $DestinationPathPartner
					#test if the partnerfiles exist
					foreach ($complementaryfiletype in $ComplementaryFileTypes) { # zu vergleichende Dateitypen
						#each filetype looks like "*.cr2" or "*.jpeg"
						[String]$Type1 = ($File.Extension).Replace(".","").ToLower()
						[String]$Type2 = $complementaryfiletype.Replace("*.","").ToLower()
						$ComplementaryFile =  $File.FullName.ToLower().Replace($Type1,$Type2).toUpper() #Großschreibung beibehalten
						Trace-LogMessage -Message "Komplementäre Datei: $ComplementaryFile" -Level 8 -MessageType Confirmation -Indent 8

						#test if the complementary file exists
						if (Test-Path -PathType Leaf $ComplementaryFile) {
							#Dateien in Unterordner verschieben
							Move-Item -Path $ComplementaryFile -Destination $DestinationPathPartner -Force
							Trace-LogMessage -Message "Komplementäre Datei $ComplementaryFile nach $DestinationPathPartner verschoben" -Level 8 -MessageType Confirmation -Indent 8
							$MoveCount++
						}
					}
				}
				Trace-LogMessage -Message "$($File.FullName) nach $DestinationPath verschoben" -Level 7 -MessageType Info -Indent 7
			}
		}
		Trace-LogMessage -Message "Es wurden $MoveCount Dateien vom Typ: $Name verschoben" -Level 1 -MessageType Info -Indent 3
	}
}


<#
.SYNOPSIS
	TODO
.DESCRIPTION
	TODO
.PARAMETER $ReadHost
	TODO
.PARAMETER $BasicPath
	TODO
.PARAMETER $DestinationSubPath
	TODO
.PARAMETER $FileTypes
	TODO
.PARAMETER $AccessSubFoldersForEachDate
	TODO
#>
function Split-PanoramaFiles {
	Param (
		[Parameter(Mandatory=$true, Position=0)]
		[String]
		$BasicPath,
		[Parameter(Mandatory=$true, Position=1)]
		[String]
		$DestinationSubPath,
		[Parameter(Mandatory=$true, Position=2)]
		[String[]]
		$FileTypes,
		[Parameter(Mandatory=$false, Position=3)]
		[Boolean]
		$AccessSubFoldersForEachDate = $false
	)
	Process {
		#Pfade anpassen
		Get-NormalizedPath -FolderName $BasicPath | Out-Null
		Get-NormalizedPath -FolderName $DestinationSubPath | Out-Null
		Trace-LogMessage -Message "Sortiere Panoramen" -Level 1 -MessageType Confirmation -Indent 1

		#es muss unterschieden werden, zwischen einem einzelnen Ordner-Pfad (ohne Unterordner für den Tag) und mehreren Ordner-Pfaden
		[System.Collections.ArrayList]$PanoramaPaths = @()
		if ($AccessSubFoldersForEachDate) {
			#ermitteln der erstellten Unterordner für die Tage
			$DayFolderList = Get-ChildItem2 -Path $BasicPath -Directory
			#jeweils den Panorama-Unterordner zur Liste hinzufügen
			$DayFolderList | ForEach-Object {$PanoramaPaths.Add($_.FullName + "\$DestinationSubPath" ) | Out-Null}
		} else {
			#default: nur ein Pfad für die Panoramen
			$PanoramaPaths.Add($BasicPath + "$DestinationSubPath") | Out-Null
		}
		#jetzt werden die Panorama-Unterordner durchlaufen
		foreach ($SubFolderPanorama in $PanoramaPaths) {
			Trace-LogMessage -Message "Sortiere Panoramen" -Level 1 -MessageType Confirmation -Indent 1
			if (Test-Path -Path $SubFolderPanorama) {
				#Zähler für die Panoramen für die Benennung der Unterordner
				[int]$PanoramaCount = 0
				#Suche aller relevanten Dateien im Ordner
				$FoundFilesList = Get-ChildItem -Path ($SubFolderPanorama+"*") -Include $FileTypes -ErrorAction SilentlyContinue #Pfad muss auf * enden, damit mehrere Dateitypen gesucht werden können
				#es wird davon ausgegangen, dass alle Bilder für eine Panorama aufsteigende Dateinamen haben
				foreach ($file in $FoundFilesList) {
					#Es kann vorkommen, dass die Datei durch eine Panorama bereits verschoben wurde - dann ist kein Zugriff mehr möglich
					if (Test-Path -Path $file.FullName) {
						[System.Collections.ArrayList]$FilesForOnePanorama = @()
						#Die Datei selbst gehört immer zum Panorama ;-)
						[String]$CurrentFile = $file.FullName
						$FilesForOnePanorama.Add($CurrentFile)
						#für jede Datei wird geprüft, ob die nachfolgende Datei auch vorhanden ist
						#solange aufsteigend benannte Dateien vorhanden sind, ist davon auszugehen, dass es sich um ein zusammenhängendes Panorama handelt
						#zunächst wird der Sonderfall betrachtet, dass ein Panorama der Bezeichnung nach über die 9999-0001-Grenze hinweg existiert
						if ($file.FullName.Contains("0001")) { #Annahme Bezeichnungsschema von Canon
							#in diesem Fall werden zusätzlich die Vorgänger einbezogen
							$GoOn = $true #Variable, um Suche abbrechen zu können
							#solange suchen, wie die Suche erfolgreich ist
							while ($GoOn) {
								#ermitteln des Dateinamens
								[String]$FileBefore = Find-AlphaNumericSuccessorAndPredecessorFile $CurrentFile -Offset -1
								#falls diese Datei existiert, gehört sie zum Panorama
								if (Test-Path -Path $FileBefore) {
									#Aufnahme in die Liste
									$FilesForOnePanorama.Add($FileBefore) | Out-Null
									#weitere Vorgänger suchen
									$CurrentFile = $FileBefore
								} else {
									$GoOn = $false #Suche abbrechen
								}
							}
						}
						#in jedem Fall werden die nachfolgenden Dateien einbezogen
						[String]$CurrentFile = $file.FullName
						$GoOn = $true #Variable, um Suche abbrechen zu können
						#solange suchen, wie die Suche erfolgreich ist
						while ($GoOn) {
							#ermitteln des Dateinamens
							[String]$FileAfter = Find-AlphaNumericSuccessorAndPredecessorFile $CurrentFile -Offset 1
							#falls diese Datei existiert, gehört sie zum Panorama
							if (Test-Path -Path $FileAfter) {
								#Aufnahme in die Liste
								$FilesForOnePanorama.Add($FileAfter) | Out-Null
								#weitere Nachfolger suchen
								$CurrentFile = $FileAfter
							} else {
								$GoOn = $false #Suche abbrechen
							}
						}
						#jetzt müssen die gesammelten Dateien verschoben werden
						#anlegen des Unterordners - ggf. mit führender Null
						if (++$PanoramaCount -lt 10) {
							$PanSubFolder = $SubFolderPanorama + "Panorama 0" + $PanoramaCount #vorher einstellig
						} else {
							$PanSubFolder = $SubFolderPanorama + "Panorama " + $PanoramaCount #zweistellig
						}
						TestAndCreate-Path -FolderName $PanSubFolder
						#Verschieben aller Dateien
						$FilesForOnePanorama | ForEach-Object {Move-Item -Path $_ -Destination $PanSubFolder -Force}
						Trace-LogMessage -Message "Es wurden $($FilesForOnePanorama.Count) Dateien nach $PanSubFolder verschoben" -Level 1 -MessageType Info -Indent 3

					} else {
						Trace-LogMessage -Message "Übgerspringe Datei $file, da sie bereits verschoben wurde" -Level 7 -MessageType Info -Indent 7
					}
				}
			} else {
				Trace-LogMessage -Message "Es gibt keine Panoramen im Ordner $SubFolderPanorama" -Level 1 -MessageType Info -Indent 3
			}
		}
	}
}


<#
.SYNOPSIS
	TODO
.DESCRIPTION
	TODO
.PARAMETER $ReadHost
	TODO
.PARAMETER $BasicPath
	TODO
.PARAMETER $DestinationSubPath
	TODO
.PARAMETER $FileTypes
	TODO
.PARAMETER $AccessSubFoldersForEachDate
	TODO
#>
function Move-HDRFiles {
	Param (
		[Parameter(Mandatory=$true, Position=0)]
		[String]
		$BasicPath,
		[Parameter(Mandatory=$true, Position=1)]
		[String]
		$DestinationSubPath,
		[Parameter(Mandatory=$true, Position=2)]
		[String]
		$DestinationSubPathPartner,
		[Parameter(Mandatory=$true, Position=3)]
		[String[]]
		$FileTypes,
		[Parameter(Mandatory=$false, Position=4)]
		[String[]]
		$PartnerFileTypes = @(),
		[Parameter(Mandatory=$false, Position=5)]
		[Boolean]
		$AccessSubFoldersForEachDate = $false
	)
	Process {
		#Pfade anpassen
		Get-NormalizedPath -FolderName $BasicPath | Out-Null
		Get-NormalizedPath -FolderName $DestinationSubPath | Out-Null
		[int]$MoveCount = 0 #zählen der jeweils verschobenen Dateien
		Trace-LogMessage -Message "Sortiere HDR" -Level 1 -MessageType Confirmation -Indent 1

		#Suche aller RAW-Dateien im Ordner
		$FoundFilesList = Get-ChildItem -Path ($BasicPath+"*") -Include $FileTypes
		#Für jede Datei wird geprüft, ob Sie Teil einer HDR-Reihung (0-(-1)-1-(-2)-2) bzw. ((-2)-(-1)-0-1-2) bzw. (0-(-2)-(-1)-1-2) ist
		foreach ($file in $FoundFilesList) {
			#Es kann vorkommen, dass die Datei durch eine HDR-Reihung bereits verschoben wurde - dann ist kein Zugriff mehr möglich
			if (-not (Test-Path -Path $File.FullName)) {
				Trace-LogMessage -Message "Übgerspringe Datei $File, da sie bereits verschoben wurde" -Level 7 -MessageType Info -Indent 7
			} else {
				#es muss bei der Ordnerstruktur unterschieden werden, ob es eine zusätzliche Ebene für das Datum gibt, um den Zielordner zu definieren
				#der default-Wert ist ohne Datumsangabe und wird ggf. wieder überschrieben
				[String]$SubFolderHDR = $BasicPath + "$DestinationSubPath"
				[String]$SubFolderHDRPartner = $BasicPath + "$DestinationSubPathPartner"
				if ($AccessSubFoldersForEachDate) {
					#den Namen des Unterordners abhängig vom Datum festlegen
					$AufnahmeDatum =  Get-FolderNameFromDate -Date (Get-ExifDataFromFile -FileName $File.FullName -Properties "Aufnahmedatum").Item("Aufnahmedatum")
					$SubFolderHDR = $BasicPath + $AufnahmeDatum + "\$DestinationSubPath"
					$SubFolderHDRPartner = $BasicPath + $AufnahmeDatum + "\$DestinationSubPathPartner"
				}
				#Annahme, dass EXIF-Daten ausgelesen werden können, da JPG-Dateien durchsucht werden
				#dazu werden die Bilder mit Lichtwert "2 Schritt(e)" gesucht und geschaut ob die Bilder davor und danach dazu passen
				#die 2 Schritte sind der letzte Werte, somit gibt es keine Probleme mit ausgeschnittenen Dateien in den nächsten Schleifendurchläufen
				$Lichtwert = Get-ExifDataFromFile -FileName $file.FullName -Properties "Lichtwert"
				if ($Lichtwert.Item("Lichtwert") -eq "+2 Schritt(e)") {
					#vorhergehende Datei und folgende Datei prüfen
					#handelt es sich um eine HDR-Reihung, werdend die Bilder (beide Formate) verschoben
					#ermitteln der für die HDR-Reihung benötigten Dateinamen
					[String]$File1 = Find-AlphaNumericSuccessorAndPredecessorFile $file.FullName -Offset -4
					[String]$File2 = Find-AlphaNumericSuccessorAndPredecessorFile $file.FullName -Offset -3
					[String]$File3 = Find-AlphaNumericSuccessorAndPredecessorFile $file.FullName -Offset -2
					[String]$File4 = Find-AlphaNumericSuccessorAndPredecessorFile $file.FullName -Offset -1
					[String]$File5 = $file.FullName
					[Boolean]$GoOn = $True #ggf, kann frühzeitig abgebrochen werden
					#ermitteln der jeweiligen Lichtwerte - falls die Datei existiert
					if ((Test-Path -Path $File1) -and $goOn ) {
						$value1 = (Get-ExifDataFromFile -FileName $File1 -Properties "Lichtwert").Item("Lichtwert")
					} else {$goOn = $False} #sonst brauchen wir es gar nicht weiter zu probieren
					if ((Test-Path -Path $File2) -and $goOn) {
						$value2 = (Get-ExifDataFromFile -FileName $File2 -Properties "Lichtwert").Item("Lichtwert")
					} else {$goOn = $False} #sonst brauchen wir es gar nicht weiter zu probieren
					if ((Test-Path -Path $File3) -and $goOn) {
						$value3 = (Get-ExifDataFromFile -FileName $File3 -Properties "Lichtwert").Item("Lichtwert")
					} else {$goOn = $False} #sonst brauchen wir es gar nicht weiter zu probieren
					if ((Test-Path -Path $File4) -and $goOn) {
						$value4 = (Get-ExifDataFromFile -FileName $File4 -Properties "Lichtwert").Item("Lichtwert")
					} else {$goOn = $False} #sonst brauchen wir es gar nicht weiter zu probieren
					if ((Test-Path -Path $File5) -and $goOn) {
						$value5 = $Lichtwert.Item("Lichtwert")
					} else {$goOn = $False} #sonst brauchen wir es gar nicht weiter zu probieren
					#prüfen, ob die jeweiligen Lichtwerte in die Reihung passen
					#TODO: Mehr übersicht
					#TODO: mehr Performance
					#TODO: Flexibilität für HDR7 und HDR3
					if (($goOn -and $value1 -eq "‎0 Schritt(e)" -and $value2 -eq "‎-1 Schritt(e)" -and $value3 -eq "‎+1 Schritt(e)" -and $value4 -eq "‎-2 Schritt(e)" -and $value5 -eq "‎+2 Schritt(e)") -or `
						($goOn -and $value1 -eq "-2 Schritt(e)" -and $value2 -eq "‎-1 Schritt(e)" -and $value3 -eq "‎0 Schritt(e)" -and $value4 -eq "‎+1 Schritt(e)" -and $value5 -eq "‎+2 Schritt(e)") -or `
						($goOn -and $value1 -eq "0 Schritt(e)" -and $value2 -eq "‎-2 Schritt(e)" -and $value3 -eq "‎-1 Schritt(e)" -and $value4 -eq "‎+1 Schritt(e)" -and $value5 -eq "‎+2 Schritt(e)")) {
						#ist dem der Fall, werden die Dateien (beide Dateitypen) verschoben
						#nachdem sichergestellt wurde, dass beide Ordner existieren
						TestAndCreate-Path -FolderName $SubFolderHDR
						TestAndCreate-Path -FolderName $SubFolderHDRPartner

						#Dateinamen als Partner-Format (Groß- und Kleinschreibung)
						foreach ($partnerfiletype in $PartnerFileTypes) { # zu vergleichende Dateitypen
							#each filetype looks like "*.cr2" or "*.jpeg"
							[String]$Type1 = ($file.Extension).Replace(".","").ToLower()
							[String]$Type2 = $partnerfiletype.Replace("*.","").ToLower()
							[String]$PartnerFile1 = $File1.ToLower().Replace($Type1,$Type2).ToUpper() #Großschreibung beibehalten
							[String]$PartnerFile2 = $File2.ToLower().Replace($Type1,$Type2).ToUpper()
							[String]$PartnerFile3 = $File3.ToLower().Replace($Type1,$Type2).ToUpper()
							[String]$PartnerFile4 = $File4.ToLower().Replace($Type1,$Type2).ToUpper()
							[String]$PartnerFile5 = $File5.ToLower().Replace($Type1,$Type2).ToUpper()
							#erst die Partner-Dateien verschieben - natürlich nur wenn sie existieren
							if (Test-Path -Path $PartnerFile1 -PathType Leaf) { Move-Item -Path $PartnerFile1 -Destination $SubFolderHDRPartner -Force }
							if (Test-Path -Path $PartnerFile2 -PathType Leaf) { Move-Item -Path $PartnerFile2 -Destination $SubFolderHDRPartner -Force }
							if (Test-Path -Path $PartnerFile3 -PathType Leaf) { Move-Item -Path $PartnerFile3 -Destination $SubFolderHDRPartner -Force }
							if (Test-Path -Path $PartnerFile4 -PathType Leaf) { Move-Item -Path $PartnerFile4 -Destination $SubFolderHDRPartner -Force }
							if (Test-Path -Path $PartnerFile5 -PathType Leaf) { Move-Item -Path $PartnerFile5 -Destination $SubFolderHDRPartner -Force }
							#dann die Originale Verschieben - bei mehreren Partnertypen könnten diese bereits verschoben worden sein
							if (Test-Path -Path $File1 -PathType Leaf) { Move-Item -Path $File1 -Destination $SubFolderHDR -Force }
							if (Test-Path -Path $File2 -PathType Leaf) { Move-Item -Path $File2 -Destination $SubFolderHDR -Force }
							if (Test-Path -Path $File3 -PathType Leaf) { Move-Item -Path $File3 -Destination $SubFolderHDR -Force }
							if (Test-Path -Path $File4 -PathType Leaf) { Move-Item -Path $File4 -Destination $SubFolderHDR -Force }
							if (Test-Path -Path $File5 -PathType Leaf) { Move-Item -Path $File5 -Destination $SubFolderHDR -Force }
							$MoveCount += 5
							Trace-LogMessage -Message "$PartnerFile1 und $File1 und die vier jeweils folgenden Dateien nach $SubFolderHDRJPG und $SubFolderHDRRAW verschoben" -Level 1 -MessageType Info -Indent 3
						}
					} else {
						Trace-LogMessage -Message "Keine vollständige HDR5-Reihung um Datei $($file.Fullname)" -Level 1 -MessageType Warning -Indent 3
					}
				}
			}
		}
		Trace-LogMessage -Message "Es wurden $MoveCount HDR5-Dateien verschoben" -Level 1 -MessageType Info -Indent 3
	}
}